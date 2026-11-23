resource "docker_network" "frontend" {
  name   = "${var.environment}_frontend"
}

resource "docker_network" "backend" {
  name     = "${var.environment}_backend"
  internal = true
}

resource "docker_network" "monitoring" {
  name     = "${var.environment}_monitoring"
  internal = true
}
