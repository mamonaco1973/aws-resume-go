// ==============================================================================
// ResumesHandler
// CRUD for Resume records (plain-text pastes). Replaces ResumesController.
// ==============================================================================
package handlers

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"resumescorer/internal/models"
)

// ResumeIndex renders GET /resumes.
func (h *H) ResumeIndex(c *gin.Context) {
	user := currentUser(c)
	var resumes []models.Resume
	h.DB.Where("user_id = ?", user.ID).Order("created_at desc").Find(&resumes)

	d := h.base(c)
	d["Resumes"] = resumes
	h.render(c, http.StatusOK, "resumes/index.html", d)
}

// ResumeNew renders GET /resumes/new.
func (h *H) ResumeNew(c *gin.Context) {
	d := h.base(c)
	h.render(c, http.StatusOK, "resumes/new.html", d)
}

// ResumeCreate handles POST /resumes.
func (h *H) ResumeCreate(c *gin.Context) {
	user := currentUser(c)
	name := strings.TrimSpace(c.PostForm("name"))
	content := strings.TrimSpace(c.PostForm("content_text"))

	var errs []string
	if name == "" {
		errs = append(errs, "Name can't be blank.")
	}
	if len(content) < 50 {
		errs = append(errs, "Resume text must be at least 50 characters.")
	}

	if len(errs) > 0 {
		d := h.base(c)
		d["Errors"] = errs
		d["Name"] = name
		d["ContentText"] = content
		h.render(c, http.StatusUnprocessableEntity, "resumes/new.html", d)
		return
	}

	resume := models.Resume{
		UserID:      user.ID,
		Name:        name,
		ContentText: content,
	}
	if err := h.DB.Create(&resume).Error; err != nil {
		h.setAlert(c, "Failed to save resume.")
		c.Redirect(http.StatusFound, "/resumes/new")
		return
	}

	h.setNotice(c, "Resume saved.")
	c.Redirect(http.StatusFound, "/resumes")
}

// ResumeShow renders GET /resumes/:id.
func (h *H) ResumeShow(c *gin.Context) {
	user := currentUser(c)
	resume, ok := h.loadResume(c, user)
	if !ok {
		return
	}
	d := h.base(c)
	d["Resume"] = resume
	h.render(c, http.StatusOK, "resumes/show.html", d)
}

// ResumeDestroy handles DELETE /resumes/:id.
func (h *H) ResumeDestroy(c *gin.Context) {
	user := currentUser(c)
	resume, ok := h.loadResume(c, user)
	if !ok {
		return
	}
	// Nullify resume_id on associated jobs before deleting. GORM's SET NULL
	// constraint handles this at the database level, but we use a raw update
	// here to be explicit and avoid GORM's association management overhead.
	h.DB.Model(&models.Job{}).Where("resume_id = ?", resume.ID).
		Update("resume_id", nil)
	h.DB.Delete(resume)

	h.setNotice(c, "Resume deleted.")
	c.Redirect(http.StatusFound, "/resumes")
}

func (h *H) loadResume(c *gin.Context, user *models.User) (*models.Resume, bool) {
	var resume models.Resume
	if err := h.DB.Where("id = ? AND user_id = ?", c.Param("id"), user.ID).
		First(&resume).Error; err != nil {
		c.Status(http.StatusNotFound)
		return nil, false
	}
	return &resume, true
}
