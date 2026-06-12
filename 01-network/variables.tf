# ==============================================================================
# Input Variables
# ==============================================================================

variable "app_name" {
  description = "Application name used as a prefix for all resources"
  type        = string
  default     = "resumescorer"
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "resumescorer_production"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "resumescorer"
}

variable "smtp_user" {
  description = "SMTP username for Devise password reset emails"
  type        = string
  sensitive   = true
  default     = ""
}

variable "smtp_password" {
  description = "SMTP password for Devise password reset emails"
  type        = string
  sensitive   = true
  default     = ""
}

variable "smtp_server" {
  description = "SMTP server hostname"
  type        = string
  default     = "smtp.improvmx.com"
}

variable "smtp_port" {
  description = "SMTP server port"
  type        = string
  default     = "587"
}

variable "app_host" {
  description = "Public hostname for Devise password reset links (ALB DNS)"
  type        = string
  default     = ""
}
