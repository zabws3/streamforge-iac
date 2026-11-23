variable "environment" {
  type = string
}

variable "networks" {
  type = list(string)
}

variable "image" {
  type    = string
  default = "redis:7-alpine"
}
