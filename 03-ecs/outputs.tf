# ==============================================================================
# Outputs
# ==============================================================================

output "app_url" {
  description = "Public HTTPS URL for the resumescorer application"
  value       = "https://${var.app_hostname}"
}

output "alb_dns_name" {
  description = "Raw ALB DNS name (used internally; prefer app_url)"
  value       = aws_lb.resumescorer.dns_name
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.resumescorer.name
}

output "ecs_service_name" {
  value = aws_ecs_service.resumescorer.name
}
