variable "environment" {
  type = string
}

variable "monitoring_network" {
  type = string
}

variable "telegram_egress_network" {
  type = string
}

variable "web_containers" {
  type = list(string)
}

variable "cache_enabled" {
  type = bool
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

variable "cpu_warning_threshold" {
  type    = number
  default = 80

  validation {
    condition     = var.cpu_warning_threshold > 0 && var.cpu_warning_threshold <= 100
    error_message = "CPU warning threshold must be greater than 0 and at most 100."
  }
}

variable "cpu_critical_threshold" {
  type    = number
  default = 95

  validation {
    condition     = var.cpu_critical_threshold > 0 && var.cpu_critical_threshold <= 100
    error_message = "CPU critical threshold must be greater than 0 and at most 100."
  }
}

variable "memory_warning_threshold" {
  type    = number
  default = 85

  validation {
    condition     = var.memory_warning_threshold > 0 && var.memory_warning_threshold <= 100
    error_message = "Memory warning threshold must be greater than 0 and at most 100."
  }
}

variable "memory_critical_threshold" {
  type    = number
  default = 95

  validation {
    condition     = var.memory_critical_threshold > 0 && var.memory_critical_threshold <= 100
    error_message = "Memory critical threshold must be greater than 0 and at most 100."
  }
}
