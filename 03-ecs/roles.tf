# ==============================================================================
# IAM Roles — ECS Task Execution and Runtime
# ==============================================================================

# ------------------------------------------------------------------------------
# Task Execution Role
# Used by ECS agent to pull images, write logs, and read Secrets Manager.
# ------------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRole-resumescorer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "execution_cloudwatch" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# Allow execution role to read the four application secrets at task start
resource "aws_iam_role_policy" "execution_secrets" {
  name = "resumescorer-execution-secrets"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = [
        data.aws_secretsmanager_secret.db_url.arn,
        data.aws_secretsmanager_secret.redis_url.arn,
        data.aws_secretsmanager_secret.secret_key_base.arn,
        data.aws_secretsmanager_secret.bedrock_model_id.arn,
        data.aws_secretsmanager_secret.smtp_user.arn,
        data.aws_secretsmanager_secret.smtp_password.arn
      ]
    }]
  })
}

# ------------------------------------------------------------------------------
# Task Runtime Role
# Assumed by the Rails container at runtime — needs S3 and Bedrock.
# ------------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task_runtime" {
  name = "ecsTaskRuntimeRole-resumescorer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# S3 read/write for ActiveStorage resume and attachment uploads
resource "aws_iam_role_policy" "runtime_s3" {
  name = "resumescorer-runtime-s3"
  role = aws_iam_role.ecs_task_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        "arn:aws:s3:::${var.s3_bucket_name}",
        "arn:aws:s3:::${var.s3_bucket_name}/*"
      ]
    }]
  })
}

# Bedrock inference — used by ScoringJob to call Claude Haiku
resource "aws_iam_role_policy" "runtime_bedrock" {
  name = "resumescorer-runtime-bedrock"
  role = aws_iam_role.ecs_task_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel"]
      Resource = "*"
    }]
  })
}

# ECS Exec — allows `aws ecs execute-command` for debugging
resource "aws_iam_role_policy" "runtime_exec" {
  name = "resumescorer-runtime-exec"
  role = aws_iam_role.ecs_task_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ]
      Resource = "*"
    }]
  })
}
