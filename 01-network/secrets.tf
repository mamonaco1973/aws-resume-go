# ==============================================================================
# Secrets Manager — Application Credentials
# ==============================================================================
# Stores DATABASE_URL, REDIS_URL, SECRET_KEY_BASE, and BEDROCK_MODEL_ID as
# plain-string secrets. ECS task definitions inject these at runtime via the
# secrets: [] block, keeping credentials out of image layers and env logs.
# ==============================================================================

# ------------------------------------------------------------------------------
# DB password — alphanumeric only; special chars break connection string URLs
# ------------------------------------------------------------------------------
resource "random_password" "db_password" {
  length  = 24
  special = false
}

# Full connection string — constructed after RDS endpoint is known
resource "aws_secretsmanager_secret" "db_url" {
  name        = "resumescorer_database_url"
  description = "Rails DATABASE_URL for resumescorer RDS instance"

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_secretsmanager_secret_version" "db_url" {
  secret_id = aws_secretsmanager_secret.db_url.id
  secret_string = "postgresql://${var.db_username}:${random_password.db_password.result}@${aws_db_instance.resumescorer.endpoint}/${var.db_name}"
}

# ------------------------------------------------------------------------------
# Redis URL — constructed from ElastiCache primary endpoint
# ------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "redis_url" {
  name        = "resumescorer_redis_url"
  description = "REDIS_URL for Sidekiq and Action Cable"

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_secretsmanager_secret_version" "redis_url" {
  secret_id     = aws_secretsmanager_secret.redis_url.id
  secret_string = "redis://${aws_elasticache_cluster.resumescorer.cache_nodes[0].address}:6379/0"
}

# ------------------------------------------------------------------------------
# SECRET_KEY_BASE — Rails uses this to sign session cookies and tokens
# ------------------------------------------------------------------------------
resource "random_password" "secret_key_base" {
  length  = 128
  special = false
}

resource "aws_secretsmanager_secret" "secret_key_base" {
  name        = "resumescorer_secret_key_base"
  description = "Rails SECRET_KEY_BASE for session signing"

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_secretsmanager_secret_version" "secret_key_base" {
  secret_id     = aws_secretsmanager_secret.secret_key_base.id
  secret_string = random_password.secret_key_base.result
}

# ------------------------------------------------------------------------------
# Bedrock model ID — injected as env var, not truly secret, but stored here
# so it can be changed without rebuilding the Docker image
# ------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "bedrock_model_id" {
  name        = "resumescorer_bedrock_model_id"
  description = "AWS Bedrock model ID used for resume scoring"

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_secretsmanager_secret_version" "bedrock_model_id" {
  secret_id     = aws_secretsmanager_secret.bedrock_model_id.id
  secret_string = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}

# ------------------------------------------------------------------------------
# SMTP credentials — used by Devise to send password reset emails
# ------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "smtp_user" {
  name        = "resumescorer_smtp_user"
  description = "SMTP username for Devise password reset emails"

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_secretsmanager_secret_version" "smtp_user" {
  secret_id     = aws_secretsmanager_secret.smtp_user.id
  secret_string = var.smtp_user
}

resource "aws_secretsmanager_secret" "smtp_password" {
  name        = "resumescorer_smtp_password"
  description = "SMTP password for Devise password reset emails"

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_secretsmanager_secret_version" "smtp_password" {
  secret_id     = aws_secretsmanager_secret.smtp_password.id
  secret_string = var.smtp_password
}
