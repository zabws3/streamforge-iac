variable "environment" {
  type = string
}

variable "web_containers" {
  type = list(string)
}

variable "network" {
  type = string
}

variable "image" {
  type    = string
  default = "nginx:alpine"
}

variable "external_port" {
  type = number
  default = 8080
}

