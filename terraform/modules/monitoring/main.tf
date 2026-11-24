locals {
  blackbox_probes = concat(
    [
      for container in var.web_containers : {
        target    = "http://${container}:3000/health"
        module    = "http_2xx"
        service   = "streamforge-web"
        container = container
      }
    ],
    [
      {
        target    = "http://${var.environment}_load_balancer/health"
        module    = "http_2xx"
        service   = "streamforge-load-balancer"
        container = "${var.environment}_load_balancer"
      },
      {
        target    = "http://${var.environment}-minio:9000/minio/health/ready"
        module    = "http_2xx"
        service   = "minio"
        container = "${var.environment}_minio"
      },
      {
        target    = "${var.environment}_database:3306"
        module    = "tcp_connect"
        service   = "mysql"
        container = "${var.environment}_database"
      },
      {
        target    = "${var.environment}_redis:6379"
        module    = "tcp_connect"
        service   = "redis"
        container = "${var.environment}_redis"
      }
    ]
  )
}

############ PROMETHEUS ###################

resource "local_file" "prometheus_config" {
  filename             = abspath("${path.root}/generated/prometheus.yml")
  file_permission      = "0644"
  directory_permission = "0755"
  content = templatefile("${path.module}/prometheus.yml.tftpl", {
    environment = var.environment
    probes      = local.blackbox_probes
  })
}

resource "local_file" "alert_rules" {
  filename             = abspath("${path.root}/generated/alert.rules.yml")
  file_permission      = "0644"
  directory_permission = "0755"
  content = templatefile("${path.module}/alert.rules.yml.tftpl", {
    environment               = var.environment
    web_containers            = var.web_containers
    cpu_warning_threshold     = var.cpu_warning_threshold
    cpu_critical_threshold    = var.cpu_critical_threshold
    memory_warning_threshold  = var.memory_warning_threshold
    memory_critical_threshold = var.memory_critical_threshold
    disk_warning_threshold    = var.disk_warning_threshold
    disk_critical_threshold   = var.disk_critical_threshold
  })
}

resource "local_file" "blackbox_config" {
  filename             = abspath("${path.root}/generated/blackbox.yml")
  file_permission      = "0644"
  directory_permission = "0755"
  content              = file("${path.module}/blackbox.yml")
}

resource "docker_image" "prometheus" {
  name = var.image
}

resource "docker_container" "prometheus" {
  name  = "${var.environment}_prometheus"
  image = docker_image.prometheus.image_id

  command = [
    "--config.file=/etc/prometheus/prometheus.yml",
    "--storage.tsdb.path=/prometheus"
  ]

  healthcheck {
    test         = ["CMD", "/bin/wget", "-qO-", "http://127.0.0.1:9090/-/healthy"]
    interval     = "15s"
    timeout      = "5s"
    retries      = 3
    start_period = "30s"
  }

  mounts {
    type   = "bind"
    source = local_file.prometheus_config.filename
    target = "/etc/prometheus/prometheus.yml"
  }

  mounts {
    type   = "bind"
    source = local_file.alert_rules.filename
    target = "/etc/prometheus/alert.rules.yml"
  }

  dynamic "networks_advanced" {
    for_each = var.networks
    content {
      name = networks_advanced.value
    }
  }

  depends_on = [
    docker_container.alertmanager,
    docker_container.blackbox_exporter,
    docker_container.node_exporter
  ]
}


############ CADVISOR #################
resource "docker_image" "cadvisor" {
  name = "gcr.io/cadvisor/cadvisor:latest"
}

resource "docker_container" "cadvisor" {
  name  = "${var.environment}_cadvisor"
  image = docker_image.cadvisor.image_id

  privileged = true

  dynamic "networks_advanced" {
    for_each = var.networks
    content {
      name = networks_advanced.value
    }
  }

  mounts {
    type   = "bind"
    source = "/"
    target = "/rootfs"
  }

  mounts {
    type   = "bind"
    source = "/var/run"
    target = "/var/run"
  }

  mounts {
    type   = "bind"
    source = "/sys"
    target = "/sys"
  }

  mounts {
    type   = "bind"
    source = "/var/lib/docker"
    target = "/var/lib/docker"
  }

  mounts {
    type   = "bind"
    source = "/dev/disk"
    target = "/dev/disk"
  }
}

################### BLACKBOX EXPORTER ###################
resource "docker_image" "blackbox_exporter" {
  name = "prom/blackbox-exporter:latest"
}

resource "docker_container" "blackbox_exporter" {
  name  = "${var.environment}_blackbox_exporter"
  image = docker_image.blackbox_exporter.image_id

  command = ["--config.file=/etc/blackbox/blackbox.yml"]
  restart = "unless-stopped"

  mounts {
    type      = "bind"
    source    = local_file.blackbox_config.filename
    target    = "/etc/blackbox/blackbox.yml"
    read_only = true
  }

  dynamic "networks_advanced" {
    for_each = distinct(concat(var.networks, var.probe_networks))
    content {
      name = networks_advanced.value
    }
  }
}

################### NODE EXPORTER ###################
resource "docker_image" "node_exporter" {
  name = "prom/node-exporter:latest"
}

