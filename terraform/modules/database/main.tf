resource "docker_image" "mysql" {
  name = "mysql:8.0"
}

resource "docker_volume" "database" {
  name = var.volume_name
}

resource "docker_container" "database" {
  name  = "${var.environment}_database"
  image = docker_image.mysql.image_id

  healthcheck {
    test         = ["CMD-SHELL", "MYSQL_PWD=\"$MYSQL_PASSWORD\" mysql --protocol=TCP --connect-timeout=3 -h 127.0.0.1 -u \"$MYSQL_USER\" \"$MYSQL_DATABASE\" --batch --skip-column-names -e 'SELECT 1' >/dev/null 2>&1"]
    interval     = "10s"
    timeout      = "5s"
    retries      = 6
    start_period = "60s"
  }

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

  mounts {
    type   = "bind"
    source = abspath("${path.module}/../../../db/init.sql")
    target = "/docker-entrypoint-initdb.d/init.sql"
  }

}