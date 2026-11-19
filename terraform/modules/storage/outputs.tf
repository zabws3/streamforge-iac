output "container_id" {
  value = docker_container.minio.id
}

output "container_name" {
  value = docker_container.minio.name
}

output "api_port" {
  value = var.api_port
}

output "console_port" {
  value = var.console_port
}

output "volume_name" {
  value = docker_volume.storage.name
}
