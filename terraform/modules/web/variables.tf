variable "environment" {
  type = string
}

variable "replicas" {
  type = number
}

variable "image" {
  type = string
}

variable "internal_port" {
  type    = number
  default = 3000
}

variable "networks" {
  type = list(string)
}

variable "env_vars" {
  type = map(string)
}
