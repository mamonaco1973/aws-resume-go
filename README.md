# AWS Resume Scorer — Go on ECS Fargate

This project delivers a fully functional **AI-powered resume scoring
application** on AWS, built with **Go (Gin + GORM)**, deployed as a
**Docker container on Amazon ECS Fargate**, and backed by **Amazon RDS
(PostgreSQL)**, **Amazon ElastiCache (Redis)**, **Amazon S3**, and
**AWS Bedrock (Claude Haiku)**.

Users paste resumes and submit job postings (by URL or pasted text).
Bedrock scores each resume against the job (0–100) with an Overview,
Strengths, and Weaknesses analysis. Scoring runs asynchronously via Asynq
(a Redis-backed task queue) so the UI stays responsive while the AI works.

It uses **Terraform** to provision all infrastructure and a single `apply.sh`
script to build and deploy the entire stack end-to-end — from VPC and database
to container image and running ECS service. No local Go installation required;
all compilation happens inside the Docker builder stage.

This is a port of the [aws-resume-ror](https://github.com/mamonaco1973/aws-resume-app-ror)
Ruby on Rails version, replacing the Rails stack with idiomatic Go while
keeping the same features, UI, and Terraform infrastructure.

## Key Capabilities Demonstrated

1. **Go Web Application with Gin** — HTTP routing via Gin, GORM v2 for
   PostgreSQL access with AutoMigrate on startup, and `html/template` with
   `//go:embed` for zero-file-copy template and static asset serving.
2. **AWS Bedrock AI Integration** — Two-call Claude Haiku pipeline: extract
   title/company/description from a URL or raw text, then score the resume
   against the extracted job description. All calls use AWS SDK v2
   `bedrockruntime.InvokeModel` from an Asynq worker goroutine.
3. **Token Usage Tracking** — Each user has a lifetime token budget (default
   100,000). Bedrock token counts accumulate after each call via an atomic
   SQL `UPDATE ... SET tokens_used = tokens_used + ?`. A usage ring on the
   dashboard shows consumption.
4. **File Uploads to S3** — Attachments are uploaded directly with the AWS
   SDK v2 S3 manager. The S3 object key is stored on the Attachment record;
   downloads use 15-minute presigned URLs. No ActiveStorage blob tables.
5. **Background Job Processing** — Asynq runs as a goroutine in the same
   process as the HTTP server, processing scoring tasks from Redis. Single
   binary, single container — no separate worker process.
6. **ECS Fargate Container Deployment** — Go runs serverlessly on Fargate with
   no EC2 instances to manage. All secrets are injected from Secrets Manager
   at task startup — credentials never touch the image. The Docker runtime
   image is ~20 MB (Alpine + static binary) vs ~800 MB for the Rails version.
7. **RDS PostgreSQL + ElastiCache Redis** — Managed PostgreSQL stores all
   application data. Redis backs the Asynq queue. GORM AutoMigrate creates
   and evolves the schema on every startup.
8. **Terraform Infrastructure as Code** — All AWS resources (VPC, RDS,
   ElastiCache, ECR, S3, Secrets Manager, ALB, ECS) provisioned in three
   Terraform phases with explicit dependency ordering.
9. **Session Auth Without an Identity Provider** — gorilla/sessions
   CookieStore with keys derived from `SECRET_KEY_BASE`. CSRF tokens are
   generated per-session and validated on every state-changing request.
   bcrypt handles password hashing.

## Architecture

```
Internet
    │
    ▼
Application Load Balancer (public subnets, port 443/80)
    │
    ▼
ECS Fargate Task (private subnets, port 3000)
  └── Go binary
        ├── Gin HTTP server
        └── Asynq worker goroutine (scoring tasks, Redis queue)
               │
               ▼
          AWS Bedrock (Claude Haiku — extract + score)
    │                   │
    ▼                   ▼
RDS PostgreSQL     ElastiCache Redis
(private subnet)   (private subnet)
    │
    ▼
S3 (attachments — direct SDK upload, presigned download URLs)
Secrets Manager (DATABASE_URL, REDIS_URL, SECRET_KEY_BASE,
                 BEDROCK_MODEL_ID, SMTP_USER, SMTP_PASSWORD)
ECR (container image)
```

## Prerequisites

* [An AWS Account](https://aws.amazon.com/console/)
* [Install AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
* [Install Terraform](https://developer.hashicorp.com/terraform/install)
* [Install Docker](https://docs.docker.com/engine/install/)
* [Install jq](https://jqlang.github.io/jq/download/)
* Bedrock model access enabled in `us-east-1` for Claude Haiku

Region is hardcoded to `us-east-1`. No local Go installation is needed —
the multi-stage Dockerfile handles `go mod tidy` and compilation inside
the builder stage.

If this is your first time using AWS with Terraform, we recommend starting
with this video:
**[AWS + Terraform: Easy Setup](https://www.youtube.com/watch?v=9clW3VQLyxA)**

### Optional: SMTP (Forgot Password)

Password-reset email requires an SMTP relay. Export these before running
`apply.sh`; if unset the app deploys normally but password-reset emails
will silently fail:

```bash
export SMTP_SERVER="smtp.improvmx.com"
export SMTP_PORT=587
export SMTP_USER="your-smtp-user"
export SMTP_PASSWORD="your-smtp-password"
```

## Download this Repository

```bash
git clone https://github.com/mamonaco1973/aws-resume-go.git
cd aws-resume-go
```

## Build the Code

Run [check_env](check_env.sh) to validate your environment, then run
[apply](apply.sh) to provision all infrastructure and deploy the application.

```bash
~/aws-resume-go$ ./apply.sh
NOTE: Running environment validation...
NOTE: Validating that required commands are found in your PATH.
NOTE: aws is found in the current PATH.
NOTE: terraform is found in the current PATH.
NOTE: docker is found in the current PATH.
NOTE: jq is found in the current PATH.
NOTE: Successfully logged into AWS.
NOTE: Building network infrastructure...
...
NOTE: Building and pushing Docker image to ECR...
...
NOTE: Deploying ECS Fargate cluster and service...
...
NOTE: Waiting for https://myjobs-go.mikes-cloud-solutions.com/signin to return HTTP 200...
NOTE: Resume Scorer is healthy (HTTP 200).
NOTE: Deployment complete.
NOTE: Resume Scorer URL:  https://myjobs-go.mikes-cloud-solutions.com
NOTE: Demo login:         demo@example.com / password123
```

`apply.sh` runs four phases in order:

1. **Phase 1 — Network Infrastructure** (`01-network/`): Provisions VPC,
   subnets, Internet Gateway, NAT Gateway, RDS PostgreSQL 16, ElastiCache
   Redis 7, ECR repository, S3 bucket for uploads, and Secrets Manager entries
   for all credentials (including SMTP if provided).
2. **Phase 2 — Docker Build** (`02-docker/resumescorer/`): Builds the Go
   container image inside a multi-stage Dockerfile (`go mod tidy` + `go build`
   in a `golang:1.22-alpine` builder, result copied to `alpine:3.19` runtime)
   and pushes it to ECR.
3. **Phase 3 — ECS Fargate** (`03-ecs/`): Deploys the ECS cluster, ALB, ACM
   certificate, Route 53 records, task definition, and ECS service. Secrets
   Manager ARNs are wired into the task definition so credentials are injected
   at task startup. ACM DNS validation can take up to 5 minutes on a fresh deploy.
4. **Phase 4 — Validation**: Polls the sign-in endpoint until the Go binary
   responds HTTP 200. Fargate tasks typically start in 2–4 minutes.

### Build Results

When deployment completes, the following resources exist in `us-east-1`:

- **Networking:**
  - VPC `10.0.0.0/23` with 2 private and 2 public subnets across 2 AZs
  - Internet Gateway, NAT Gateway, route tables for private subnet egress

- **Database Layer:**
  - RDS PostgreSQL 16 (`db.t3.micro`, 20 GB) in private subnets
  - ElastiCache Redis 7 (`cache.t3.micro`, single node) in private subnets
  - Passwords randomly generated by Terraform; stored in Secrets Manager
  - Schema created by GORM AutoMigrate on first container start

- **Storage:**
  - S3 bucket (`resumescorer-uploads-<random>`) for file attachments
  - Public access blocked; IAM role grants ECS task read/write access

- **Container Infrastructure:**
  - ECR repository `resumescorer` holding the Go application image (~20 MB)
  - ECS Fargate cluster (1 vCPU / 2 GB) with Container Insights enabled
  - CloudWatch log group `/ecs/resumescorer` (7-day retention)

- **Application Load Balancer:**
  - ALB in public subnets, HTTPS (port 443) termination with ACM certificate
  - HTTP (port 80) redirects to HTTPS
  - Health check against `/signin`

- **Security & IAM:**
  - ALB security group (ports 80/443 inbound from internet)
  - ECS task security group (port 3000 from ALB only; RDS/Redis from VPC CIDR)
  - ECS task execution role: pull from ECR, write CloudWatch, read 6 secrets
  - ECS task runtime role: S3 read/write, Bedrock `InvokeModel`, SSM ECS Exec

- **Secrets Manager:**
  - `resumescorer_database_url` — full `postgresql://` connection string
  - `resumescorer_redis_url` — `redis://` endpoint with database index
  - `resumescorer_secret_key_base` — 128-character random key for session signing
  - `resumescorer_bedrock_model_id` — Claude Haiku model ID string
  - `resumescorer_smtp_user` — SMTP username (empty if not provided)
  - `resumescorer_smtp_password` — SMTP password (empty if not provided)

## Demo User

Seed data is loaded automatically on first deploy.

| Email | Password | Notes |
|---|---|---|
| `demo@example.com` | `password123` | 2 resumes, 2 folders, 2 pre-scored jobs |

You can register additional accounts at `/signup`.

## Using the Application

### Add a Resume

1. Sign in and navigate to **Resumes** in the nav bar.
2. Click **New Resume**, give it a name, and paste the resume text directly
   into the form. The full text is stored in the database and used at
   scoring time.

### Score a Job

1. Navigate to **Score a Job**.
2. Choose a source: paste a job URL, enter LinkedIn Job IDs (one per line,
   up to 10), or paste raw job text directly.
3. Select the resume to score against and optionally assign a folder.
4. Submit — the job appears immediately with status `pending`, then
   `scoring`, then `scored` as the Asynq worker processes it in the
   background. The dashboard auto-refreshes while jobs are in flight.

### View Results

- The **Dashboard** shows all scored jobs with color-coded score badges
  (green ≥ 75, yellow ≥ 50, red below 50) and a token usage ring.
- Click a job to see the full AI analysis (Overview, Strengths, Weaknesses),
  add personal notes, upload file attachments, and read the extracted job
  description.

### Organize

- Create **Folders** to group related jobs (e.g., "Remote Python Roles").
- Filter the dashboard by folder or keyword.

## Application Structure

```
01-network/                        # Terraform: VPC, RDS, Redis, ECR, S3, Secrets
03-ecs/                            # Terraform: ECS Fargate, ALB, ACM, Route 53, IAM
02-docker/resumescorer/            # Go application
  main.go                          # Entry point: DB retry, Asynq goroutine, Gin server
  go.mod                           # Module dependencies (Go 1.22)
  Dockerfile                       # Multi-stage: golang:1.22-alpine → alpine:3.19
  startup.sh                       # Thin entrypoint — exec ./resumescorer
  internal/
    config/config.go               # Env var loading (mustEnv panics on missing)
    db/db.go                       # GORM connect + AutoMigrate
    models/                        # user, resume, folder, job, attachment
    handlers/                      # auth, dashboard, jobs, resumes, folders, attachments
    middleware/middleware.go        # RequireAuth, CSRF, MethodOverride
    worker/scoring.go              # Asynq task handler (Bedrock extract + score)
    storage/s3.go                  # S3 upload, presign, delete
    seeds/seeds.go                 # Idempotent demo data
    tmpl/tmpl.go                   # Pre-parsed template sets + helper funcs
  templates/
    layout.html                    # Nav, flash, confirm modal
    dashboard/index.html           # Job table, token ring, auto-refresh
    jobs/                          # new, show
    resumes/                       # index, new, show
    folders/                       # index, new
    auth/                          # signin, signup
  public/
    favicon.ico
apply.sh
destroy.sh
check_env.sh
validate.sh
```

## Destroy

```bash
./destroy.sh
```

Tears down all resources in reverse dependency order:

1. ECS Fargate service and ALB (`03-ecs/`)
2. ECR repository (force-deletes all images)
3. Secrets Manager entries (force-delete bypasses recovery window so
   re-deploys can reuse the same secret names)
4. Network infrastructure — VPC, RDS, ElastiCache, S3 (`01-network/`)
