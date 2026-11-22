resource "docker_image" "minio" {
  name = "pgsty/silo:RELEASE.2026-11-12T00-00-00Z"
}
  
resource "docker_volume" "storage" {
  name = "${var.environment}_minio_data"
}

resource "docker_container" "minio" {
  name  = "${var.environment}_minio"
  image = docker_image.minio.image_id

  command = ["server", "/data", "--console-address", ":9001"]

  env = [
    "MINIO_ROOT_USER=${var.root_user}",
    "MINIO_ROOT_PASSWORD=${var.root_password}"
  ]

  ports {
    external = var.api_port
    internal = 9000
  }

  ports {
    external = var.console_port
    internal = 9001
  }

  networks_advanced {
    name = var.network
  }

  volumes {
    volume_name    = docker_volume.storage.name
    container_path = "/data"
  }
}
