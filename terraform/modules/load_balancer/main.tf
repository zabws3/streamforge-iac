resource "docker_image" "haproxy" {
  name = var.image
}

resource "local_file" "haproxy_config" {
  filename             = abspath("${path.root}/generated/haproxy.cfg")
  file_permission      = "0644"
  directory_permission = "0755"
  content              = <<-EOF
    global
      log stdout format raw local0
      maxconn 2048

    defaults
      log global
      mode http
      option httplog
      timeout connect 3s
      timeout client 60s
      timeout server 60s
      retries 2
      retry-on conn-failure empty-response response-timeout 502 503 504
      option redispatch

    resolvers docker
      nameserver docker 127.0.0.11:53
      resolve_retries 3
      timeout resolve 1s
      timeout retry 1s
      hold valid 10s

    frontend streamforge_frontend
      bind :80
      default_backend streamforge_web
      http-request set-header X-Real-IP %[src]

    backend streamforge_web
      option httpchk
      http-check send meth GET uri /health ver HTTP/1.1 hdr Host localhost
      http-check expect status 200
      stick-table type string len 128 size 100k expire 8h
      stick on req.cook(streamforge.sid)
      stick store-response res.cook(streamforge.sid)
    ${join("\n", [for container in var.web_containers : "  server ${container} ${container}:3000 check inter 2s fall 2 rise 2 resolvers docker init-addr libc,none"])}
  EOF
}

resource "docker_container" "haproxy" {
  name  = "${var.environment}_load_balancer"
  image = docker_image.haproxy.image_id

  healthcheck {
    test         = ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1/health"]
    interval     = "15s"
    timeout      = "5s"
    retries      = 3
    start_period = "90s"
  }

  ports {
    external = var.external_port
    internal = 80
  }

  dynamic "networks_advanced" {
    for_each = var.networks
    content {
      name = networks_advanced.value
    }
  }

  mounts {
    type   = "bind"
    source = local_file.haproxy_config.filename
    target = "/usr/local/etc/haproxy/haproxy.cfg"
  }

  lifecycle {
    replace_triggered_by = [local_file.haproxy_config]
  }
}
