output "frontend_id" {
  description = "ID de la red frontend"
  value       = docker_network.frontend.id
}


output "backend_id" {
  description = "ID de la red backend"
  value       = docker_network.backend.id
}

output "monitoring_id" {
  description = "ID de la red monitoring"
  value       = docker_network.monitoring.id
}
