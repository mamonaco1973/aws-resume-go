// ==============================================================================
// ScoringWorker
// Asynq background worker that scores a resume against a job posting.
// Replaces the Rails ScoringJob / Sidekiq implementation.
//
// Two-phase Bedrock pipeline (identical logic to the original Ruby worker):
//   Phase 1 — Extraction: fetch the job source (URL or raw text), strip
//     noise, and ask Claude to extract job_title, company, and job_text.
//   Phase 2 — Scoring: ask Claude to score the resume vs the extracted
//     job_text (0-100 integer + written analysis).
//
// Token usage from both calls is accumulated on the user record via an
// atomic SQL UPDATE.
// ==============================================================================
package worker

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/bedrockruntime"
	"github.com/hibiken/asynq"
	"gorm.io/gorm"
	"golang.org/x/net/html"
	"resumescorer/internal/models"
)

const (
	TaskTypeScoring = "scoring:process"
	maxSourceChars  = 120_000
	minJobChars     = 100
)

// ScoringPayload is the JSON-serialised argument enqueued with each task.
type ScoringPayload struct {
	JobID uint `json:"job_id"`
}

// Worker holds the dependencies needed to process scoring tasks.
type Worker struct {
	db     *gorm.DB
	region string
	model  string
}

// New returns a Worker. region and model are read from config at startup.
func New(db *gorm.DB, region, model string) *Worker {
	return &Worker{db: db, region: region, model: model}
}

// EnqueueScoring pushes a scoring task onto the Asynq Redis queue.
// Called by the jobs handler immediately after the Job record is created.
func EnqueueScoring(client *asynq.Client, jobID uint) error {
	payload, err := json.Marshal(ScoringPayload{JobID: jobID})
	if err != nil {
		return err
	}
	task := asynq.NewTask(TaskTypeScoring, payload)
	_, err = client.Enqueue(task)
	return err
}

// ProcessTask is the Asynq handler for TaskTypeScoring. It is registered in
// main.go via mux.HandleFunc(TaskTypeScoring, worker.ProcessTask).
func (w *Worker) ProcessTask(ctx context.Context, t *asynq.Task) error {
	var p ScoringPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("unmarshal payload: %w", err)
	}

	var job models.Job
	if err := w.db.Preload("Resume").Preload("User").First(&job, p.JobID).Error; err != nil {
		// Job was deleted between enqueue and execution — not an error.
		return nil
	}

	user := job.Resume
	_ = user // loaded via Preload below

	// Load user separately to get token fields.
	var dbUser models.User
	if err := w.db.First(&dbUser, job.UserID).Error; err != nil {
		return nil
	}

	if dbUser.OverTokenLimit() {
		return w.markError(&job, "Token limit reached. This job was not scored.")
	}

	w.db.Model(&job).Updates(map[string]any{
		"status":         "scoring",
		"status_message": "Started job scoring",
	})

	resumeText := strings.TrimSpace(job.Resume.ContentText)
	if resumeText == "" {
		return w.markError(&job, "Resume has no text content.")
	}

	// Phase 1: extract structured job data from the raw source.
	jobText, err := w.extractJobDescription(ctx, &job)
	if err != nil {
		return nil // markError already called inside
	}

	// Reload user to get post-extraction token count before Phase 2.
	w.db.First(&dbUser, job.UserID)
	if dbUser.OverTokenLimit() {
		return w.markError(&job, "Token limit reached after extraction.")
	}

	// Phase 2: score the resume against the extracted job text.
	scored, err := w.scoreResume(ctx, &job, resumeText, jobText)
	if err != nil {
		return nil
	}

	score := scored["score"].(int)
	summary := strings.TrimSpace(scored["summary"].(string))

	return w.db.Model(&job).Updates(map[string]any{
		"job_description_text": jobText,
		"score":               score,
		"analysis":            summary,
		"status":              "scored",
		"status_message":      "",
	}).Error
}

// ------------------------------------------------------------------------------
// Phase 1 — extraction
// ------------------------------------------------------------------------------

