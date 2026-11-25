resource "docker_image" "web" {
  name = var.image

  build {
    context    = abspath("${path.module}/../../../app")
    dockerfile = "Dockerfile"
  }
}

resource "docker_container" "web" {
  count = var.replicas

  name     = "${var.environment}_web_${count.index + 1}"
  image    = docker_image.web.image_id
  hostname = "${var.environment}_web_${count.index + 1}"
  restart  = "unless-stopped"

  healthcheck {
    test         = ["CMD", "node", "-e", "fetch('http://127.0.0.1:3000/health', { signal: AbortSignal.timeout(4000) }).then(response => process.exit(response.status === 200 ? 0 : 1)).catch(() => process.exit(1))"]
    interval     = "30s"
    timeout      = "5s"
    retries      = 3
    start_period = "90s"
  }

  env = [
    for key, value in var.env_vars : "${key}=${value}"
  ]

  dynamic "networks_advanced" {
    for_each = var.networks
    content {
      name = networks_advanced.value
    }
  }
}