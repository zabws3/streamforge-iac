resource "docker_image" "web" {
  name = var.image

  build {
    context    = "../../app"
    dockerfile = "Dockerfile"
  }
}

resource "docker_container" "web" {
  count = var.replicas

  name  = "${var.environment}_web_${count.index + 1}"
  image = docker_image.web.image_id

  env = [
    for key, value in var.env_vars : "${key}=${value}"
  ]

  networks_advanced {
    name = var.networks[0]
  }

  networks_advanced {
    name = var.networks[1]
  }

  ports {
    internal = var.internal_port
  }
}