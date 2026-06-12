// ==============================================================================
// Template Engine
// Loads all HTML templates from the embedded filesystem at startup. Each page
// template is paired with layout.html to produce a standalone template set.
// Executing the "layout" template renders the full page HTML.
// ==============================================================================
package tmpl

import (
	"fmt"
	"html/template"
	"io"
	"io/fs"
	"strconv"
	"strings"
	"time"
)

// Templates holds one pre-parsed template set per page, keyed by path
// relative to the templates/ directory (e.g. "dashboard/index.html").
type Templates struct {
	sets map[string]*template.Template
}

// Load parses all page templates against the shared layout. templateFS must
// be an fs.FS rooted at the directory containing layout.html and subdirs.
func Load(templateFS fs.FS) (*Templates, error) {
	funcs := template.FuncMap{
		"timeAgo":   timeAgo,
		"fmtDate":   func(t time.Time) string { return t.Format("Jan 02") },
		"numFmt":    numFmt,
		"sub":       func(a, b int) int { return a - b },
		// dashOffset computes the SVG stroke-dashoffset for a ring chart.
		// circumference is 2πr; pct is 0-100. Accepts int or *int so the
		// function works whether the template passes ScoreVal() or TokenPct.
		"dashOffset": func(circ float64, pct interface{}) string {
			var p int
			switch v := pct.(type) {
			case int:
				p = v
			case *int:
				if v != nil {
					p = *v
				}
			case float64:
				p = int(v)
			}
			offset := circ * (1.0 - float64(p)/100.0)
			return strconv.FormatFloat(offset, 'f', 1, 64)
		},
	}

	pages := []string{
		"dashboard/index.html",
		"jobs/new.html",
		"jobs/show.html",
		"resumes/index.html",
		"resumes/new.html",
		"resumes/show.html",
		"folders/index.html",
		"folders/new.html",
		"auth/signin.html",
		"auth/signup.html",
	}

	t := &Templates{sets: make(map[string]*template.Template)}

	for _, page := range pages {
		// Parse layout + page together so "layout" can call {{template "content" .}}
		tmpl, err := template.New("layout.html").Funcs(funcs).ParseFS(
			templateFS,
			"templates/layout.html",
			"templates/"+page,
		)
		if err != nil {
			return nil, fmt.Errorf("parsing template %s: %w", page, err)
		}
		t.sets[page] = tmpl
	}

	return t, nil
}

// Render writes the named page template to w. Data is available as "." in
// both the layout and the content block.
func (t *Templates) Render(w io.Writer, page string, data any) error {
	tmpl, ok := t.sets[page]
	if !ok {
		return fmt.Errorf("template not found: %s", page)
	}
	return tmpl.ExecuteTemplate(w, "layout.html", data)
}

// ------------------------------------------------------------------------------
// Template helper functions
// ------------------------------------------------------------------------------

func timeAgo(t time.Time) string {
	d := time.Since(t)
	switch {
	case d < time.Minute:
		return "just now"
	case d < time.Hour:
		n := int(d.Minutes())
		if n == 1 {
			return "1 minute"
		}
		return fmt.Sprintf("%d minutes", n)
	case d < 24*time.Hour:
		n := int(d.Hours())
		if n == 1 {
			return "1 hour"
		}
		return fmt.Sprintf("%d hours", n)
	default:
		n := int(d.Hours() / 24)
		if n == 1 {
			return "1 day"
		}
		return fmt.Sprintf("%d days", n)
	}
}

// numFmt formats an integer with comma separators: 1234567 → "1,234,567".
func numFmt(n int) string {
	s := strconv.Itoa(n)
	if n < 0 {
		s = s[1:]
	}
	var b strings.Builder
	for i, c := range s {
		if i > 0 && (len(s)-i)%3 == 0 {
			b.WriteByte(',')
		}
		b.WriteRune(c)
	}
	if n < 0 {
		return "-" + b.String()
	}
	return b.String()
}
