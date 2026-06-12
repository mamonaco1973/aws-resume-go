// ==============================================================================
// Middleware
// Provides Gin middleware for session-based authentication, CSRF protection,
// and HTML form method override (_method=DELETE/PATCH).
// ==============================================================================
package middleware

import (
	"crypto/rand"
	"encoding/hex"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/sessions"
	"gorm.io/gorm"
	"resumescorer/internal/models"
)

const SessionName = "resumescorer_session"

// RequireAuth rejects unauthenticated requests with a redirect to /signin.
// On success it stores the loaded *models.User under the key "current_user"
// in the Gin context so handlers can call CurrentUser(c).
func RequireAuth(store sessions.Store, db *gorm.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		sess, _ := store.Get(c.Request, SessionName)
		userID, ok := sess.Values["user_id"].(uint)
		if !ok || userID == 0 {
			c.Redirect(http.StatusFound, "/signin")
			c.Abort()
			return
		}
		var user models.User
		if err := db.First(&user, userID).Error; err != nil {
			// Session references a deleted user — clear it.
			sess.Values["user_id"] = uint(0)
			_ = sess.Save(c.Request, c.Writer)
			c.Redirect(http.StatusFound, "/signin")
			c.Abort()
			return
		}
		c.Set("current_user", &user)
		c.Next()
	}
}

// CurrentUser retrieves the authenticated user from the Gin context.
// Returns nil when called outside an authenticated route.
func CurrentUser(c *gin.Context) *models.User {
	if u, ok := c.Get("current_user"); ok {
		return u.(*models.User)
	}
	return nil
}

// CSRF generates a per-session token on first visit and validates it on
// state-changing requests (POST, PATCH, DELETE). The token is read from
// the _csrf form field or the X-CSRF-Token request header.
func CSRF(store sessions.Store) gin.HandlerFunc {
	return func(c *gin.Context) {
		sess, _ := store.Get(c.Request, SessionName)

		token, _ := sess.Values["csrf_token"].(string)
		if token == "" {
			token = generateToken()
			sess.Values["csrf_token"] = token
			_ = sess.Save(c.Request, c.Writer)
		}
		c.Set("csrf_token", token)

		m := c.Request.Method
		if m == http.MethodPost || m == http.MethodPatch ||
			m == http.MethodPut || m == http.MethodDelete {
			submitted := c.PostForm("_csrf")
			if submitted == "" {
				submitted = c.GetHeader("X-CSRF-Token")
			}
			if submitted != token {
				c.AbortWithStatus(http.StatusForbidden)
				return
			}
		}
		c.Next()
	}
}

// CSRFToken retrieves the CSRF token from the Gin context.
func CSRFToken(c *gin.Context) string {
	t, _ := c.Get("csrf_token")
	s, _ := t.(string)
	return s
}

// MethodOverride allows HTML forms to submit PATCH and DELETE requests by
// including a hidden _method field. The override is only applied to POST
// requests to prevent misuse of other methods.
func MethodOverride() gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.Request.Method == http.MethodPost {
			if m := c.PostForm("_method"); m == "DELETE" || m == "PATCH" || m == "PUT" {
				c.Request.Method = m
			}
		}
		c.Next()
	}
}

func generateToken() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
