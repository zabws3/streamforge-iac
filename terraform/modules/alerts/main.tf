resource "local_file" "alert_rules" {
  filename             = abspath("${path.root}/generated/alert.rules.yml")
  file_permission      = "0644"
  directory_permission = "0755"
  content = templatefile("${path.module}/alert.rules.yml.tftpl", {
    environment               = var.environment
    web_containers            = var.web_containers
    cache_enabled             = var.cache_enabled
    cpu_warning_threshold     = var.cpu_warning_threshold
    cpu_critical_threshold    = var.cpu_critical_threshold
    memory_warning_threshold  = var.memory_warning_threshold
    memory_critical_threshold = var.memory_critical_threshold
    disk_warning_threshold    = var.disk_warning_threshold
    disk_critical_threshold   = var.disk_critical_threshold
  })
}

resource "docker_image" "alertmanager" {
  name = "prom/alertmanager:latest"
}

resource "docker_volume" "alertmanager_data" {
  name = "${var.environment}_alertmanager_data"
}

resource "docker_container" "alertmanager" {
  name          = "${var.environment}_alertmanager"
  image         = docker_image.alertmanager.image_id
  read_only     = true
  security_opts = ["no-new-privileges:true"]

  capabilities {
    drop = ["ALL"]
  }

  entrypoint = ["/bin/sh", "/etc/alertmanager/entrypoint.sh"]
  restart    = "unless-stopped"
  tmpfs = {
    "/run" = "rw,noexec,nosuid,size=1m"
  }
  env = [
    "TELEGRAM_BOT_TOKEN=${var.telegram_bot_token}",
    "TELEGRAM_CHAT_ID=${var.telegram_chat_id}"
  ]

  healthcheck {
    test         = ["CMD-SHELL", "wget -qO- http://127.0.0.1:9093/-/healthy >/dev/null 2>&1"]
    interval     = "15s"
    timeout      = "5s"
    retries      = 3
    start_period = "30s"
  }

  mounts {
    type      = "bind"
    source    = abspath("${path.module}/alertmanager.yml.template")
    target    = "/etc/alertmanager/alertmanager.yml.template"
    read_only = true
  }

  mounts {
    type      = "bind"
    source    = abspath("${path.module}/alertmanager-entrypoint.sh")
    target    = "/etc/alertmanager/entrypoint.sh"
    read_only = true
  }

  mounts {
    type      = "bind"
    source    = abspath("${path.module}/alertmanager.tmpl")
    target    = "/etc/alertmanager/templates/streamforge.tmpl"
    read_only = true
  }

  volumes {
    volume_name    = docker_volume.alertmanager_data.name
    container_path = "/alertmanager"
  }

  dynamic "networks_advanced" {
    for_each = distinct([var.monitoring_network, var.telegram_egress_network])
    content {
      name = networks_advanced.value
    }
  }
}
