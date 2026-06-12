# ==============================================================================
# Security Groups — ALB and ECS Service
# ==============================================================================

# ------------------------------------------------------------------------------
# ALB Security Group
# Accepts HTTP (80) and HTTPS (443) from the internet.
# ECS tasks only accept traffic from the ALB, never directly from the internet.
# ------------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "resumescorer-alb-sg"
  description = "ALB inbound HTTP and HTTPS"
  vpc_id      = data.aws_vpc.ecs-vpc.id

  ingress {
    description = "HTTP from internet — redirected to HTTPS by ALB listener"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "resumescorer-alb-sg" }
}

# ------------------------------------------------------------------------------
# ECS Service Security Group
# Rails runs on port 3000; only the ALB is allowed to initiate connections.
# ------------------------------------------------------------------------------
resource "aws_security_group" "ecs_service" {
  name        = "resumescorer-ecs-sg"
  description = "ECS tasks - allow from ALB only"
  vpc_id      = data.aws_vpc.ecs-vpc.id

  ingress {
    description     = "Rails from ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "resumescorer-ecs-sg" }
}
