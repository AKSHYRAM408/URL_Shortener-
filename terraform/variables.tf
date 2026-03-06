# ──────────────────────────────────────────────────────────────────
# Input Variables
# ──────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "api_stage_name" {
  description = "API Gateway stage name (e.g. prod, dev)"
  type        = string
  default     = "prod"
}

variable "alert_email" {
  description = "Email address for billing alerts (you'll get notified if charges exceed $0.80)"
  type        = string
}
