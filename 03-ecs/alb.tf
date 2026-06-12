# ==============================================================================
# Application Load Balancer
# Public ALB in public subnets. HTTP/80 redirects to HTTPS; HTTPS/443
# terminates TLS with the ACM cert and forwards to Rails on port 3000.
# ==============================================================================

resource "aws_lb" "resumescorer" {
  name               = "resumescorer-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]

  subnets = [
    data.aws_subnet.pub-subnet-1.id,
    data.aws_subnet.pub-subnet-2.id
  ]

  tags = { Name = "resumescorer-alb" }
}

resource "aws_lb_target_group" "resumescorer" {
  name        = "resumescorer-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.ecs-vpc.id
  target_type = "ip"

  health_check {
    path                = "/users/sign_in"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 10
    interval            = 30
    matcher             = "200"
  }

  tags = { Name = "resumescorer-tg" }
}

# ------------------------------------------------------------------------------
# HTTP listener — permanent redirect to HTTPS
# Keeps port 80 open so bookmarked or typed HTTP URLs still work; they
# are immediately bounced to HTTPS with a 301 that browsers cache.
# ------------------------------------------------------------------------------
resource "aws_lb_listener" "resumescorer_http" {
  load_balancer_arn = aws_lb.resumescorer.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ------------------------------------------------------------------------------
# HTTPS listener — TLS termination at the ALB
# The ACM cert is attached here. Traffic from the ALB to ECS tasks is
# plain HTTP inside the VPC — no need for end-to-end TLS on private links.
# ------------------------------------------------------------------------------
resource "aws_lb_listener" "resumescorer_https" {
  load_balancer_arn = aws_lb.resumescorer.arn
  port              = 443
  protocol          = "HTTPS"
  # TLS 1.2+ policy — drops TLS 1.0/1.1 which are deprecated
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.resumescorer.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.resumescorer.arn
  }
}
