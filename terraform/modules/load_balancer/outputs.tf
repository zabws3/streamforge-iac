output "container_id" {
  value = docker_container.haproxy.id
}

output "container_name" {
  value = docker_container.haproxy.name
}

output "external_port" {
  value = var.external_port
}
