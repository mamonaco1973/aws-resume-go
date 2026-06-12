// ==============================================================================
// DashboardHandler
// Serves the app home page — job list with search/folder filters and the
// Bedrock token usage ring. Replaces DashboardController + index.html.erb.
// ==============================================================================
package handlers

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"resumescorer/internal/models"
)

// Index renders GET / — the main dashboard.
func (h *H) DashboardIndex(c *gin.Context) {
	user := currentUser(c)

	q := strings.TrimSpace(c.Query("q"))
	folderID := c.Query("folder_id")

	// Build the query with optional filters. Using raw ILIKE for
	// case-insensitive keyword search on PostgreSQL.
	tx := h.DB.Preload("Resume").Preload("Folder").
		Where("user_id = ?", user.ID).
		Order("created_at desc")

	if q != "" {
		tx = tx.Where("title ILIKE ? OR company ILIKE ?", "%"+q+"%", "%"+q+"%")
	}
	if folderID != "" {
		tx = tx.Where("folder_id = ?", folderID)
	}

	var jobs []models.Job
	tx.Find(&jobs)

	var folders []models.Folder
	h.DB.Where("user_id = ?", user.ID).Order("name").Find(&folders)

	d := h.base(c)
	d["Jobs"] = jobs
	d["Folders"] = folders
	d["FilterQ"] = q
	d["FilterFolderID"] = folderID
	d["TokenPct"] = user.TokenUsagePct()
	d["TokensUsed"] = user.TokensUsed
	d["TokenLimit"] = user.TokenLimit

	// AnyProcessing signals the template to render the auto-refresh bar.
	anyProcessing := false
	for _, j := range jobs {
		if j.Processing() {
			anyProcessing = true
			break
		}
	}
	d["AnyProcessing"] = anyProcessing

	h.render(c, http.StatusOK, "dashboard/index.html", d)
}
