// ==============================================================================
// AttachmentsHandler
// Manages file attachments on a Job. Files are uploaded to S3; the S3 object
// key is stored on the Attachment record. Downloads use presigned S3 URLs
// (valid 15 min) rather than proxying bytes through the app server.
// Replaces AttachmentsController + ActiveStorage.
// ==============================================================================
package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net/http"
	"path/filepath"
	"strings"

	"github.com/gin-gonic/gin"
	"resumescorer/internal/models"
)

// AttachmentCreate handles POST /jobs/:job_id/attachments.
func (h *H) AttachmentCreate(c *gin.Context) {
	user := currentUser(c)
	job, ok := h.loadJobByParam(c, user, "job_id")
	if !ok {
		return
	}

	file, header, err := c.Request.FormFile("attachment[file]")
	if err != nil {
		h.setAlert(c, "No file provided.")
		c.Redirect(http.StatusFound, "/jobs/"+idStr(job.ID))
		return
	}
	defer file.Close()

	// Validate content type.
	ct := header.Header.Get("Content-Type")
	allowed := map[string]bool{
		"application/pdf": true,
		"application/msword": true,
		"application/vnd.openxmlformats-officedocument.wordprocessingml.document": true,
		"text/plain": true,
		"image/jpeg": true,
		"image/png":  true,
	}
	if !allowed[ct] {
		h.setAlert(c, "File must be a PDF, Word document, text file, or image.")
		c.Redirect(http.StatusFound, "/jobs/"+idStr(job.ID))
		return
	}

	// Validate size (10 MB cap).
	if header.Size > 10*1024*1024 {
		h.setAlert(c, "File must be under 10 MB.")
		c.Redirect(http.StatusFound, "/jobs/"+idStr(job.ID))
		return
	}

	filename := filepath.Base(header.Filename)
	// Build an S3 key that includes a UUID to prevent collisions.
	key := fmt.Sprintf("attachments/%d/%d/%s_%s",
		user.ID, job.ID, randHex(), sanitizeFilename(filename))

	if err := h.S3.Upload(c.Request.Context(), key, file, ct); err != nil {
		h.setAlert(c, "Upload failed. Please try again.")
		c.Redirect(http.StatusFound, "/jobs/"+idStr(job.ID))
		return
	}

	att := models.Attachment{
		JobID:    job.ID,
		UserID:   user.ID,
		Filename: filename,
		S3Key:    key,
	}
	if err := h.DB.Create(&att).Error; err != nil {
		h.setAlert(c, "Failed to save attachment.")
		c.Redirect(http.StatusFound, "/jobs/"+idStr(job.ID))
		return
	}

	h.setNotice(c, "Attachment added.")
	c.Redirect(http.StatusFound, "/jobs/"+idStr(job.ID))
}

// AttachmentDownload handles GET /jobs/:job_id/attachments/:id/download.
// Generates a presigned S3 URL and redirects the browser to it.
func (h *H) AttachmentDownload(c *gin.Context) {
	user := currentUser(c)
	job, ok := h.loadJobByParam(c, user, "job_id")
	if !ok {
		return
	}

	var att models.Attachment
	if err := h.DB.Where("id = ? AND job_id = ? AND user_id = ?",
		c.Param("id"), job.ID, user.ID).First(&att).Error; err != nil {
		c.Status(http.StatusNotFound)
		return
	}

	url, err := h.S3.PresignDownload(c.Request.Context(), att.S3Key, att.Filename)
	if err != nil {
		h.setAlert(c, "Could not generate download link.")
		c.Redirect(http.StatusFound, "/jobs/"+idStr(job.ID))
		return
	}
	c.Redirect(http.StatusFound, url)
}

// AttachmentDestroy handles DELETE /jobs/:job_id/attachments/:id.
func (h *H) AttachmentDestroy(c *gin.Context) {
	user := currentUser(c)
	job, ok := h.loadJobByParam(c, user, "job_id")
	if !ok {
		return
	}

	var att models.Attachment
	if err := h.DB.Where("id = ? AND job_id = ? AND user_id = ?",
		c.Param("id"), job.ID, user.ID).First(&att).Error; err != nil {
		c.Status(http.StatusNotFound)
		return
	}

	// Delete from S3 first; if the DB delete fails the orphan S3 object is
	// acceptable. The reverse (DB deleted, S3 not) would leave a broken link.
	h.S3.Delete(c.Request.Context(), att.S3Key)
	h.DB.Delete(&att)

	h.setNotice(c, "Attachment removed.")
	c.Redirect(http.StatusFound, "/jobs/"+idStr(job.ID))
}

// loadJobByParam is the same as loadJob but reads the job ID from the named
// URL parameter (used in nested routes: /jobs/:job_id/attachments/:id).
func (h *H) loadJobByParam(c *gin.Context, user *models.User, param string) (*models.Job, bool) {
	var job models.Job
	if err := h.DB.Where("id = ? AND user_id = ?", c.Param(param), user.ID).
		First(&job).Error; err != nil {
		c.Status(http.StatusNotFound)
		return nil, false
	}
	return &job, true
}

func randHex() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// sanitizeFilename strips path separators from a filename to prevent
// directory traversal when constructing S3 keys.
func sanitizeFilename(name string) string {
	name = filepath.Base(name)
	name = strings.ReplaceAll(name, "/", "_")
	name = strings.ReplaceAll(name, "\\", "_")
	return name
}
