output "container_ids" {
  value = docker_container.web[*].id
}

output "container_names" {
  value = docker_container.web[*].name
}