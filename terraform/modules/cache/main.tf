resource "docker_image" "redis" {
  name = var.image
}

resource "docker_container" "redis" {
  name  = "${var.environment}_redis"
  image = docker_image.redis.image_id

  networks_advanced {
    name = var.network
  }

  ports {
    internal = 6379
  }
}