func (w *Worker) extractJobDescription(ctx context.Context, job *models.Job) (string, error) {
	var raw string
	if job.SourceType == "url" {
		html, err := fetchURL(job.URL)
		if err != nil {
			w.markError(job, fmt.Sprintf("Failed to fetch URL: %s", err.Error()))
			return "", err
		}
		raw = extractVisibleText(html)
	} else {
		raw = job.RawText
	}

	if strings.TrimSpace(raw) == "" {
		w.markError(job, "No text could be extracted from the source")
		return "", fmt.Errorf("empty source text")
	}

	extracted, inputTok, outputTok, err := w.callBedrock(ctx, extractionPrompt(raw), 1000)
	if err != nil {
		w.markError(job, fmt.Sprintf("Bedrock error: %s", err.Error()))
		return "", err
	}
	models.AccumulateTokens(w.db, job.UserID, inputTok+outputTok)

	var parsed map[string]any
	if err := json.Unmarshal([]byte(stripFences(extracted)), &parsed); err != nil {
		w.markError(job, "Bedrock returned invalid JSON during extraction")
		return "", err
	}

	title, _ := parsed["job_title"].(string)
	company, _ := parsed["company_name"].(string)
	jobText, _ := parsed["job_text"].(string)
	title = strings.TrimSpace(title)
	company = strings.TrimSpace(company)
	jobText = strings.TrimSpace(jobText)

	if len(jobText) < minJobChars {
		w.markError(job, "Extracted job description is too short to score")
		return "", fmt.Errorf("job text too short")
	}

	// Update title and company immediately so the dashboard shows them
	// while the slower Phase 2 scoring call is still in progress.
	w.db.Model(job).Updates(map[string]any{"title": title, "company": company})

	return jobText, nil
}

// ------------------------------------------------------------------------------
// Phase 2 — scoring
// ------------------------------------------------------------------------------

func (w *Worker) scoreResume(ctx context.Context, job *models.Job, resumeText, jobText string) (map[string]any, error) {
	raw, inputTok, outputTok, err := w.callBedrock(ctx, scoringPrompt(resumeText, jobText), 4000)
	if err != nil {
		w.markError(job, fmt.Sprintf("Bedrock error: %s", err.Error()))
		return nil, err
	}
	models.AccumulateTokens(w.db, job.UserID, inputTok+outputTok)

	var parsed map[string]any
	if err := json.Unmarshal([]byte(stripFences(raw)), &parsed); err != nil {
		w.markError(job, "Bedrock returned invalid JSON during scoring")
		return nil, err
	}

	// Coerce score to int — Bedrock occasionally returns it as a float or string.
	var score int
	switch v := parsed["score"].(type) {
	case float64:
		score = int(v)
	case string:
		fmt.Sscanf(v, "%d", &score)
	default:
		w.markError(job, "Bedrock returned an invalid score value")
		return nil, fmt.Errorf("invalid score type")
	}
	if score < 0 || score > 100 {
		w.markError(job, "Bedrock returned an out-of-range score")
		return nil, fmt.Errorf("score out of range: %d", score)
	}

	summary, _ := parsed["summary"].(string)
	if strings.TrimSpace(summary) == "" {
		w.markError(job, "Bedrock did not return analysis text")
		return nil, fmt.Errorf("empty summary")
	}

	return map[string]any{"score": score, "summary": summary}, nil
}

// ------------------------------------------------------------------------------
// Bedrock API call
// ------------------------------------------------------------------------------

type bedrockRequest struct {
	AnthropicVersion string           `json:"anthropic_version"`
	MaxTokens        int              `json:"max_tokens"`
	Temperature      float64          `json:"temperature"`
	Messages         []bedrockMessage `json:"messages"`
}

type bedrockMessage struct {
	Role    string           `json:"role"`
	Content []bedrockContent `json:"content"`
}

type bedrockContent struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

type bedrockResponse struct {
	Content []struct {
		Text string `json:"text"`
	} `json:"content"`
	Usage struct {
		InputTokens  int `json:"input_tokens"`
		OutputTokens int `json:"output_tokens"`
	} `json:"usage"`
}

// callBedrock invokes the Anthropic Messages API via Bedrock InvokeModel.
// temperature:0 makes responses deterministic — important for score consistency.
func (w *Worker) callBedrock(ctx context.Context, prompt string, maxTokens int) (string, int, int, error) {
	cfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(w.region))
	if err != nil {
		return "", 0, 0, err
	}
	client := bedrockruntime.NewFromConfig(cfg)

	reqBody := bedrockRequest{
		AnthropicVersion: "bedrock-2023-05-31",
		MaxTokens:        maxTokens,
		Temperature:      0,
		Messages: []bedrockMessage{{
			Role:    "user",
			Content: []bedrockContent{{Type: "text", Text: prompt}},
		}},
	}
	body, _ := json.Marshal(reqBody)

	resp, err := client.InvokeModel(ctx, &bedrockruntime.InvokeModelInput{
		ModelId:     aws.String(w.model),
		Body:        body,
		ContentType: aws.String("application/json"),
		Accept:      aws.String("application/json"),
	})
	if err != nil {
		return "", 0, 0, err
	}

	var result bedrockResponse
	if err := json.Unmarshal(resp.Body, &result); err != nil {
		return "", 0, 0, err
	}

	text := ""
	if len(result.Content) > 0 {
		text = result.Content[0].Text
	}
	return text, result.Usage.InputTokens, result.Usage.OutputTokens, nil
}

// ------------------------------------------------------------------------------
// Prompts — identical to the original Ruby worker prompts
// ------------------------------------------------------------------------------

