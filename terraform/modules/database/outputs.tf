output "container_id" {
  value = docker_container.database.id
}

output "container_name" {
  value = docker_container.database.name
}

output "volume_name" {
  value = docker_volume.database.name
}