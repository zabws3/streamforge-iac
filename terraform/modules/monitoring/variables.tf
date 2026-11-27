variable "environment" {
  type = string
}

variable "networks" {
  type = list(string)
}

variable "grafana_networks" {
  type = list(string)
}

variable "host_access_network" {
  type = string
}

variable "alert_rules_path" {
  description = "Optional path to the alert rules file managed by the alerts module."
  type        = string
  default     = ""
}

variable "alertmanager_target" {
  description = "Optional Alertmanager host and port used by Prometheus."
  type        = string
  default     = ""
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

variable "prometheus_port" {
  type    = number
  default = 9090
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

variable "docker_socket_gid" {
  description = "Host group ID that owns /var/run/docker.sock"
  type        = number
  default     = 126
}
