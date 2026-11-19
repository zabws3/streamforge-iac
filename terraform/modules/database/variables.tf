variable "environment" {
  type = string
}

variable "database_name" {
  type = string
}

variable "database_user" {
  type = string
}

#Sensitive para ocultar el valor en la salida de consola y para q no se guarde en tfstate

variable "database_password" {
  type      = string
  sensitive  = true
}

variable "root_password" {
  type      = string
  sensitive  = true
}

variable "network" {
  type = string
}

variable "volume_name" {
  type = string
}