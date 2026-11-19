output "container_id" {
  value = docker_container.nginx.id
}

output "container_name" {
  value = docker_container.nginx.name
}

output "external_port" {
  value = var.external_port
}
