# ==============================================================================
# ECS Fargate Cluster, Task Definition, and Service
# ==============================================================================
# Fargate eliminates EC2 node management. Scoring jobs run inside the same
# container as Puma via Sidekiq — no separate worker service required.
# ==============================================================================

resource "aws_ecs_cluster" "resumescorer" {
  name = "resumescorer"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "resumescorer-cluster" }
}

# ------------------------------------------------------------------------------
# CloudWatch Log Group
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "resumescorer" {
  name              = "/ecs/resumescorer"
  retention_in_days = 7

  tags = { Name = "resumescorer-logs" }
}

# ------------------------------------------------------------------------------
# Task Definition
# Secrets injected from Secrets Manager — never in image layers or env logs.
# ------------------------------------------------------------------------------
resource "aws_ecs_task_definition" "resumescorer" {
  family                   = "resumescorer-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task_runtime.arn

  container_definitions = jsonencode([
    {
      name      = "resumescorer"
      image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.id}.amazonaws.com/resumescorer:${var.image_tag}"
      essential = true

      environment = [
        { name = "RAILS_ENV",                value = "production" },
        { name = "RAILS_LOG_TO_STDOUT",      value = "true" },
        { name = "RAILS_SERVE_STATIC_FILES", value = "true" },
        { name = "AWS_REGION",               value = data.aws_region.current.id },
        { name = "S3_BUCKET",                value = var.s3_bucket_name },
        { name = "SMTP_SERVER",              value = var.smtp_server },
        { name = "SMTP_PORT",                value = var.smtp_port },
        { name = "APP_HOST",                 value = var.app_host }
      ]

      # Secrets Manager injects these at task start before the container runs
      secrets = [
        { name = "DATABASE_URL",       valueFrom = data.aws_secretsmanager_secret.db_url.arn },
        { name = "REDIS_URL",          valueFrom = data.aws_secretsmanager_secret.redis_url.arn },
        { name = "SECRET_KEY_BASE",    valueFrom = data.aws_secretsmanager_secret.secret_key_base.arn },
        { name = "BEDROCK_MODEL_ID",   valueFrom = data.aws_secretsmanager_secret.bedrock_model_id.arn },
        { name = "SMTP_USER",          valueFrom = data.aws_secretsmanager_secret.smtp_user.arn },
        { name = "SMTP_PASSWORD",      valueFrom = data.aws_secretsmanager_secret.smtp_password.arn }
      ]

      portMappings = [
        { containerPort = 3000, hostPort = 3000, protocol = "tcp" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/resumescorer"
          "awslogs-region"        = data.aws_region.current.id
          "awslogs-stream-prefix" = "resumescorer"
        }
      }
    }
  ])
}

# ------------------------------------------------------------------------------
# ECS Service — Fargate, 1 desired task for demo (scale up as needed)
# ------------------------------------------------------------------------------
resource "aws_ecs_service" "resumescorer" {
  name                   = "resumescorer-service"
  cluster                = aws_ecs_cluster.resumescorer.id
  task_definition        = aws_ecs_task_definition.resumescorer.arn
  desired_count          = 1
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets = [
      data.aws_subnet.priv-subnet-1.id,
      data.aws_subnet.priv-subnet-2.id
    ]
    assign_public_ip = false
    security_groups  = [aws_security_group.ecs_service.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.resumescorer.arn
    container_name   = "resumescorer"
    container_port   = 3000
  }

  depends_on = [
    aws_lb_listener.resumescorer_http,
    aws_lb_listener.resumescorer_https,
  ]
}
