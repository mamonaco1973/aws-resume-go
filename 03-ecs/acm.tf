# ==============================================================================
# ACM Certificate and Route 53 DNS
# Provisions a TLS certificate for the custom domain, validates it via
# DNS records in Route 53, and creates an A-alias record pointing the
# hostname to the ALB.
#
# DNS validation is preferred over email validation because it is fully
# automated — Terraform creates the CNAME validation record in Route 53,
# AWS validates it, and the cert is issued without any manual step.
# ==============================================================================

# ------------------------------------------------------------------------------
# ACM Certificate
# ------------------------------------------------------------------------------
resource "aws_acm_certificate" "resumescorer" {
  domain_name       = var.app_hostname
  validation_method = "DNS"

  # create_before_destroy prevents downtime during cert renewal — the
  # new cert is issued before the old one is removed from the listener.
  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "resumescorer-cert" }
}

# ------------------------------------------------------------------------------
# Route 53 Hosted Zone (data source — zone must already exist)
# ------------------------------------------------------------------------------
data "aws_route53_zone" "zone" {
  name         = var.hosted_zone_name
  private_zone = false
}

# ------------------------------------------------------------------------------
# DNS Validation Records
# ACM provides one CNAME record per domain; Terraform creates it in Route 53.
# for_each handles the case where the cert covers multiple SANs.
# ------------------------------------------------------------------------------
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.resumescorer.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.zone.zone_id
}

# Waits until AWS confirms the cert is issued before the HTTPS listener
# is allowed to reference it. Without this, apply would race and fail.
resource "aws_acm_certificate_validation" "resumescorer" {
  certificate_arn         = aws_acm_certificate.resumescorer.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# ------------------------------------------------------------------------------
# Route 53 A Alias — hostname → ALB
# An alias record is preferred over a CNAME for apex/subdomain → ALB
# because AWS resolves it internally (no extra DNS hop) and it is free.
# ------------------------------------------------------------------------------
resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = var.app_hostname
  type    = "A"

  alias {
    name                   = aws_lb.resumescorer.dns_name
    zone_id                = aws_lb.resumescorer.zone_id
    evaluate_target_health = true
  }
}
