resource "docker_image" "mysql" {
  name = "mysql:8.0"
}

resource "docker_volume" "database" {
  name = var.volume_name
}

resource "docker_container" "database" {
  name  = "${var.environment}_database"
  image = docker_image.mysql.image_id

  env = [
    "MYSQL_DATABASE=${var.database_name}",
    "MYSQL_USER=${var.database_user}",
    "MYSQL_PASSWORD=${var.database_password}",
    "MYSQL_ROOT_PASSWORD=${var.root_password}"
  ]

  networks_advanced {
    name = var.network
  }

  volumes {
    volume_name    = docker_volume.database.name
    container_path = "/var/lib/mysql"
  }
}