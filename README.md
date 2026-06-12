# AWS Resume Scorer — Ruby on Rails on ECS Fargate

This project delivers a fully functional **AI-powered resume scoring
application** on AWS, built with **Ruby on Rails 7.1**, deployed as a
**Docker container on Amazon ECS Fargate**, and backed by **Amazon RDS
(PostgreSQL)**, **Amazon ElastiCache (Redis)**, **Amazon S3**, and
**AWS Bedrock (Claude Haiku)**.

Users upload resumes and submit job postings (by URL or pasted text).
Bedrock scores each resume against the job (0–100) with an Overview,
Strengths, and Weaknesses analysis. Scoring runs asynchronously via Sidekiq
so the UI stays responsive while the AI works.

It uses **Terraform** to provision all infrastructure and a single `apply.sh`
script to build and deploy the entire stack end-to-end — from VPC and database
to container image and running ECS service.

Authentication is handled by **Devise** (bcrypt sessions) and authorization by
**Pundit** policy objects — no external identity provider required.

## Key Capabilities Demonstrated

1. **Ruby on Rails MVC Application** — Full Rails 7.1 stack with ActiveRecord,
   Devise authentication, Pundit authorization, ActiveStorage file uploads,
   and Sidekiq background jobs.
2. **AWS Bedrock AI Integration** — Two-call Claude Haiku pipeline: extract
   title/company/description from a URL or raw text, then score the resume
   against the extracted job description. All calls are made from a Sidekiq
   worker using the `aws-sdk-bedrockruntime` gem.
3. **Token Usage Tracking** — Each user has a lifetime token budget (default
   100,000). Bedrock token counts accumulate after each call using a
   thread-safe SQL increment. A usage ring on the dashboard shows consumption.
4. **File Uploads to S3** — Resumes and job attachments are stored via
   ActiveStorage. The ECS task IAM role grants S3 access — no long-lived
   credentials in the application.
5. **Background Job Processing** — Sidekiq runs in the same container as Puma,
   processing `ScoringJob` from a Redis queue. A natural talking point for
   production separation of web and worker tiers.
6. **ECS Fargate Container Deployment** — Rails runs serverlessly on Fargate
   with no EC2 instances to manage. All secrets are injected from Secrets
   Manager at task startup — credentials never touch the image.
7. **RDS PostgreSQL + ElastiCache Redis** — Managed PostgreSQL stores all
   application data. Redis backs the Sidekiq queue.
8. **Terraform Infrastructure as Code** — All AWS resources (VPC, RDS,
   ElastiCache, ECR, S3, Secrets Manager, ALB, ECS) provisioned in three
   Terraform phases with explicit dependency ordering.
9. **Database Migrations on Deploy** — `rails db:prepare` runs in the
   container entrypoint on startup, applying all ActiveRecord migrations
   before Puma accepts traffic.

## Architecture

