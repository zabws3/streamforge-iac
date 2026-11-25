variable "environment" {
  type    = string
  default = "pro"
}

variable "database_name" {
  type    = string
  default = "streamforge"
}

variable "database_user" {
  type    = string
  default = "streamforge"
}

variable "database_password" {
  type      = string
  sensitive = true
}

variable "database_root_password" {
  type      = string
  sensitive = true
}

variable "minio_user" {
  type    = string
  default = "streamforge"
}

variable "minio_password" {
  type      = string
  sensitive = true
}

variable "grafana_password" {
  type      = string
  sensitive = true
}

variable "session_secret" {
  type      = string
  sensitive = true
}

variable "telegram_bot_token" {
  type      = string
  sensitive = true

  validation {
    condition     = length(trimspace(var.telegram_bot_token)) > 0
    error_message = "telegram_bot_token must not be empty."
  }
}

variable "telegram_chat_id" {
  type      = string
  sensitive = true

  validation {
    condition     = can(regex("^-?[0-9]+$", var.telegram_chat_id))
    error_message = "telegram_chat_id must be a Telegram numeric chat ID."
  }
}

variable "alert_cpu_warning_threshold" {
  type    = number
  default = 80
}

variable "alert_cpu_critical_threshold" {
  type    = number
  default = 95
}

variable "alert_memory_warning_threshold" {
  type    = number
  default = 85
}

variable "alert_memory_critical_threshold" {
  type    = number
  default = 95
}
