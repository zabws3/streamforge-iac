variable "environment" {
  type = string
}

variable "network" {
  type = string
}

variable "web_containers" {
  type = list(string)
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
  sensitive  = true
}


variable "loki_image" {
  type    = string
  default = "grafana/loki:latest"
}


variable "alloy_image" {
  type    = string
  default = "grafana/alloy:latest"
}

