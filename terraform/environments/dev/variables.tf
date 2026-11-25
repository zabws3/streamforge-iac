variable "environment" {
  type    = string
  default = "dev"
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
