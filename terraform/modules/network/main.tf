resource "docker_network" "frontend" {
  name = "${var.environment}_frontend"
}

resource "docker_network" "backend" {
  name     = "${var.environment}_backend"
  internal = true
}

resource "docker_network" "monitoring" {
  name     = "${var.environment}_monitoring"
  internal = true
}

# Política de acceso desde el host: no se conectan los servicios a una red
# compartida abierta; se crean redes puente dedicadas para los contenedores que
# necesitan publicar un puerto.

# La pertenencia a cada red delimita qué servicios
# tienen ese camino de conectividad. El bind de cada puerto a 127.0.0.1 limita
# el acceso al propio host; esta red no identifica ni autoriza equipos concretos.
resource "docker_network" "host_storage" {
  name     = "${var.environment}_host_storage"
  internal = false
  options = {
    # Desactiva el NAT de salida de esta red; no controla el acceso entrante
    # desde el host ni sustituye el bind de puertos a 127.0.0.1.
    "com.docker.network.bridge.enable_ip_masquerade" = "false"
  }
}

resource "docker_network" "host_monitoring" {
  name     = "${var.environment}_host_monitoring"
  internal = false

  options = {
    "com.docker.network.bridge.enable_ip_masquerade" = "false"
  }
}