func extractionPrompt(sourceText string) string {
	if len(sourceText) > maxSourceChars {
		sourceText = sourceText[:maxSourceChars]
	}
	return fmt.Sprintf(`You are extracting structured data from a job posting.

Return valid JSON only.

Required JSON fields:
- job_title
- company_name
- job_text

Rules:
- job_title: best extracted job title, or empty string if unknown
- company_name: best extracted company name, or empty string if unknown
- job_text: plain-text job description, maximum 3000 characters, include
  only role responsibilities and candidate requirements
- Do not wrap the response in markdown
- Do not include any explanation

SOURCE TEXT:
%s`, sourceText)
}

func scoringPrompt(resumeText, jobText string) string {
	if len(resumeText) > maxSourceChars {
		resumeText = resumeText[:maxSourceChars]
	}
	if len(jobText) > maxSourceChars {
		jobText = jobText[:maxSourceChars]
	}
	return fmt.Sprintf(`You are scoring a resume against a job description.

Return valid JSON only.

Required JSON fields:
- score
- summary

Rules:
- score: integer from 0 to 100
- summary: plain-text analysis with exactly three labeled paragraphs in
  this order: "Overview:" (2-3 sentences explaining why the score is
  what it is), "Strengths:" (2-3 sentences on resume positives relative
  to the job), "Weaknesses:" (2-3 sentences on gaps or missing
  qualifications)
- Do not wrap the response in markdown
- Do not include any explanation outside the JSON

RESUME:
%s

JOB DESCRIPTION:
%s`, resumeText, jobText)
}

// ------------------------------------------------------------------------------
// URL fetching and HTML text extraction
// ------------------------------------------------------------------------------

// fetchURL makes an HTTP GET with a browser User-Agent header. Many job boards
// return empty content or a redirect for non-browser User-Agent strings.
func fetchURL(url string) (string, error) {
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent",
		"Mozilla/5.0 (Windows NT 10.0; Win64; x64) "+
			"AppleWebKit/537.36 (KHTML, like Gecko) "+
			"Chrome/122.0.0.0 Safari/537.36")

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	return string(body), nil
}

// skipTags lists HTML elements whose subtrees are stripped during text
// extraction — they never contain useful job description content but
// inflate the token count when sent to Bedrock.
var skipTags = map[string]bool{
	"script": true, "style": true, "noscript": true,
	"nav": true, "footer": true, "header": true,
	"svg": true, "img": true, "form": true,
	"input": true, "button": true, "select": true,
	"iframe": true,
}

// extractVisibleText parses HTML and returns normalised plain text, mirroring
// the Nokogiri extraction logic in the original Ruby scoring_job.rb.
func extractVisibleText(htmlStr string) string {
	doc, err := html.Parse(strings.NewReader(htmlStr))
	if err != nil {
		return ""
	}

	var title string
	var buf strings.Builder

	var traverse func(*html.Node)
	traverse = func(n *html.Node) {
		if n.Type == html.ElementNode {
			if skipTags[n.Data] {
				return
			}
			// Capture <title> text for the extraction prompt hint.
			if n.Data == "title" && n.FirstChild != nil {
				title = strings.TrimSpace(n.FirstChild.Data)
				return
			}
		}
		if n.Type == html.TextNode {
			buf.WriteString(n.Data)
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			traverse(c)
		}
	}
	traverse(doc)

	text := buf.String()
	// Normalise whitespace to match the Ruby version's output.
	reSpace := regexp.MustCompile(`[ \t\f\v]+`)
	text = reSpace.ReplaceAllString(text, " ")
	reNewline := regexp.MustCompile(` *\n *`)
	text = reNewline.ReplaceAllString(text, "\n")
	reBlank := regexp.MustCompile(`\n{3,}`)
	text = reBlank.ReplaceAllString(text, "\n\n")
	text = strings.TrimSpace(text)

	if title != "" {
		return "PAGE TITLE: " + title + "\n\n" + text
	}
	return text
}

// stripFences removes Markdown code fences that Claude sometimes wraps around
// JSON responses despite being instructed not to.
func stripFences(text string) string {
	text = strings.TrimSpace(text)
	if !strings.HasPrefix(text, "```") {
		return text
	}
	lines := strings.Split(text, "\n")
	// Drop opening ``` or ```json line.
	lines = lines[1:]
	// Drop closing ``` line if present.
	if len(lines) > 0 && strings.TrimSpace(lines[len(lines)-1]) == "```" {
		lines = lines[:len(lines)-1]
	}
	return strings.TrimSpace(strings.Join(lines, "\n"))
}

// markError updates the job status to "error" and records the message.
func (w *Worker) markError(job *models.Job, msg string) error {
	if len(msg) > 500 {
		msg = msg[:500]
	}
	return w.db.Model(job).Updates(map[string]any{
		"status":         "error",
		"status_message": msg,
	}).Error
}
