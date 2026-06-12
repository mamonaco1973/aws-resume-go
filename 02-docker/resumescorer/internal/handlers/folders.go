// ==============================================================================
// FoldersHandler
// CRUD for Folder records. Replaces FoldersController.
// ==============================================================================
package handlers

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"resumescorer/internal/models"
)

// FolderIndex renders GET /folders.
func (h *H) FolderIndex(c *gin.Context) {
	user := currentUser(c)
	var folders []models.Folder
	h.DB.Preload("Jobs").Where("user_id = ?", user.ID).Order("name").Find(&folders)

	d := h.base(c)
	d["Folders"] = folders
	h.render(c, http.StatusOK, "folders/index.html", d)
}

// FolderNew renders GET /folders/new.
func (h *H) FolderNew(c *gin.Context) {
	d := h.base(c)
	h.render(c, http.StatusOK, "folders/new.html", d)
}

// FolderCreate handles POST /folders.
func (h *H) FolderCreate(c *gin.Context) {
	user := currentUser(c)
	name := strings.TrimSpace(c.PostForm("name"))

	var errs []string
	if name == "" {
		errs = append(errs, "Name can't be blank.")
	}
	if len(name) > 100 {
		errs = append(errs, "Name is too long (max 100 characters).")
	}

	if len(errs) > 0 {
		d := h.base(c)
		d["Errors"] = errs
		d["Name"] = name
		h.render(c, http.StatusUnprocessableEntity, "folders/new.html", d)
		return
	}

	folder := models.Folder{UserID: user.ID, Name: name}
	if err := h.DB.Create(&folder).Error; err != nil {
		h.setAlert(c, "Failed to create folder.")
		c.Redirect(http.StatusFound, "/folders/new")
		return
	}

	h.setNotice(c, "Folder created.")
	c.Redirect(http.StatusFound, "/folders")
}

// FolderDestroy handles DELETE /folders/:id.
func (h *H) FolderDestroy(c *gin.Context) {
	user := currentUser(c)
	var folder models.Folder
	if err := h.DB.Where("id = ? AND user_id = ?", c.Param("id"), user.ID).
		First(&folder).Error; err != nil {
		c.Status(http.StatusNotFound)
		return
	}
	// Nullify folder_id on jobs before deleting the folder.
	h.DB.Model(&models.Job{}).Where("folder_id = ?", folder.ID).
		Update("folder_id", nil)
	h.DB.Delete(&folder)

	h.setNotice(c, "Folder deleted. Jobs were unassigned.")
	c.Redirect(http.StatusFound, "/folders")
}
