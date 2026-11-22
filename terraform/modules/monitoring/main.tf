############ PROMETHEUS ###################

resource "local_file" "prometheus_config" {
  filename=abspath("${path.root}/generated/prometheus.yml")
  file_permission      = "0644"
  directory_permission = "0755"
  content = <<-EOF
    global:
      scrape_interval: 15s

    scrape_configs:
      - job_name: 'cadvisor'
        static_configs:
          - targets: ['${var.environment}_cadvisor:8080']
  EOF
}

resource "docker_image" "prometheus" {
  name = var.image
}

resource "docker_container" "prometheus" {
  name  = "${var.environment}_prometheus"
  image = docker_image.prometheus.image_id

  mounts {
    type   = "bind"
    source = local_file.prometheus_config.filename
    target = "/etc/prometheus/prometheus.yml"
  }

  networks_advanced {
    name = var.network
  }
}


############ CADVISOR #################
resource "docker_image" "cadvisor" {
  name = "gcr.io/cadvisor/cadvisor:latest"
}

resource "docker_container" "cadvisor" {
  name  = "${var.environment}_cadvisor"
  image = docker_image.cadvisor.image_id

  privileged = true

  ports {
    internal = 8080
  }

  networks_advanced {
    name = var.network
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
################### GRAFANA ###################
resource "docker_image" "grafana" {
  name = var.grafana_image
}

resource "docker_container" "grafana" {
  name  = "${var.environment}_grafana"
  image = docker_image.grafana.image_id

  env = [
    "GF_SECURITY_ADMIN_PASSWORD=${var.grafana_admin_password}"
  ]

  ports {
    external = var.grafana_port
    internal = 3000
  }

  networks_advanced {
    name = var.network
  }

  networks_advanced {
    name = var.frontend_network
  }

  mounts {
    type   = "bind"
    source = local_file.grafana_datasource.filename
    target = "/etc/grafana/provisioning/datasources/datasource.yml" # Prometheus
  }
  mounts {
    type   = "bind"
    source = local_file.grafana_loki_datasource.filename
    target = "/etc/grafana/provisioning/datasources/loki.yml"       # Loki
  }

}


resource "local_file" "grafana_datasource" {
  filename = abspath("${path.root}/generated/datasource.yml")
  file_permission      = "0644"
  directory_permission = "0755"
  content = <<-EOF
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
  filename = abspath("${path.root}/generated/loki-config.yml")
  file_permission      = "0644"
  directory_permission = "0755"
  content = file("${path.module}/loki.yml")
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

  networks_advanced {
    name = var.network
  }
}

################### ALLOY ###################

resource "local_file" "alloy_config" {
  filename = abspath("${path.root}/generated/alloy-config.alloy")
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

  networks_advanced {
    name = var.network
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
  filename = abspath("${path.root}/generated/datasource-loki.yml")
  file_permission      = "0644"
  directory_permission = "0755"
  content = <<-EOF
apiVersion: 1

datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://${var.environment}_loki:3100
    isDefault: false
EOF
}

