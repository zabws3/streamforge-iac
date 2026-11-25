output "alert_rules_path" {
  value = local_file.alert_rules.filename
}

output "alertmanager_target" {
  value = "${docker_container.alertmanager.name}:9093"
}
