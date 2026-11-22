resource "docker_image" "redis" {
  name = var.image
}

resource "docker_container" "redis" {
  name  = "${var.environment}_redis"
  image = docker_image.redis.image_id

  healthcheck {
    test         = ["CMD", "redis-cli", "-h", "127.0.0.1", "ping"]
    interval     = "10s"
    timeout      = "3s"
    retries      = 3
    start_period = "10s"
  }

  networks_advanced {
    name = var.network
  }

}
