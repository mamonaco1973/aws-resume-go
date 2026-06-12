# CLAUDE.md

This file provides guidance to Claude Code when working with code in this
repository.

## What This App Does

AWS Resume Scorer — Ruby on Rails 7.1 application running on ECS Fargate.
Users upload resumes and submit job postings (URL or pasted text); AWS Bedrock
(Claude Haiku) scores each resume against the job (0-100) with Overview,
Strengths, and Weaknesses analysis. Scoring runs asynchronously via Sidekiq.
Devise handles authentication (bcrypt sessions). Pundit enforces per-resource
authorization. Jobs can be organized into folders. File attachments per job
are stored via ActiveStorage to S3. Token usage is tracked per user with a
configurable lifetime cap (default 100,000). All infrastructure is
Terraform-managed; credentials are injected at ECS task startup from Secrets
Manager — never baked into the image.

## Deployment Commands

All deployment runs from the repo root:

```bash
./apply.sh      # Full deploy: 01-network → docker build → 03-ecs → validate
./destroy.sh    # Reverse teardown: 03-ecs → ECR → Secrets → 01-network
./check_env.sh  # Validate required tools: aws, terraform, docker, jq
./validate.sh   # Poll ALB until HTTP 200; Fargate needs ~5-10 min to start
```

Requires Bedrock model access enabled in us-east-1 for
`us.anthropic.claude-haiku-4-5-20251001-v1:0`.

There are no test or lint commands configured.

## Architecture

```
01-network/          # Terraform: VPC, RDS PostgreSQL 16, ElastiCache Redis 7,
                     #   ECR, S3 (uploads), Secrets Manager (4 secrets)
03-ecs/              # Terraform: ECS Fargate cluster, ALB, task def, IAM roles
02-docker/resumescorer/  # Rails 7.1 app + Dockerfile + startup.sh
```

### Deployment Flow

`apply.sh` runs in order:

1. `01-network/` — provisions all persistent infrastructure; exports
   `S3_BUCKET` and `ECR_URL` from Terraform outputs
2. Docker build + ECR push — single-stage `ruby:3.3-slim` image
3. `03-ecs/` — deploys Fargate service; `s3_bucket_name` passed as a
   Terraform variable (not a data source — bucket name has random suffix)
4. `validate.sh` — polls `/users/sign_in` for HTTP 200

### Container Startup (`startup.sh`)

On each task start:
- Waits for RDS to accept connections (30 retries × 5s)
- Runs `rake db:migrate` (idempotent; skips already-applied migrations)
- Runs `rake db:seed` (idempotent via `find_or_create_by!`)
- Starts Sidekiq in background (picks up `:default` queue for ScoringJob)
- Exec's Puma in foreground

### Rails Application Layout

```
app/models/
  user.rb             # Devise, token_limit/tokens_used tracking
  resume.rb           # belongs_to user, has_one_attached :file,
                      #   extract_and_store_text (pdf-reader)
  folder.rb           # belongs_to user, has_many jobs
  job.rb              # belongs_to user+resume+folder(opt), status enum,
                      #   score_color, processing?/scored?/errored?
  attachment.rb       # belongs_to job+user, has_one_attached :file,
                      #   10 MB cap, type whitelist

app/policies/         # Pundit — one policy per model (user-scoped)
  job_policy.rb
  resume_policy.rb
  folder_policy.rb
  attachment_policy.rb

app/controllers/
  dashboard_controller.rb   # root path; job list + token ring
  jobs_controller.rb        # CRUD + patch for notes save
  resumes_controller.rb     # upload, list, delete
  folders_controller.rb     # CRUD
  attachments_controller.rb # create + destroy (nested under jobs)

app/jobs/
  scoring_job.rb    # Sidekiq; two Bedrock calls: extract then score
                    # Accumulates tokens on user record after each call

db/migrate/         # 6 migrations; timestamps frozen at 20240101*
db/seeds.rb         # 1 demo user, 2 resumes, 2 folders, 2 seeded jobs
                    # password: "password123", email: demo@example.com
```

### Scoring Flow (`ScoringJob`)

1. Load job + resume, check token limit
2. Set status = "scoring"
3. If `source_type == "url"`: fetch URL with `Net::HTTP`, strip HTML with
   Nokogiri, call Bedrock to extract title/company/job_description_text
4. If `source_type == "raw_text"`: call Bedrock on the pasted text
5. Update job with title/company (shows in UI during scoring)
6. Call Bedrock to score resume text vs job_description_text (0-100, summary)
7. Update job with score/analysis, set status = "scored"

### Secrets Injection

Four Secrets Manager secrets created in `01-network/secrets.tf`:
- `resumescorer_database_url`  — full `postgresql://` connection string
- `resumescorer_redis_url`     — `redis://<endpoint>:6379/0`
- `resumescorer_secret_key_base` — 128-char random key
- `resumescorer_bedrock_model_id` — Claude Haiku model ID string

All four are injected into the ECS task via the `secrets:` block in
`03-ecs/ecs.tf`. Rails / ScoringJob reads them as environment variables.

### Cross-Phase Data Flow

| Value | Source | Consumer |
|---|---|---|
| `ECR_URL` | `01-network` terraform output | Docker build tag + push |
| `S3_BUCKET` | `01-network` terraform output | `03-ecs` `-var` argument |
| VPC/subnet IDs | tag-based data sources | `03-ecs/data.tf` |
| Secret ARNs | name-based data sources | `03-ecs/data.tf` → task def |

### Key Terraform Files

- `01-network/rds.tf` — RDS PostgreSQL 16, `db.t3.micro`, private subnets
- `01-network/elasticache.tf` — Redis 7, `cache.t3.micro`, single node
- `01-network/secrets.tf` — 4 plain-string secrets
- `03-ecs/roles.tf` — execution role (ECR + CW + 4 secrets); runtime role
  (S3 + Bedrock `InvokeModel` + SSM ECS Exec)
- `03-ecs/ecs.tf` — task def: 1 vCPU / 2 GB; `secrets:` block; exec enabled

### ECS Task Size

1 vCPU / 2 GB — bumped from 0.5/1 GB used in the jobs board because
ScoringJob + Sidekiq + Puma all run in the same container and Bedrock
response payloads can be several KB. Adjust in `03-ecs/ecs.tf` if needed.

## Code Commenting Standards

Follow the workspace-level standards in `c:\cloudenv\.claude\CLAUDE.md`.
Key rules for this project:

- Comment lines ≤ 80 characters
- Shell scripts: `set -euo pipefail` at top, section banners for major blocks
- Terraform: section headers for logical resource groups; explain *why*
  infrastructure exists, not what the resource type says
- Ruby: Google-style docstrings on non-trivial methods; inline comments
  explain intent only
- No comments that restate the code