```
Internet
    │
    ▼
Application Load Balancer (public subnets, port 80)
    │
    ▼
ECS Fargate Task (private subnets, port 3000)
  ├── Puma (Rails web server)
  └── Sidekiq (ScoringJob worker, Redis queue)
         │
         ▼
    AWS Bedrock (Claude Haiku — extract + score)
    │                   │
    ▼                   ▼
RDS PostgreSQL     ElastiCache Redis
(private subnet)   (private subnet)
    │
    ▼
S3 (ActiveStorage — resumes + attachments)
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

Region is hardcoded to `us-east-1`.

If this is your first time using AWS with Terraform, we recommend starting
with this video:
**[AWS + Terraform: Easy Setup](https://www.youtube.com/watch?v=9clW3VQLyxA)**

### Optional: SMTP (Forgot Password)

Devise's password-reset email requires an SMTP relay. Export these before
running `apply.sh`; if unset the app deploys normally but password-reset
emails will silently fail:

```bash
export SMTP_SERVER="smtp.improvmx.com"
export SMTP_PORT=587
export SMTP_USER="your-smtp-user"
export SMTP_PASSWORD="your-smtp-password"
```

## Download this Repository

```bash
git clone https://github.com/mamonaco1973/aws-resume-app-ror.git
cd aws-resume-app-ror
```

## Build the Code

Run [check_env](check_env.sh) to validate your environment, then run
[apply](apply.sh) to provision all infrastructure and deploy the application.

```bash
~/aws-resume-app-ror$ ./apply.sh
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
NOTE: Waiting for http://<alb-dns>/users/sign_in to return HTTP 200...
NOTE: Resume Scorer is healthy (HTTP 200).
NOTE: Deployment complete.
NOTE: Resume Scorer URL:  http://<alb-dns>
NOTE: Demo login:         demo@example.com / password123
```

`apply.sh` runs four phases in order:

1. **Phase 1 — Network Infrastructure** (`01-network/`): Provisions VPC,
   subnets, Internet Gateway, NAT Gateway, RDS PostgreSQL 16, ElastiCache
   Redis 7, ECR repository, S3 bucket for uploads, and Secrets Manager entries
   for all credentials (including SMTP if provided).
2. **Phase 2 — Docker Build** (`02-docker/resumescorer/`): Builds the Rails
   container image and pushes it to ECR.
3. **Phase 3 — ECS Fargate** (`03-ecs/`): Deploys the ECS cluster, ALB,
   target group, task definition, and ECS service. Secrets Manager ARNs are
   wired into the task definition so credentials are injected at task startup.
   A second Terraform pass re-applies with `APP_HOST` set to the ALB DNS name
   so Devise password-reset links resolve correctly.
4. **Phase 4 — Validation**: Polls the ALB health endpoint until Rails
   responds HTTP 200. Fargate tasks need ~5–10 minutes to start, run
   migrations, and join the target group.

### Build Results

When deployment completes, the following resources exist in `us-east-1`:

- **Networking:**
  - VPC `10.0.0.0/23` with 2 private and 2 public subnets across 2 AZs
  - Internet Gateway, NAT Gateway, route tables for private subnet egress

- **Database Layer:**
  - RDS PostgreSQL 16 (`db.t3.micro`, 20 GB) in private subnets
  - ElastiCache Redis 7 (`cache.t3.micro`, single node) in private subnets
  - Passwords randomly generated by Terraform; stored in Secrets Manager
  - Full Rails schema created by `rails db:prepare` on first container start

- **Storage:**
  - S3 bucket (`resumescorer-uploads-<random>`) for ActiveStorage files
  - Public access blocked; IAM role grants ECS task read/write access

- **Container Infrastructure:**
  - ECR repository `resumescorer` holding the Rails application image
  - ECS Fargate cluster (1 vCPU / 2 GB) with Container Insights enabled
  - CloudWatch log group `/ecs/resumescorer` (7-day retention)

- **Application Load Balancer:**
  - ALB in public subnets, port 80 forwarding to ECS tasks on port 3000
  - Health check against `/users/sign_in`

- **Security & IAM:**
  - ALB security group (port 80 inbound from internet)
  - ECS task security group (port 3000 from ALB only; RDS/Redis from VPC CIDR)
  - ECS task execution role: pull from ECR, write CloudWatch, read 6 secrets
  - ECS task runtime role: S3 read/write, Bedrock `InvokeModel`, SSM ECS Exec

- **Secrets Manager:**
  - `resumescorer_database_url` — full `postgresql://` connection string
  - `resumescorer_redis_url` — `redis://` endpoint with database index
  - `resumescorer_secret_key_base` — 128-character random key for Rails sessions
  - `resumescorer_bedrock_model_id` — Claude Haiku model ID string
  - `resumescorer_smtp_user` — SMTP username (empty if not provided)
  - `resumescorer_smtp_password` — SMTP password (empty if not provided)

## Demo User

Seed data is loaded automatically on first deploy.

| Email | Password | Notes |
|---|---|---|
| `demo@example.com` | `password123` | 2 resumes, 2 folders, 2 pre-scored jobs |

You can register additional accounts at `/users/sign_up`.

## Using the Application

### Upload a Resume

1. Sign in and navigate to **Resumes** in the nav bar.
2. Click **New Resume**, give it a name, and attach a PDF file.
3. The app extracts text from the PDF at upload time using `pdf-reader` and
   stores it in the database — no re-reads at scoring time.

### Score a Job

1. Navigate to **Score a Job**.
2. Choose a source: paste a job URL or paste raw job text directly.
3. Select the resume to score against and optionally assign a folder.
4. Submit — the job appears immediately with status `pending`, then `scoring`,
   then `scored` as Sidekiq processes it in the background.

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
01-network/                  # Terraform: VPC, RDS, Redis, ECR, S3, Secrets
03-ecs/                      # Terraform: ECS Fargate, ALB, IAM roles
02-docker/resumescorer/          # Rails 7.1 application
  app/
    models/                  # User, Resume, Folder, Job, Attachment
    policies/                # Pundit: one policy per model (user-scoped)
    controllers/
      dashboard_controller.rb
      jobs_controller.rb
      resumes_controller.rb
      folders_controller.rb
      attachments_controller.rb
    views/                   # ERB templates with Tailwind CSS (CDN)
    jobs/                    # ScoringJob (Sidekiq + Bedrock)
  db/
    migrate/                 # 6 migrations (timestamps frozen at 20240101*)
    seeds.rb                 # 1 demo user, 2 resumes, 2 folders, 2 jobs
  config/
    routes.rb
    storage.yml              # ActiveStorage → S3 via IAM role
  Dockerfile
  startup.sh                 # Waits for DB, db:prepare, Sidekiq + Puma
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
