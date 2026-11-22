resource "docker_image" "nginx" {
  name = var.image
}

resource "local_file" "nginx_config" {
  filename             = abspath("${path.root}/generated/nginx.conf")
  file_permission      = "0644"
  directory_permission = "0755"
  content              = <<-EOF
    upstream streamforge {
      ${join("\n", [for container in var.web_containers : "server ${container}:3000;"])}
    }

    server {
      listen 80;

      location / {
        proxy_pass http://streamforge;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
      }
    }
  EOF
}

resource "docker_container" "nginx" {
  name  = "${var.environment}_load_balancer"
  image = docker_image.nginx.image_id

  healthcheck {
    test         = ["CMD", "/usr/bin/curl", "-fsS", "-o", "/dev/null", "http://127.0.0.1/health"]
    interval     = "15s"
    timeout      = "5s"
    retries      = 3
    start_period = "90s"
  }

  ports {
    external = var.external_port
    internal = 80
  }

  networks_advanced {
    name = var.network
  }

  mounts {
    type   = "bind"
    source = local_file.nginx_config.filename
    target = "/etc/nginx/conf.d/default.conf"
  }
}
