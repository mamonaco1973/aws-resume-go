# CLAUDE.md

This file provides guidance to Claude Code when working with code in this
repository.

## What This App Does

AWS Resume Scorer — Go application running on ECS Fargate.
Users paste resumes and submit job postings (URL or pasted text); AWS Bedrock
(Claude Haiku) scores each resume against the job (0-100) with Overview,
Strengths, and Weaknesses analysis. Scoring runs asynchronously via Asynq
(Redis-backed worker goroutine). bcrypt handles password hashing and
gorilla/sessions manages auth cookies. Jobs can be organized into folders.
File attachments per job are uploaded directly to S3. Token usage is tracked
per user with a configurable lifetime cap (default 100,000). All infrastructure
is Terraform-managed; credentials are injected at ECS task startup from Secrets
Manager — never baked into the image.

This is a port of aws-resume-ror (Ruby on Rails) to Go using:
- Gin HTTP router
- GORM v2 + PostgreSQL
- Asynq (replaces Sidekiq/Redis queue)
- AWS SDK v2 (S3, Bedrock)
- html/template (replaces ERB)
- gorilla/sessions (replaces Devise sessions)
- bcrypt (replaces Devise password hashing)

## Deployment Commands

All deployment runs from the repo root:

```bash
./apply.sh      # Full deploy: 01-network → docker build+push → 03-ecs → validate
./destroy.sh    # Reverse teardown: 03-ecs → ECR → Secrets → 01-network
./check_env.sh  # Validate required tools: aws, terraform, docker, jq
./validate.sh   # Poll ALB until HTTP 200 on /signin
```

Requires Bedrock model access enabled in us-east-1 for
`us.anthropic.claude-haiku-4-5-20251001-v1:0`.

There are no test or lint commands configured.

## Architecture

```
01-network/          # Terraform: VPC, RDS PostgreSQL 16, ElastiCache Redis 7,
                     #   ECR, S3 (uploads), Secrets Manager (4 secrets)
03-ecs/              # Terraform: ECS Fargate cluster, ALB, task def, IAM roles
02-docker/resumescorer/  # Go application + Dockerfile + startup.sh
```

### Application Layout

```
main.go                   - Entry point: DB retry, Asynq worker goroutine, Gin server
go.mod                    - Module dependencies

internal/
  config/config.go        - Environment variable loading (mustEnv panics on startup)
  db/db.go                - GORM connection + AutoMigrate
  models/
    user.go               - bcrypt auth, token tracking, AccumulateTokens (atomic SQL)
    resume.go             - Plain-text resume storage
    folder.go             - Job organization (cosmetic, no scoring effect)
    job.go                - Status lifecycle, ScoreColor, ScoreVal, FolderIDVal
    attachment.go         - S3 key storage (replaces ActiveStorage blobs)
  handlers/
    helpers.go            - H struct (dependencies), base() TD, flash helpers
    auth.go               - Sign in/up/out (gorilla/sessions)
    dashboard.go          - Job list with search/folder filters + token ring
    jobs.go               - Job CRUD + LinkedIn batch + Asynq enqueue
    resumes.go            - Resume CRUD (plain text paste)
    folders.go            - Folder CRUD
    attachments.go        - S3 upload/presigned-download/delete
  middleware/
    middleware.go         - RequireAuth, CSRF, MethodOverride
  worker/
    scoring.go            - Asynq task handler (port of ScoringJob):
                          #   Phase 1: extract title/company/job_text via Bedrock
                          #   Phase 2: score resume vs job_text (0-100 + analysis)
  storage/
    s3.go                 - S3 Upload, PresignDownload, Delete
  seeds/
    seeds.go              - Idempotent demo data (demo@example.com / password123)
  tmpl/
    tmpl.go               - Pre-parsed template sets (layout + page), helper funcs

templates/
  layout.html             - Nav, flash, confirm modal, {{template "content" .}}
  dashboard/index.html    - Job table, token ring, auto-filter JS, auto-refresh
  jobs/new.html           - URL/LinkedIn/raw_text source selector + localStorage
  jobs/show.html          - Score ring, AI analysis, folder move, notes, attachments
  resumes/                - index, new, show
  folders/                - index, new
  auth/                   - signin, signup
```

### Scoring Flow (worker/scoring.go)

1. Asynq dequeues task with job_id from Redis
2. Load Job + Resume + User, check token limit
3. Set status = "scoring"
4. Phase 1: fetch URL or use raw_text → Bedrock extraction prompt → title/company/job_text
5. Update title/company (visible in UI during scoring)
6. Phase 2: Bedrock scoring prompt → score (0-100) + analysis
7. Update job: score, analysis, status = "scored"
8. Accumulate tokens on user via atomic SQL UPDATE

### Session and CSRF

- gorilla/sessions CookieStore, keys derived from SECRET_KEY_BASE
- CSRF token generated per-session, stored in cookie, validated on POST/PATCH/DELETE
- All forms include `<input type="hidden" name="_csrf" value="{{.CSRF}}">`
- DELETE/PATCH forms include `<input type="hidden" name="_method" value="DELETE">`
  and MethodOverride middleware rewrites the request method

### Attachment Flow

1. POST /jobs/:job_id/attachments → validate type + size
2. Upload to S3 key: `attachments/{user_id}/{job_id}/{rand}_{filename}`
3. Store S3 key on Attachment record
4. GET /jobs/:job_id/attachments/:id/download → presign S3 GET URL → redirect

### Secrets Injection

Same four Secrets Manager secrets as the ROR version (01-network/secrets.tf):
- `resumescorer_database_url`      — postgresql:// connection string
- `resumescorer_redis_url`         — redis://<endpoint>:6379/0
- `resumescorer_secret_key_base`   — 128-char random key
- `resumescorer_bedrock_model_id`  — Claude Haiku model ID string

## Code Commenting Standards

Follow the workspace-level standards in `c:\cloudenv\.claude\CLAUDE.md`.
Key rules for this project:

- Comment lines ≤ 80 characters
- Shell scripts: `set -e` at top, section banners for major blocks
- Terraform: section headers for logical resource groups; explain *why*
  infrastructure exists, not what the resource type says
- Go: Google-style doc comments on exported functions; inline comments
  explain intent only; no comments that restate the code
