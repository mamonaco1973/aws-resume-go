// ==============================================================================
// JobsHandler
// Manages the full lifecycle of a scoring request: submission, show, update
// (notes/folder move), and delete. Enqueues ScoringWorker tasks via Asynq.
// Replaces JobsController.
// ==============================================================================
package handlers

import (
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"resumescorer/internal/models"
	"resumescorer/internal/worker"
)

// JobNew renders GET /jobs/new — the scoring submission form.
func (h *H) JobNew(c *gin.Context) {
	user := currentUser(c)

	var resumes []models.Resume
	h.DB.Where("user_id = ?", user.ID).Order("name").Find(&resumes)

	if len(resumes) == 0 {
		h.setAlert(c, "Upload a resume before scoring jobs.")
		c.Redirect(http.StatusFound, "/resumes/new")
		return
	}

	var folders []models.Folder
	h.DB.Where("user_id = ?", user.ID).Order("name").Find(&folders)

	d := h.base(c)
	d["Resumes"] = resumes
	d["Folders"] = folders
	h.render(c, http.StatusOK, "jobs/new.html", d)
}

// JobCreate handles POST /jobs — validates, persists, and enqueues scoring.
func (h *H) JobCreate(c *gin.Context) {
	user := currentUser(c)

	// Scope resume lookup to the current user — a crafted resume_id for
	// another user returns nil rather than leaking data.
	resumeID := c.PostForm("resume_id")
	var resume models.Resume
	if err := h.DB.Where("id = ? AND user_id = ?", resumeID, user.ID).
		First(&resume).Error; err != nil {
		h.setAlert(c, "Add a resume before scoring jobs.")
		c.Redirect(http.StatusFound, "/resumes/new")
		return
	}

	sourceType := c.PostForm("source_type")
	folderID := nilOrUint(c.PostForm("folder_id"))

	if sourceType == "linkedin_id" {
		h.createLinkedInJobs(c, user, &resume, folderID)
		return
	}

	job := models.Job{
		UserID:     user.ID,
		ResumeID:   &resume.ID,
		FolderID:   folderID,
		SourceType: sourceType,
		URL:        strings.TrimSpace(c.PostForm("url")),
		RawText:    strings.TrimSpace(c.PostForm("raw_text")),
		Status:     "pending",
	}

	var errs []string
	if sourceType == "url" && job.URL == "" {
		errs = append(errs, "URL can't be blank.")
	}
	if sourceType == "raw_text" && job.RawText == "" {
		errs = append(errs, "Job description can't be blank.")
	}
	if sourceType != "url" && sourceType != "raw_text" {
		errs = append(errs, "Invalid source type.")
	}

	if len(errs) > 0 {
		var resumes []models.Resume
		h.DB.Where("user_id = ?", user.ID).Order("name").Find(&resumes)
		var folders []models.Folder
		h.DB.Where("user_id = ?", user.ID).Order("name").Find(&folders)
		d := h.base(c)
		d["Errors"] = errs
		d["Resumes"] = resumes
		d["Folders"] = folders
		h.render(c, http.StatusUnprocessableEntity, "jobs/new.html", d)
		return
	}

	if err := h.DB.Create(&job).Error; err != nil {
		h.setAlert(c, "Failed to create job.")
		c.Redirect(http.StatusFound, "/jobs/new")
		return
	}

	if err := worker.EnqueueScoring(h.Queue, job.ID); err != nil {
		h.setAlert(c, "Job saved but scoring could not be queued.")
	} else {
		h.setNotice(c, "Job submitted — scoring will begin shortly.")
	}
	c.Redirect(http.StatusFound, "/jobs/"+idStr(job.ID))
}

