variable "environment" {
  type = string
}

variable "networks" {
  type = list(string)
}

variable "grafana_networks" {
  type = list(string)
}

variable "web_containers" {
  type = list(string)
}

variable "probe_networks" {
  type    = list(string)
  default = []
}

variable "telegram_egress_network" {
  type = string
}

variable "telegram_bot_token" {
  type      = string
  sensitive = true
}

variable "telegram_chat_id" {
  type      = string
  sensitive = true
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

variable "disk_warning_threshold" {
  type    = number
  default = 85

  validation {
    condition     = var.disk_warning_threshold > 0 && var.disk_warning_threshold <= 100
    error_message = "Disk warning threshold must be greater than 0 and at most 100."
  }
}

variable "disk_critical_threshold" {
  type    = number
  default = 95

  validation {
    condition     = var.disk_critical_threshold > 0 && var.disk_critical_threshold <= 100
    error_message = "Disk critical threshold must be greater than 0 and at most 100."
  }
}

variable "image" {
  type    = string
  default = "prom/prometheus:latest"
}

variable "grafana_image" {
  type    = string
  default = "grafana/grafana:latest"
}

variable "grafana_port" {
  type    = number
  default = 3000
}

variable "grafana_admin_password" {
  type      = string
  sensitive = true
}


variable "loki_image" {
  type    = string
  default = "grafana/loki:latest"
}


variable "alloy_image" {
  type    = string
  default = "grafana/alloy:latest"
}
