# Resume Scorer on AWS: Go on ECS Fargate with RDS, Redis and Bedrock

An AI **resume scoring** web app written in **Go** (Gin, GORM,
`html/template`) and run as one container on **ECS Fargate** behind an
**Application Load Balancer**. Users paste resumes and submit job postings
by URL, LinkedIn job ID or pasted text; a background worker in the same
process has **Claude Haiku on Amazon Bedrock** extract the job and score the
resume from 0 to 100 with an overview, strengths and weaknesses. Data lives
in **RDS PostgreSQL**, the job queue in **ElastiCache Redis** (Asynq), and
attachments in **S3**.

This is a Go port of [aws-resume-ror](https://github.com/mamonaco1973/aws-resume-ror),
with the same features, UI and infrastructure.

| Piece | Where | Role |
|---|---|---|
| **VPC** | `10.0.0.0/23`, us-east-1 | two public and two private `/26` subnets across two AZs; a NAT gateway for the private subnets |
| **Application Load Balancer** | public subnets | HTTPS on 443 with an ACM certificate (TLS 1.3 policy); 80 redirects to 443; forwards to the task on 3000 |
| **Route 53** + **ACM** | your hosted zone | DNS validation for the certificate and an alias record for the app's hostname |
| **ECS Fargate service** | private subnets | one task, 1 vCPU and 2 GB, running the Gin server and an Asynq worker (concurrency 5) in one binary; ECS Exec enabled; logs to `/ecs/resumescorer` for 7 days |
| **RDS PostgreSQL 16** | private subnets | `db.t3.micro`, 20 GB, not public; GORM creates the schema on startup |
| **ElastiCache Redis 7** | private subnets | `cache.t3.micro`, one node; the Asynq queue |
| **resumescorer-uploads-&lt;random&gt;** | S3 | private; attachments, downloaded through 15-minute presigned URLs |
| **resumescorer** | ECR | the app image, tagged with the build time |
| **Secrets Manager** | us-east-1 | `resumescorer_database_url`, `_redis_url`, `_secret_key_base`, `_bedrock_model_id`, `_smtp_user`, `_smtp_password`, injected into the task at start |

## Architecture

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="architecture-dark.svg">
  <img alt="A browser resolves the app's hostname through a Route 53 alias record and connects over HTTPS to an Application Load Balancer in the public subnets, which uses a DNS-validated ACM certificate and redirects port 80. The load balancer forwards to one ECS Fargate task on port 3000 in the private subnets, running a Go binary with the Gin web server and an Asynq worker. The task pulls its image from ECR, gets six settings from Secrets Manager at start, stores data in RDS PostgreSQL, queues scoring work in ElastiCache Redis, keeps attachments in S3, and calls Claude Haiku on Amazon Bedrock through the NAT gateway." src="architecture-light.svg">
</picture>

Regenerate with `python3 make_diagram.py`.

- **`01-network/`**: the VPC and NAT gateway, RDS, ElastiCache, ECR, the
  uploads bucket and the secrets (database and Redis passwords are random).
- **`02-docker/resumescorer/`**: the Go app (`main.go`, `internal/`,
  `templates/`) and a multi-stage `Dockerfile` that compiles it, so no local
  Go install is needed.
- **`03-ecs/`**: the certificate and DNS records, the load balancer, the
  cluster, task definition and service, the security groups and the two
  roles.

The load balancer's security group allows 80 and 443 from anywhere; the
task's allows 3000 only from the load balancer; PostgreSQL and Redis allow
5432 and 6379 from the VPC. The task's execution role pulls the image and
reads the six secrets; its runtime role can use the uploads bucket, call
`bedrock:InvokeModel` and use ECS Exec.

## How a job is scored

1. Users sign up and sign in with an email and password (bcrypt); sessions
   are signed cookies keyed from `SECRET_KEY_BASE`, valid for 30 days, and
   every form carries a CSRF token.
2. Submitting a job saves it as `pending` and enqueues an Asynq task in
   Redis. LinkedIn job IDs (up to 10) become one job each.
3. The worker fetches the posting or uses the pasted text, calls Bedrock
   once to extract the title, company and description, then again to score
   the resume, and saves the result as `scored`.
4. Each call's tokens are added to the user's `tokens_used` with an atomic
   SQL update. The default budget is 100,000 tokens per user, shown as a
   ring on the dashboard.

## Prerequisites

* [An AWS Account](https://aws.amazon.com/console/) with Bedrock access to
  Claude Haiku in `us-east-1`
* A **Route 53 public hosted zone** for the domain the app will use
* [Install AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
* [Install Terraform](https://developer.hashicorp.com/terraform/install)
* [Install Docker](https://docs.docker.com/engine/install/)
* [Install jq](https://jqlang.github.io/jq/download/)

The hostname is hardcoded for the author's domain: `APP_HOSTNAME` in
`apply.sh` (`myjobs-go.mikes-cloud-solutions.com`) and `hosted_zone_name` in
`03-ecs/variables.tf` (`mikes-cloud-solutions.com`). Change both, and the URL
in `validate.sh`, to a zone you own.

To set SMTP credentials, export `SMTP_SERVER`, `SMTP_PORT`, `SMTP_USER` and
`SMTP_PASSWORD` before deploying; otherwise the SMTP secrets are empty.

If this is your first time following along, we recommend starting with this
video: [AWS + Terraform: Easy Setup](https://www.youtube.com/watch?v=9clW3VQLyxA).

## Deploy

```bash
git clone https://github.com/mamonaco1973/aws-resume-go.git
cd aws-resume-go
./apply.sh
```

`apply.sh` applies `01-network`, builds the image tagged with a timestamp
and pushes it to ECR, then applies `03-ecs` with that image and the
hostname. It ends by running `validate.sh`, which polls the sign-in page
until it returns HTTP 200:

```
NOTE: Waiting for https://myjobs-ror.mikes-cloud-solutions.com/signin to return HTTP 200...
NOTE: Resume Scorer is healthy (HTTP 200).
NOTE: Demo login: demo@example.com / password123
```

## Try it

1. Open `https://<your hostname>` and sign in as `demo@example.com` /
   `password123`. The seed data gives this user 2 resumes, 2 folders and 2
   scored jobs. Or register at `/signup`.
2. Under **Resumes**, add a resume and paste its text.
3. Under **Score a Job**, give a job URL, LinkedIn job IDs (one per line) or
   the pasted description, pick a resume and optionally a folder, and
   submit. The dashboard refreshes while the job goes from `pending` to
   `scoring` to `scored`.
4. Open a scored job for the analysis and the extracted description, add
   notes, and upload attachments. Score badges are green at 75 and above,
   yellow at 50 and above, and red below 50; folders and a keyword search
   filter the dashboard.

## Teardown

```bash
./destroy.sh
```

## Notes

- **Lab only.** Anyone can register, and the seeded demo user has a known
  password.
- The load balancer's health check requests `/users/sign_in` (the Rails
  path) and expects `200`, but the Go app serves sign-in at `/signin`, so
  the check gets a 404. If the target group marks the task unhealthy,
  `/users/sign_in` is the place to look.
- `apply.sh` deploys `myjobs-go.…`, but `validate.sh` and the
  `app_hostname` default in `03-ecs/variables.tf` use `myjobs-ror.…`, so
  `validate.sh` checks the Rails app's hostname.
- The app reads the SMTP settings, but this version has no password-reset
  route that uses them.
