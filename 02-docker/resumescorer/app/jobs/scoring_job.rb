require "net/http"
require "json"

# ==============================================================================
# ScoringJob
# Sidekiq background job that scores a resume against a job posting.
# Runs asynchronously — the HTTP request that created the Job returns
# immediately, and this job runs in a separate worker process.
#
# Two-phase Bedrock pipeline:
#   Phase 1 — Extraction: fetch the job source (URL or raw text), strip
#     noise, and ask Claude to extract a normalised job_title, company,
#     and job_text. Updating title/company immediately lets the dashboard
#     show meaningful data while Phase 2 is still running.
#
#   Phase 2 — Scoring: ask Claude to score the resume text against the
#     extracted job_text on a 0–100 scale with a written analysis.
#
# Token usage from both calls is accumulated on the user record. If the
# user hits their cap mid-job, the job is marked as an error.
# ==============================================================================
class ScoringJob < ApplicationJob
  queue_as :default

  # MAX_SOURCE_CHARS limits how much text we send to Bedrock per call.
  # Claude's context window is large but per-token cost scales linearly.
  MAX_SOURCE_CHARS  = 120_000

  # Jobs shorter than this after extraction are probably not real job
  # postings (e.g. a login wall returned instead of the actual page).
  MIN_JOB_CHARS     = 100

  BEDROCK_MODEL_ENV = "BEDROCK_MODEL_ID"

  # perform is the entry point called by Sidekiq. The argument is the
  # Job's integer id, not the object itself. ActiveJob serialises
  # arguments to JSON for Redis storage; passing the id (a plain integer)
  # is safer than passing the record (which would be serialised with
  # GlobalID and could reference a stale/deleted record on retry).
  def perform(job_id)
    # find_by returns nil instead of raising if the job was deleted
    # between enqueue and execution — a valid race condition.
    @job  = Job.find_by(id: job_id)
    return unless @job

    @user   = @job.user
    @resume = @job.resume

    # Check the token cap before consuming any API credits. over_token_limit?
    # compares tokens_used to the configurable per-user limit on the User record.
    return mark_error("Token limit reached. This job was not scored.") \
      if @user.over_token_limit?

    # Set status to "scoring" so the dashboard shows the job as in-flight
    # and the auto-refresh JS keeps polling.
    @job.update!(status: "scoring", status_message: "Started job scoring")

    resume_text = @resume.content_text.to_s.strip
    return mark_error("Resume has no text content — re-upload the file.") \
      if resume_text.blank?

    # Phase 1: extract structured job data from the raw source.
    # extract_job_description returns the cleaned job_text string, or nil
    # if something went wrong (it calls mark_error internally in that case).
    job_text = extract_job_description
    # Reload status — mark_error may have set it to "error" inside the
    # method. We use reload here because @job is an in-memory object and
    # could reflect a stale status.
    return if @job.reload.status == "error"

    # Re-check the token cap after Phase 1 — extraction can consume
    # several hundred tokens even for a short job posting.
    return mark_error("Token limit reached after extraction.") \
      if @user.reload.over_token_limit?

    # Phase 2: score the resume against the extracted job text.
    scored = score_resume(resume_text, job_text)
    return if @job.reload.status == "error"

    @job.update!(
      job_description_text: job_text,
      score:                Integer(scored["score"]),
      analysis:             scored["summary"].to_s.strip,
      status:               "scored",
      status_message:       ""
    )
  rescue => e
    # Catch-all rescues any unexpected exception and marks the job as
    # errored with a truncated message rather than crashing the Sidekiq
    # worker and leaving the job stuck in "scoring" forever.
    mark_error(e.message.to_s.truncate(500)) if @job
  end

  private

  # ------------------------------------------------------------------------------
  # Phase 1 — Job description extraction
  # For URL jobs: fetch the page HTML, strip noise, call Bedrock to
  # extract title/company/job_text as structured JSON.
  # For raw_text jobs: send the pasted text directly to Bedrock.
  # ------------------------------------------------------------------------------

  def extract_job_description
    raw = if @job.source_type == "url"
            html = fetch_url(@job.url)
            # fetch_url calls mark_error and returns nil on network failure.
            return nil unless html
            extract_visible_text(html)
          else
            @job.raw_text.to_s
          end

    if raw.blank?
      mark_error("No text could be extracted from the source")
      return nil
    end

    # Ask Bedrock to normalise the raw text into structured JSON with
    # three fields: job_title, company_name, job_text. max_tokens: 1000
    # is enough for the extraction response; the bulk of tokens are in
    # the input (the raw source text).
    extracted = call_bedrock(extraction_prompt(raw), max_tokens: 1000)
    return nil if extracted.nil?

    # strip_fences removes markdown code fences that Claude sometimes
    # wraps around JSON responses despite being told not to.
    parsed = JSON.parse(strip_fences(extracted))

    title   = parsed["job_title"].to_s.strip
    company = parsed["company_name"].to_s.strip
    text    = parsed["job_text"].to_s.strip

    if text.length < MIN_JOB_CHARS
      mark_error("Extracted job description is too short to score")
      return nil
    end

    # Update title and company immediately so the dashboard shows them
    # while the slower Phase 2 scoring call is still in progress.
    @job.update!(title: title, company: company)

    text
  rescue JSON::ParserError
    mark_error("Bedrock returned invalid JSON during extraction")
    nil
  end

  # ------------------------------------------------------------------------------
  # Phase 2 — Resume scoring
  # Returns the parsed JSON hash with "score" (integer 0-100) and
  # "summary" (three-paragraph analysis string).
  # ------------------------------------------------------------------------------

  def score_resume(resume_text, job_text)
    # max_tokens: 4000 accommodates the full Overview/Strengths/Weaknesses
    # analysis. Extraction only needs ~1000 because the output is compact JSON.
    raw = call_bedrock(scoring_prompt(resume_text, job_text), max_tokens: 4000)
    return nil if raw.nil?

    parsed = JSON.parse(strip_fences(raw))
    score  = parsed["score"]

    # Bedrock occasionally returns score as a string ("82") rather than
    # an integer (82) even when the prompt says "integer". Coerce defensively.
    score = Integer(score.to_s.strip) if score.is_a?(String)

    unless score.is_a?(Integer) && score.between?(0, 100)
      mark_error("Bedrock returned an invalid score value")
      return nil
    end

    if parsed["summary"].to_s.strip.blank?
      mark_error("Bedrock did not return analysis text")
      return nil
    end

    parsed
  rescue JSON::ParserError
    mark_error("Bedrock returned invalid JSON during scoring")
    nil
  end

  # ------------------------------------------------------------------------------
  # Bedrock API call wrapper
  # Constructs the Anthropic Messages API payload, calls the Bedrock
  # InvokeModel endpoint, and accumulates token usage on the user record.
  # The AWS SDK reads region and credentials from the ECS task's IAM role
  # — no explicit credentials are needed in the code.
  # ------------------------------------------------------------------------------

  def call_bedrock(prompt, max_tokens:)
    client = Aws::BedrockRuntime::Client.new(
      region: ENV.fetch("AWS_REGION", "us-east-1")
    )
    model  = ENV.fetch(BEDROCK_MODEL_ENV, "us.anthropic.claude-haiku-4-5-20251001-v1:0")

    # Anthropic Messages API format. temperature: 0 makes responses
    # deterministic — important for scoring consistency across retries.
    body = {
      anthropic_version: "bedrock-2023-05-31",
      max_tokens:        max_tokens,
      temperature:       0,
      messages: [{
        role:    "user",
        content: [{ type: "text", text: prompt }]
      }]
    }.to_json

    response = client.invoke_model(
      model_id:     model,
      body:         body,
      content_type: "application/json",
      accept:       "application/json"
    )

    # response.body is an IO stream — read it once into a string, then parse.
    payload = JSON.parse(response.body.read)
    usage   = payload.fetch("usage", {})

    # Accumulate tokens after every successful Bedrock call so the usage
    # ring on the dashboard reflects real-time consumption.
    accumulate_tokens(
      usage.fetch("input_tokens", 0).to_i,
      usage.fetch("output_tokens", 0).to_i
    )

    # content[0]["text"] is the model's text response in the Messages API.
    payload.dig("content", 0, "text")
  rescue Aws::BedrockRuntime::Errors::ServiceError => e
    mark_error("Bedrock error: #{e.message.truncate(200)}")
    nil
  end

  def accumulate_tokens(input, output)
    total = input + output
    return if total <= 0
    # with_lock acquires a row-level lock on the user record before the
    # increment. This prevents a race condition where two concurrent
    # ScoringJobs for the same user both read tokens_used = 500, each
    # add 100, and both write 600 (instead of the correct 700).
    @user.with_lock { @user.increment!(:tokens_used, total) }
  rescue => e
    Rails.logger.warn("ScoringJob: token accumulation failed: #{e.message}")
  end

  # ------------------------------------------------------------------------------
  # Prompts
  # These match the extraction and scoring logic from the original Python
  # worker (aws-resume-app/01-core/code/worker.py) so results are
  # consistent when comparing the two implementations.
  # ------------------------------------------------------------------------------

  def extraction_prompt(source_text)
    <<~PROMPT.strip
      You are extracting structured data from a job posting.

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
      #{source_text.slice(0, MAX_SOURCE_CHARS)}
    PROMPT
  end

  def scoring_prompt(resume_text, job_text)
    <<~PROMPT.strip
      You are scoring a resume against a job description.

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
      #{resume_text.slice(0, MAX_SOURCE_CHARS)}

      JOB DESCRIPTION:
      #{job_text.slice(0, MAX_SOURCE_CHARS)}
    PROMPT
  end

  # ------------------------------------------------------------------------------
  # URL fetching and HTML text extraction
  # ------------------------------------------------------------------------------

  def fetch_url(url)
    uri      = URI.parse(url)
    use_ssl  = uri.scheme == "https"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: use_ssl,
                               read_timeout: 30, open_timeout: 10) do |http|
      req = Net::HTTP::Get.new(uri)
      # Spoof a real browser User-Agent — many job boards (including
      # LinkedIn) return empty content or a redirect for non-browser
      # requests identified by a generic or missing User-Agent.
      req["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " \
                          "AppleWebKit/537.36 (KHTML, like Gecko) " \
                          "Chrome/122.0.0.0 Safari/537.36"
      http.request(req)
    end
    response.body.force_encoding("UTF-8").encode("UTF-8", invalid: :replace)
  rescue => e
    mark_error("Failed to fetch URL: #{e.message.truncate(200)}")
    nil
  end

  def extract_visible_text(html)
    require "nokogiri"
    doc = Nokogiri::HTML(html)

    # Remove elements that never contain useful job description content.
    # Leaving scripts and nav in the text bloats the token count and
    # confuses the extraction prompt with irrelevant noise.
    doc.css("script, style, noscript, nav, footer, header, " \
            "svg, img, form, input, button, select, iframe").remove

    text = doc.text.gsub(/[ \t\f\v]+/, " ")
                   .gsub(/ *\n */, "\n")
                   .gsub(/\n{3,}/, "\n\n")
                   .strip

    # Prepend the page title as a hint for the extraction prompt — many
    # job boards put the job title and company name in the <title> tag.
    title = doc.at_css("title")&.text&.strip
    [title.present? ? "PAGE TITLE: #{title}" : nil, text].compact.join("\n\n")
  end

  # ------------------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------------------

  # Removes Markdown code fences that Claude sometimes wraps around JSON
  # despite being instructed not to. The prompt says "Do not wrap the
  # response in markdown" but Claude occasionally ignores this, especially
  # for JSON that looks like code. strip_fences makes the parsing robust.
  def strip_fences(text)
    text = text.strip
    return text unless text.start_with?("```")
    lines = text.lines
    lines.shift                       # remove opening ``` or ```json line
    lines.pop if lines.last&.strip == "```"
    lines.join.strip
  end

  def mark_error(message)
    @job&.update(status: "error", status_message: message.to_s.truncate(500))
  end
end
