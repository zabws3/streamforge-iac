variable "environment" {
  type = string
}

variable "replicas" {
  type = number
}

variable "image" {
  type = string
}

variable "networks" {
  type = list(string)
}

variable "env_vars" {
  type = map(string)
}
