// ==============================================================================
// Handler Helpers
// Shared utilities used by all route handlers: dependency container,
// template rendering, flash messages, and form validation errors.
// ==============================================================================
package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/sessions"
	"github.com/hibiken/asynq"
	"gorm.io/gorm"
	"resumescorer/internal/middleware"
	"resumescorer/internal/models"
	"resumescorer/internal/storage"
	"resumescorer/internal/tmpl"
)

// H is the dependency container shared by all handlers.
type H struct {
	DB      *gorm.DB
	Store   sessions.Store
	S3      *storage.Client
	Queue   *asynq.Client
	Tmpl    *tmpl.Templates
	AppHost string
}

// TD is shorthand for the template data map.
type TD map[string]any

// base builds the template data shared by every page render:
// the current user, flash messages, and the CSRF token.
func (h *H) base(c *gin.Context) TD {
	sess, _ := h.Store.Get(c.Request, middleware.SessionName)

	// Consume flash messages so they only appear once.
	var notice, alert string
	if msgs := sess.Flashes("notice"); len(msgs) > 0 {
		notice, _ = msgs[0].(string)
	}
	if msgs := sess.Flashes("alert"); len(msgs) > 0 {
		alert, _ = msgs[0].(string)
	}
	_ = sess.Save(c.Request, c.Writer)

	return TD{
		"CurrentUser": middleware.CurrentUser(c),
		"CSRF":        middleware.CSRFToken(c),
		"Notice":      notice,
		"Alert":       alert,
	}
}

// render writes a fully rendered HTML page to the response.
func (h *H) render(c *gin.Context, status int, page string, data TD) {
	c.Status(status)
	c.Header("Content-Type", "text/html; charset=utf-8")
	if err := h.Tmpl.Render(c.Writer, page, data); err != nil {
		c.String(http.StatusInternalServerError, "render error: %s", err)
	}
}

// setNotice stores a success flash message in the session.
func (h *H) setNotice(c *gin.Context, msg string) {
	sess, _ := h.Store.Get(c.Request, middleware.SessionName)
	sess.AddFlash(msg, "notice")
	_ = sess.Save(c.Request, c.Writer)
}

// setAlert stores an error flash message in the session.
func (h *H) setAlert(c *gin.Context, msg string) {
	sess, _ := h.Store.Get(c.Request, middleware.SessionName)
	sess.AddFlash(msg, "alert")
	_ = sess.Save(c.Request, c.Writer)
}

// currentUserOrAbort retrieves the current user or aborts with 401.
// Use this in handlers that are behind RequireAuth where the user is
// guaranteed to be loaded, as a typed convenience wrapper.
func currentUser(c *gin.Context) *models.User {
	return middleware.CurrentUser(c)
}
