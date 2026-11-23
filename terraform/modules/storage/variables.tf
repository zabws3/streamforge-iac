variable "environment" {
  type = string
}

variable "networks" {
  type = list(string)
}

variable "root_user" {
  type = string
}

variable "root_password" {
  type      = string
  sensitive = true
}

variable "api_port" {
  type    = number
  default = 9000
}

variable "console_port" {
  type    = number
  default = 9001
}