resource "docker_container" "node_exporter" {
  name  = "${var.environment}_node_exporter"
  image = docker_image.node_exporter.image_id

  command = [
    "--path.rootfs=/host",
    "--path.procfs=/host/proc",
    "--path.sysfs=/host/sys",
    "--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|var/lib/docker/.+|var/lib/containers/storage/.+)($|/)"
  ]
  restart = "unless-stopped"

  mounts {
    type      = "bind"
    source    = "/"
    target    = "/host"
    read_only = true
  }

  dynamic "networks_advanced" {
    for_each = var.networks
    content {
      name = networks_advanced.value
    }
  }
}

################### ALERTMANAGER ###################
resource "docker_image" "alertmanager" {
  name = "prom/alertmanager:latest"
}

resource "docker_volume" "alertmanager_data" {
  name = "${var.environment}_alertmanager_data"
}

resource "docker_container" "alertmanager" {
  name  = "${var.environment}_alertmanager"
  image = docker_image.alertmanager.image_id

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
    for_each = distinct(concat(var.networks, [var.telegram_egress_network]))
    content {
      name = networks_advanced.value
    }
  }
}
################### GRAFANA ###################
resource "docker_image" "grafana" {
  name = var.grafana_image
}

resource "docker_container" "grafana" {
  name  = "${var.environment}_grafana"
  image = docker_image.grafana.image_id

  healthcheck {
    test         = ["CMD", "/usr/bin/curl", "-fsS", "-o", "/dev/null", "http://127.0.0.1:3000/api/health"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "60s"
  }

  env = [
    "GF_SECURITY_ADMIN_PASSWORD=${var.grafana_admin_password}"
  ]

  ports {
    external = var.grafana_port
    internal = 3000
  }

  dynamic "networks_advanced" {
    for_each = var.grafana_networks
    content {
      name = networks_advanced.value
    }
  }

  mounts {
    type   = "bind"
    source = local_file.grafana_datasource.filename
    target = "/etc/grafana/provisioning/datasources/datasource.yml" # Prometheus
  }
  mounts {
    type   = "bind"
    source = local_file.grafana_loki_datasource.filename
    target = "/etc/grafana/provisioning/datasources/loki.yml" # Loki
  }

  mounts {
    type      = "bind"
    source    = abspath("${path.module}/grafana/provisioning/dashboards.yml")
    target    = "/etc/grafana/provisioning/dashboards/dashboards.yml"
    read_only = true
  }

  mounts {
    type      = "bind"
    source    = abspath("${path.module}/grafana/dashboards")
    target    = "/var/lib/grafana/dashboards"
    read_only = true
  }

}


resource "local_file" "grafana_datasource" {
  filename             = abspath("${path.root}/generated/datasource.yml")
  file_permission      = "0644"
  directory_permission = "0755"
  content              = <<-EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://${var.environment}_prometheus:9090
    isDefault: true
EOF
}
############### LOKI #################

resource "local_file" "loki_config" {
  filename             = abspath("${path.root}/generated/loki-config.yml")
  file_permission      = "0644"
  directory_permission = "0755"
  content              = file("${path.module}/loki.yml")
}

resource "docker_image" "loki" {
  name = var.loki_image
}

resource "docker_volume" "loki_data" {
  name = "${var.environment}_loki_data"
}

resource "docker_container" "loki" {
  name  = "${var.environment}_loki"
  image = docker_image.loki.image_id

  command = ["-config.file=/etc/loki/local-config.yaml"]

  mounts {
    type   = "bind"
    source = local_file.loki_config.filename
    target = "/etc/loki/local-config.yaml"
  }

  volumes {
    volume_name    = docker_volume.loki_data.name
    container_path = "/loki"
  }

  dynamic "networks_advanced" {
    for_each = var.networks
    content {
      name = networks_advanced.value
    }
  }
}

################### ALLOY ###################

resource "local_file" "alloy_config" {
  filename             = abspath("${path.root}/generated/alloy-config.alloy")
  file_permission      = "0644"
  directory_permission = "0755"
  content = templatefile("${path.module}/config.alloy", {
    environment = var.environment
  })
}


resource "docker_image" "alloy" {
  name = var.alloy_image
}

resource "docker_container" "alloy" {
  name  = "${var.environment}_alloy"
  image = docker_image.alloy.image_id

  command = [
    "run",
    "--server.http.listen-addr=0.0.0.0:12345",
    "--storage.path=/var/lib/alloy/data",
    "/etc/alloy/config.alloy"
  ]

  dynamic "networks_advanced" {
    for_each = var.networks
    content {
      name = networks_advanced.value
    }
  }

  mounts {
    type   = "bind"
    source = local_file.alloy_config.filename
    target = "/etc/alloy/config.alloy"
  }

  mounts {
    type   = "bind"
    source = "/var/run/docker.sock"
    target = "/var/run/docker.sock"
  }
}


############### ALLOY - LOKI ###############

resource "local_file" "grafana_loki_datasource" {
  filename             = abspath("${path.root}/generated/datasource-loki.yml")
  file_permission      = "0644"
  directory_permission = "0755"
  content              = <<-EOF
apiVersion: 1

datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://${var.environment}_loki:3100
    isDefault: false
EOF
}
