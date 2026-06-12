# ==============================================================================
# Input Variables
# ==============================================================================

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

# S3 bucket name passed in from apply.sh (captured from 01-network output)
variable "s3_bucket_name" {
  description = "S3 bucket for ActiveStorage uploads"
  type        = string
}

variable "smtp_server" {
  description = "SMTP server hostname (plain env var — not sensitive)"
  type        = string
  default     = "smtp.improvmx.com"
}

variable "smtp_port" {
  description = "SMTP server port"
  type        = string
  default     = "587"
}

variable "app_host" {
  description = "Public hostname for Devise password reset links"
  type        = string
  default     = ""
}

variable "app_hostname" {
  description = "Custom domain for the app (e.g. myjobs-ror.mikes-cloud-solutions.com)"
  type        = string
  default     = "myjobs-ror.mikes-cloud-solutions.com"
}

variable "hosted_zone_name" {
  description = "Route 53 hosted zone that owns the domain (e.g. mikes-cloud-solutions.com)"
  type        = string
  default     = "mikes-cloud-solutions.com"
}
