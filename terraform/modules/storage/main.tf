resource "docker_image" "minio" {
  name = "streamforge-silo:${var.environment}"

  build {
    context    = abspath(path.module)
    dockerfile = "Dockerfile"
  }
}

resource "docker_volume" "storage" {
  name = "${var.environment}_minio_data"
}

resource "docker_container" "minio" {
  name  = "${var.environment}_minio"
  image = docker_image.minio.image_id

  healthcheck {
    test         = ["CMD", "/usr/bin/curl", "-fsS", "-o", "/dev/null", "http://127.0.0.1:9000/minio/health/ready"]
    interval     = "15s"
    timeout      = "5s"
    retries      = 3
    start_period = "60s"
  }

  command = ["server", "/data", "--console-address", ":9001"]

  env = [
    "MINIO_ROOT_USER=${var.root_user}",
    "MINIO_ROOT_PASSWORD=${var.root_password}"
  ]

  ports {
    external = var.api_port
    internal = 9000
    ip       = "127.0.0.1"
  }

  ports {
    external = var.console_port
    internal = 9001
    ip       = "127.0.0.1"
  }

  dynamic "networks_advanced" {
    for_each = var.networks
    content {
      name    = networks_advanced.value
      aliases = ["${var.environment}-minio"]
    }
  }

  volumes {
    volume_name    = docker_volume.storage.name
    container_path = "/data"
  }

  volumes {
    host_path      = abspath("${path.module}/../../../media")
    container_path = "/media"
    read_only      = true
  }
}
