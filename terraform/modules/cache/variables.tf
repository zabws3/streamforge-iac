variable "environment" {
  type = string
}

variable "network" {
  type = string
}

variable "image" {
  type    = string
  default = "redis:7-alpine"
}
