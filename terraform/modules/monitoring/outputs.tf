output "prometheus_name" {
  value = docker_container.prometheus.name
}

output "grafana_name" {
  value = docker_container.grafana.name
}

output "loki_name" {
  value = docker_container.loki.name
}

output "alloy_name" {
  value = docker_container.alloy.name
}

output "docker_api_proxy_name" {
  value = docker_container.docker_api_proxy.name
}

output "cadvisor_name" {
  value = docker_container.cadvisor.name
}

output "grafana_port" {
  value = var.grafana_port
}