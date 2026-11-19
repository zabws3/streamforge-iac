resource "docker_network" "frontend" {
  name   = "${var.environment}_frontend"
  driver = "bridge"
}

resource "docker_network" "backend" {
  name     = "${var.environment}_backend"
  driver   = "bridge"
  internal = true
}

resource "docker_network" "monitoring" {
  name     = "${var.environment}_monitoring"
  driver   = "bridge"
  internal = true
}
