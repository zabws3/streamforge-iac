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
      }
    ],
    var.cache_enabled ? [
      {
        target    = "${var.environment}_redis:6379"
        module    = "tcp_connect"
        service   = "redis"
        container = "${var.environment}_redis"
      }
    ] : []
  )
}

############ PROMETHEUS ###################

resource "local_file" "prometheus_config" {
  filename             = abspath("${path.root}/generated/prometheus.yml")
  file_permission      = "0644"
  directory_permission = "0755"
  content = templatefile("${path.module}/prometheus.yml.tftpl", {
    environment         = var.environment
    probes              = local.blackbox_probes
    alerts_enabled      = var.alert_rules_path != ""
    alertmanager_target = var.alertmanager_target
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
  name          = "${var.environment}_prometheus"
  image         = docker_image.prometheus.image_id
  read_only     = true
  security_opts = ["no-new-privileges:true"]

  capabilities {
    drop = ["ALL"]
  }

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

  tmpfs = {
    "/tmp" = "rw,noexec,nosuid,size=64m"
  }

  mounts {
    type      = "bind"
    source    = local_file.prometheus_config.filename
    target    = "/etc/prometheus/prometheus.yml"
    read_only = true
  }

  dynamic "mounts" {
    for_each = var.alert_rules_path != "" ? [var.alert_rules_path] : []
    content {
      type      = "bind"
      source    = mounts.value
      target    = "/etc/prometheus/alert.rules.yml"
      read_only = true
    }
  }

  volumes {
    volume_name    = docker_volume.prometheus_data.name
    container_path = "/prometheus"
  }

  dynamic "networks_advanced" {
    for_each = distinct(concat(var.networks, [var.host_access_network]))
    content {
      name = networks_advanced.value
    }
  }

  ports {
    external = var.prometheus_port
    internal = 9090
    ip       = "127.0.0.1"
  }

  depends_on = [
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

  read_only     = true
  security_opts = ["no-new-privileges:true"]

  capabilities {
    drop = ["ALL"]
  }

  command = [
    "--docker_only=true",
    "--enable_metrics=cpu,memory,network",
    "--housekeeping_interval=15s",
    "--store_container_labels=false"
  ]

  dynamic "networks_advanced" {
    for_each = var.networks
    content {
      name = networks_advanced.value
    }
  }

  mounts {
    type      = "bind"
    source    = "/sys"
    target    = "/sys"
    read_only = true
  }

  mounts {
    type      = "bind"
    source    = "/var/lib/docker"
    target    = "/var/lib/docker"
    read_only = true
  }

  # Socket mounts are read-only, but their APIs remain powerful; this container
  # is therefore unprivileged, unexposed, and reachable only on monitoring.
  mounts {
    type      = "bind"
    source    = "/var/run/docker.sock"
    target    = "/var/run/docker.sock"
    read_only = true
  }

  mounts {
    type      = "bind"
    source    = "/run/containerd/containerd.sock"
    target    = "/run/containerd/containerd.sock"
    read_only = true
  }
}

################### BLACKBOX EXPORTER ###################
resource "docker_image" "blackbox_exporter" {
  name = "prom/blackbox-exporter:latest"
}

resource "docker_container" "blackbox_exporter" {
  name          = "${var.environment}_blackbox_exporter"
  image         = docker_image.blackbox_exporter.image_id
  read_only     = true
  security_opts = ["no-new-privileges:true"]

  capabilities {
    drop = ["ALL"]
  }

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
  name          = "${var.environment}_node_exporter"
  image         = docker_image.node_exporter.image_id
  read_only     = true
  security_opts = ["no-new-privileges:true"]

  capabilities {
    drop = ["ALL"]
  }

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
resource "docker_volume" "prometheus_data" {
  name = "${var.environment}_prometheus_data"
}

resource "docker_volume" "grafana_data" {
  name = "${var.environment}_grafana_data"
}

resource "docker_volume" "alloy_data" {
  name = "${var.environment}_alloy_data"
}

################### GRAFANA ###################
resource "docker_image" "grafana" {
  name = var.grafana_image
}

resource "docker_container" "grafana" {
  name          = "${var.environment}_grafana"
  image         = docker_image.grafana.image_id
  read_only     = true
  security_opts = ["no-new-privileges:true"]

  capabilities {
    drop = ["ALL"]
  }

  tmpfs = {
    "/tmp" = "rw,noexec,nosuid,size=64m"
  }

  healthcheck {
    test         = ["CMD", "/usr/bin/curl", "-fsS", "-o", "/dev/null", "http://127.0.0.1:3000/api/health"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "60s"
  }

  env = [
    "GF_SECURITY_ADMIN_PASSWORD=${var.grafana_admin_password}",
    "GF_LOG_MODE=console"
  ]

  ports {
    external = var.grafana_port
    internal = 3000
    ip       = "127.0.0.1"
  }

  dynamic "networks_advanced" {
    for_each = distinct(concat(var.grafana_networks, [var.host_access_network]))
    content {
      name = networks_advanced.value
    }
  }

  mounts {
    type      = "bind"
    source    = local_file.grafana_datasource.filename
    target    = "/etc/grafana/provisioning/datasources/datasource.yml" # Prometheus
    read_only = true
  }
  mounts {
    type      = "bind"
    source    = local_file.grafana_loki_datasource.filename
    target    = "/etc/grafana/provisioning/datasources/loki.yml" # Loki
    read_only = true
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

  volumes {
    volume_name    = docker_volume.grafana_data.name
    container_path = "/var/lib/grafana"
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

  command       = ["-config.file=/etc/loki/local-config.yaml"]
  read_only     = true
  security_opts = ["no-new-privileges:true"]

  capabilities {
    drop = ["ALL"]
  }

  mounts {
    type      = "bind"
    source    = local_file.loki_config.filename
    target    = "/etc/loki/local-config.yaml"
    read_only = true
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

  lifecycle {
    replace_triggered_by = [local_file.loki_config]
  }
}

################### ALLOY ###################

resource "local_file" "alloy_config" {
  filename             = abspath("${path.root}/generated/alloy-config.alloy")
  file_permission      = "0644"
  directory_permission = "0755"
  content = templatefile("${path.module}/config.alloy", {
    environment = var.environment
    docker_host = "unix:///var/run/docker.sock"
  })
}


resource "docker_image" "alloy" {
  name = var.alloy_image
}

resource "docker_container" "alloy" {
  name          = "${var.environment}_alloy"
  image         = docker_image.alloy.image_id
  user          = "alloy"
  read_only     = true
  security_opts = ["no-new-privileges:true"]
  group_add     = [tostring(var.docker_socket_gid)]

  capabilities {
    drop = ["ALL"]
  }

  command = [
    "run",
    "--server.http.listen-addr=0.0.0.0:12345",
    "--storage.path=/var/lib/alloy/data",
    "/etc/alloy/config.alloy"
  ]

  volumes {
    volume_name    = docker_volume.alloy_data.name
    container_path = "/var/lib/alloy/data"
  }

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
    read_only      = true
  }

  dynamic "networks_advanced" {
    for_each = var.networks
    content {
      name = networks_advanced.value
    }
  }

  mounts {
    type      = "bind"
    source    = local_file.alloy_config.filename
    target    = "/etc/alloy/config.alloy"
    read_only = true
  }

  lifecycle {
    replace_triggered_by = [local_file.alloy_config]
  }

  depends_on = [docker_container.loki]
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
