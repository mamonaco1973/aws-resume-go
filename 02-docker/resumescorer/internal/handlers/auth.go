// ==============================================================================
// AuthHandler
// Handles sign-in, sign-up, and sign-out. Manages the gorilla/sessions
// cookie. Replaces Devise sessions and registrations controllers.
// ==============================================================================
package handlers

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"resumescorer/internal/middleware"
	"resumescorer/internal/models"
)

// ShowSignIn renders GET /signin.
func (h *H) ShowSignIn(c *gin.Context) {
	d := h.base(c)
	h.render(c, http.StatusOK, "auth/signin.html", d)
}

// SignIn handles POST /signin — validates credentials and writes the session.
func (h *H) SignIn(c *gin.Context) {
	email := strings.TrimSpace(c.PostForm("email"))
	password := c.PostForm("password")

	var user models.User
	if err := h.DB.Where("email = ?", email).First(&user).Error; err != nil ||
		!user.CheckPassword(password) {
		d := h.base(c)
		d["Error"] = "Invalid email or password."
		h.render(c, http.StatusUnprocessableEntity, "auth/signin.html", d)
		return
	}

	sess, _ := h.Store.Get(c.Request, middleware.SessionName)
	sess.Values["user_id"] = user.ID
	_ = sess.Save(c.Request, c.Writer)

	c.Redirect(http.StatusFound, "/")
}

// ShowSignUp renders GET /signup.
func (h *H) ShowSignUp(c *gin.Context) {
	d := h.base(c)
	h.render(c, http.StatusOK, "auth/signup.html", d)
}

// SignUp handles POST /signup — creates a new user account.
func (h *H) SignUp(c *gin.Context) {
	email := strings.TrimSpace(c.PostForm("email"))
	password := c.PostForm("password")
	confirm := c.PostForm("password_confirmation")

	d := h.base(c)

	var errs []string
	if email == "" {
		errs = append(errs, "Email can't be blank.")
	}
	if len(password) < 6 {
		errs = append(errs, "Password must be at least 6 characters.")
	}
	if password != confirm {
		errs = append(errs, "Passwords don't match.")
	}

	// Check for existing account.
	var existing models.User
	if h.DB.Where("email = ?", email).First(&existing).Error == nil {
		errs = append(errs, "Email is already registered.")
	}

	if len(errs) > 0 {
		d["Errors"] = errs
		d["Email"] = email
		h.render(c, http.StatusUnprocessableEntity, "auth/signup.html", d)
		return
	}

	user := models.User{
		Email:      email,
		TokenLimit: 100_000,
	}
	if err := user.SetPassword(password); err != nil {
		d["Errors"] = []string{"Failed to create account. Please try again."}
		h.render(c, http.StatusInternalServerError, "auth/signup.html", d)
		return
	}
	if err := h.DB.Create(&user).Error; err != nil {
		d["Errors"] = []string{"Failed to create account. Please try again."}
		h.render(c, http.StatusInternalServerError, "auth/signup.html", d)
		return
	}

	sess, _ := h.Store.Get(c.Request, middleware.SessionName)
	sess.Values["user_id"] = user.ID
	_ = sess.Save(c.Request, c.Writer)

	c.Redirect(http.StatusFound, "/")
}

// SignOut handles GET /signout — destroys the session.
func (h *H) SignOut(c *gin.Context) {
	sess, _ := h.Store.Get(c.Request, middleware.SessionName)
	// MaxAge <= 0 tells the browser to delete the cookie immediately.
	sess.Options.MaxAge = -1
	_ = sess.Save(c.Request, c.Writer)
	c.Redirect(http.StatusFound, "/signin")
}
