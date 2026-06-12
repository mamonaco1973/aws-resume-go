// ==============================================================================
// Resume Scorer — Go application entry point
//
// Startup sequence:
//   1. Load config from environment variables
//   2. Connect to PostgreSQL and run AutoMigrate
//   3. Seed demo data (idempotent)
//   4. Build HTTP handlers
//   5. Start Asynq worker (goroutine) — processes scoring tasks from Redis
//   6. Start Gin HTTP server (foreground)
//
// Both the HTTP server and the Asynq worker run in the same process,
// mirroring the Rails startup.sh pattern of starting Sidekiq + Puma.
// ==============================================================================
package main

import (
	"context"
	"embed"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/securecookie"
	"github.com/gorilla/sessions"
	"github.com/hibiken/asynq"
	"resumescorer/internal/config"
	"resumescorer/internal/db"
	"resumescorer/internal/handlers"
	"resumescorer/internal/middleware"
	"resumescorer/internal/seeds"
	"resumescorer/internal/storage"
	"resumescorer/internal/tmpl"
	"resumescorer/internal/worker"
	"gorm.io/gorm"
)

//go:embed templates
var templateFS embed.FS

//go:embed public
var publicFS embed.FS

func main() {
	cfg := config.Load()

	// ===========================================================================
	// Database — retry until RDS accepts connections (Fargate cold start)
	// ===========================================================================
	var (
		database *gorm.DB
		dbErr    error
	)
	for attempt := 1; attempt <= 30; attempt++ {
		database, dbErr = db.Open(cfg.DatabaseURL)
		if dbErr == nil {
			break
		}
		fmt.Printf("NOTE: DB not ready (attempt %d/30), retrying in 5s: %v\n", attempt, dbErr)
		time.Sleep(5 * time.Second)
	}
	if dbErr != nil {
		log.Fatalf("database connection failed after 30 attempts: %v", dbErr)
	}
	if err := seeds.Run(database); err != nil {
		log.Fatalf("seeding failed: %v", err)
	}

	// ===========================================================================
	// Dependencies
	// ===========================================================================
	s3client, err := storage.New(cfg.AWSRegion, cfg.S3Bucket)
	if err != nil {
		log.Fatalf("S3 client failed: %v", err)
	}

	// Session store uses a 64-byte hash key and 32-byte AES encryption key
	// derived from SECRET_KEY_BASE so sessions are encrypted and signed.
	key := []byte(cfg.SecretKeyBase)
	hashKey := securecookie.GenerateRandomKey(64)
	if len(key) >= 64 {
		hashKey = key[:64]
	}
	encKey := securecookie.GenerateRandomKey(32)
	if len(key) >= 96 {
		encKey = key[64:96]
	}
	store := sessions.NewCookieStore(hashKey, encKey)
	store.Options = &sessions.Options{
		Path:     "/",
		MaxAge:   86400 * 30, // 30 days
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
	}

	asynqOpt, err := asynq.ParseRedisURI(cfg.RedisURL)
	if err != nil {
		log.Fatalf("invalid REDIS_URL: %v", err)
	}
	queue := asynq.NewClient(asynqOpt)
	defer queue.Close()

	templates, err := tmpl.Load(templateFS)
	if err != nil {
		log.Fatalf("template loading failed: %v", err)
	}

	h := &handlers.H{
		DB:      database,
		Store:   store,
		S3:      s3client,
		Queue:   queue,
		Tmpl:    templates,
		AppHost: cfg.AppHostname,
	}

	// ===========================================================================
	// Asynq worker goroutine — handles scoring tasks from Redis
	// ===========================================================================
	scoringWorker := worker.New(database, cfg.AWSRegion, cfg.BedrockModelID)
	asynqSrv := asynq.NewServer(asynqOpt, asynq.Config{Concurrency: 5})
	mux := asynq.NewServeMux()
	mux.HandleFunc(worker.TaskTypeScoring, scoringWorker.ProcessTask)

	go func() {
		if err := asynqSrv.Run(mux); err != nil {
			log.Printf("asynq server error: %v", err)
		}
	}()

	// ===========================================================================
	// Gin HTTP server
	// ===========================================================================
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Logger(), gin.Recovery())

	// Static files from embedded FS (favicon, etc.)
	r.StaticFS("/public", http.FS(publicFS))
	r.GET("/favicon.ico", func(c *gin.Context) {
		c.FileFromFS("public/favicon.ico", http.FS(publicFS))
	})

	// Global middleware order matters:
	//   1. MethodOverride — must run before routing to rewrite POST→PATCH/DELETE
	//   2. CSRF — generates token for all requests, validates on state-changing
	r.Use(middleware.MethodOverride())
	r.Use(middleware.CSRF(store))

	// ===========================================================================
	// Public routes (no auth required)
	// ===========================================================================
	r.GET("/signin", h.ShowSignIn)
	r.POST("/signin", h.SignIn)
	r.GET("/signup", h.ShowSignUp)
	r.POST("/signup", h.SignUp)
	r.GET("/signout", h.SignOut)

	// ===========================================================================
	// Authenticated routes
	// ===========================================================================
	auth := r.Group("/")
	auth.Use(middleware.RequireAuth(store, database))
	{
		auth.GET("/", h.DashboardIndex)
		auth.GET("/dashboard", h.DashboardIndex)

		// Resumes
		auth.GET("/resumes", h.ResumeIndex)
		auth.GET("/resumes/new", h.ResumeNew)
		auth.POST("/resumes", h.ResumeCreate)
		auth.GET("/resumes/:id", h.ResumeShow)
		auth.DELETE("/resumes/:id", h.ResumeDestroy)

		// Folders
		auth.GET("/folders", h.FolderIndex)
		auth.GET("/folders/new", h.FolderNew)
		auth.POST("/folders", h.FolderCreate)
		auth.DELETE("/folders/:id", h.FolderDestroy)

		// Jobs
		auth.GET("/jobs/new", h.JobNew)
		auth.POST("/jobs", h.JobCreate)
		auth.GET("/jobs/:id", h.JobShow)
		auth.PATCH("/jobs/:id", h.JobUpdate)
		auth.DELETE("/jobs/:id", h.JobDestroy)

		// Attachments (nested under jobs)
		auth.POST("/jobs/:job_id/attachments", h.AttachmentCreate)
		auth.GET("/jobs/:job_id/attachments/:id/download", h.AttachmentDownload)
		auth.DELETE("/jobs/:job_id/attachments/:id", h.AttachmentDestroy)
	}

	// ===========================================================================
	// Graceful shutdown
	// ===========================================================================
	srv := &http.Server{
		Addr:    ":" + cfg.Port,
		Handler: r,
	}

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		fmt.Printf("NOTE: Resume Scorer listening on :%s\n", cfg.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("HTTP server error: %v", err)
		}
	}()

	<-quit
	fmt.Println("NOTE: Shutting down...")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	asynqSrv.Shutdown()
	srv.Shutdown(ctx)
}