// createLinkedInJobs handles the LinkedIn batch path — one job per numeric ID.
func (h *H) createLinkedInJobs(c *gin.Context, user *models.User, resume *models.Resume, folderID *uint) {
	raw := c.PostForm("linkedin_ids")
	var ids []string
	for _, line := range strings.Split(raw, "\n") {
		var digits strings.Builder
		for _, r := range line {
			if r >= '0' && r <= '9' {
				digits.WriteRune(r)
			}
		}
		if s := digits.String(); s != "" {
			ids = append(ids, s)
		}
		if len(ids) >= 10 {
			break
		}
	}

	if len(ids) == 0 {
		var resumes []models.Resume
		h.DB.Where("user_id = ?", user.ID).Order("name").Find(&resumes)
		var folders []models.Folder
		h.DB.Where("user_id = ?", user.ID).Order("name").Find(&folders)
		d := h.base(c)
		d["Errors"] = []string{"Enter at least one LinkedIn job ID."}
		d["Resumes"] = resumes
		d["Folders"] = folders
		h.render(c, http.StatusUnprocessableEntity, "jobs/new.html", d)
		return
	}

	for _, lid := range ids {
		job := models.Job{
			UserID:     user.ID,
			ResumeID:   &resume.ID,
			FolderID:   folderID,
			SourceType: "url",
			// LinkedIn guest API returns full posting HTML without authentication.
			URL:    "https://www.linkedin.com/jobs-guest/jobs/api/jobPosting/" + lid,
			Status: "pending",
		}
		if err := h.DB.Create(&job).Error; err == nil {
			worker.EnqueueScoring(h.Queue, job.ID)
		}
	}

	plural := "job"
	if len(ids) > 1 {
		plural = "jobs"
	}
	h.setNotice(c, fmt.Sprintf("%d LinkedIn %s submitted for scoring.", len(ids), plural))
	c.Redirect(http.StatusFound, "/")
}

// JobShow renders GET /jobs/:id.
func (h *H) JobShow(c *gin.Context) {
	user := currentUser(c)
	job, ok := h.loadJob(c, user)
	if !ok {
		return
	}

	var attachments []models.Attachment
	h.DB.Where("job_id = ?", job.ID).Order("created_at desc").Find(&attachments)

	var folders []models.Folder
	h.DB.Where("user_id = ?", user.ID).Order("name").Find(&folders)

	d := h.base(c)
	d["Job"] = job
	d["Attachments"] = attachments
	d["Folders"] = folders
	h.render(c, http.StatusOK, "jobs/show.html", d)
}

// JobUpdate handles PATCH /jobs/:id — updates notes and/or folder assignment.
func (h *H) JobUpdate(c *gin.Context) {
	user := currentUser(c)
	job, ok := h.loadJob(c, user)
	if !ok {
		return
	}

	updates := map[string]any{
		"notes":     c.PostForm("notes"),
		"folder_id": nilOrUint(c.PostForm("folder_id")),
	}

	if err := h.DB.Model(job).Updates(updates).Error; err != nil {
		h.setAlert(c, "Failed to save.")
	} else {
		h.setNotice(c, "Saved.")
	}
	c.Redirect(http.StatusFound, "/jobs/"+idStr(job.ID))
}

// JobDestroy handles DELETE /jobs/:id.
func (h *H) JobDestroy(c *gin.Context) {
	user := currentUser(c)
	job, ok := h.loadJob(c, user)
	if !ok {
		return
	}
	h.DB.Delete(job)
	h.setNotice(c, "Job removed.")
	c.Redirect(http.StatusFound, "/")
}

// loadJob finds a job by :id scoped to the current user, returning 404 if
// not found. Preloads Resume and Folder for the show page.
func (h *H) loadJob(c *gin.Context, user *models.User) (*models.Job, bool) {
	var job models.Job
	if err := h.DB.Preload("Resume").Preload("Folder").
		Where("id = ? AND user_id = ?", c.Param("id"), user.ID).
		First(&job).Error; err != nil {
		c.Status(http.StatusNotFound)
		return nil, false
	}
	return &job, true
}

// nilOrUint converts a form field string to *uint, returning nil for blank
// or zero values. Used for nullable foreign keys like folder_id.
func nilOrUint(s string) *uint {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	n, err := strconv.ParseUint(s, 10, 64)
	if err != nil || n == 0 {
		return nil
	}
	v := uint(n)
	return &v
}

// idStr formats a uint primary key for URL construction.
func idStr(id uint) string {
	return strconv.FormatUint(uint64(id), 10)
}
