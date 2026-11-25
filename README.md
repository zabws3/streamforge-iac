# StreamForge - Infrastructure as Code

Infrastructure as Code project developed using Terraform
and Docker.

## Overview

The objective of this project is to deploy and manage
a multi-environment web infrastructure using Terraform.

The infrastructure will include:

- Web application
- PostgreSQL database
- Redis cache
- Load Balancer
- Monitoring and centralized logging
- Shared file storage

## Environments

- Development (DEV)
- Production (PRO)

## Technologies

- Terraform
- Docker
- Python / Flask
- PostgreSQL
- Redis
- Nginx
- Prometheus
- Grafana
- Alertmanager
- Blackbox Exporter
- Node Exporter
- MinIO

## Project Status

Initial project setup.

## Media storage

The MinIO container mounts the repository's `media/` directory read-only.
At startup it enables versioning on `streamforge-manifests` and
`streamforge-chunks`, then uploads `.mpd` files and `.m4s` segments while
preserving their relative paths. Existing objects are left untouched.

The web application retrieves manifests and segments from their respective
private buckets, so the manifest's relative segment URLs continue to work
through `/video/stream/`.

## Prometheus alerts and Telegram

Monitoring uses the existing Prometheus and cAdvisor, with Blackbox Exporter
for direct HTTP/TCP availability probes and Node Exporter for host filesystem
metrics (which cAdvisor does not expose in this deployment). Alertmanager
groups and deduplicates notifications and sends both firing and resolved
alerts to Telegram. No Docker Compose file is used; Terraform manages these
containers.

### Configure Telegram

1. In Telegram, message `@BotFather`, run `/newbot`, and copy the bot token.
2. Start a chat with the bot and send it a message. For a private chat, obtain
   the chat ID by opening `https://api.telegram.org/bot<TOKEN>/getUpdates`
   and reading `message.chat.id`. Do not publish the token or URL.
3. Copy `.env.example` to `.env` and set `TELEGRAM_BOT_TOKEN` and
   `TELEGRAM_CHAT_ID`. Keep `.env` local and private.
4. Export the Terraform input names before running Terraform:

   ```sh
   set -a
   . ./.env
   set +a
   export TF_VAR_telegram_bot_token="$TELEGRAM_BOT_TOKEN"
   export TF_VAR_telegram_chat_id="$TELEGRAM_CHAT_ID"
   ```

The variables are passed to Alertmanager only at container runtime. Its
entrypoint writes the bot token to a mode-0600 file in container `tmpfs`;
Alertmanager reads it with `telegram_bot_token_file`. The token is not written
to the generated configuration, dashboard, or logs. Protect Terraform state
and Docker access as secrets because Terraform records container environment
variables in state and Docker administrators can inspect container settings.

### Alert thresholds

The DEV defaults are:

| Alert | Threshold | Sustained for |
|---|---:|---:|
| Container CPU warning / critical | 80% / 95% of total host CPU capacity | 10m / 5m |
| Container RAM warning / critical | 85% / 95% of host RAM for one container | 10m / 5m |
| Host root disk warning / critical | 85% / 95% used | 5m / 2m |

Change the Terraform inputs `alert_cpu_warning_threshold`,
`alert_cpu_critical_threshold`, `alert_memory_warning_threshold`,
`alert_memory_critical_threshold`, `alert_disk_warning_threshold`, and
`alert_disk_critical_threshold` in a local tfvars file or with `-var`.
Thresholds are percentages from 0 to 100. Service availability alerts wait
2 minutes (the all-Web-down alert waits 1 minute); Alertmanager groups for
30 seconds, groups updates every minute, and repeats after 4 hours.

### Review and deploy

From the repository root, initialize/validate and review the plan. Do not
apply until the plan is understood:

```sh
terraform -chdir=terraform/environments/dev init
terraform -chdir=terraform/environments/dev fmt -check
terraform -chdir=terraform/environments/dev validate
terraform -chdir=terraform/environments/dev plan -var-file=dev.tfvars
```

The monitoring module requires the two `TF_VAR_telegram_*` inputs above. An
apply adds Alertmanager, Blackbox Exporter, and Node Exporter, updates
Prometheus configuration/rules, and updates the Grafana dashboard. Alertmanager
uses the frontend network for outbound Telegram API access; the exporters are
not published on host ports. No service is stopped intentionally, but
Prometheus will need to be recreated by Terraform to load its new scrape and
alert rules.

### Check and test

After you apply the reviewed plan:

```sh
docker ps --filter name=dev_alertmanager
docker ps --filter name=dev_blackbox_exporter
docker ps --filter name=dev_node_exporter
docker exec dev_prometheus promtool check config /etc/prometheus/prometheus.yml
docker exec dev_prometheus promtool check rules /etc/prometheus/alert.rules.yml
```

Alertmanager is not published on a host port. Prometheus is bound to
`127.0.0.1:9090` for local administration. Inspect targets and firing alerts
from inside the Prometheus container, and inspect Alertmanager's API inside
its container:

```sh
docker exec dev_prometheus wget -qO- http://127.0.0.1:9090/api/v1/targets
docker exec dev_prometheus wget -qO- http://127.0.0.1:9090/api/v1/alerts
docker exec dev_alertmanager wget -qO- http://127.0.0.1:9093/api/v2/alerts
```

Confirm `blackbox`, `blackbox_exporter`, `node_exporter`, and `cadvisor` targets
are healthy. Grafana's existing StreamForge dashboard adds current firing
alerts, available Web replica count, and host root disk usage.

To send a controlled firing notification without stopping a real service,
POST a temporary alert to Alertmanager's API from inside its container, wait
for the configured 30-second group wait, then POST the same labels with an
`endsAt` in the past. Allow at least 70 seconds after the first POST for the
grouped recovery notification:

```sh
START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
END=$(date -u -d '+10 minutes' +%Y-%m-%dT%H:%M:%SZ)
send_test_alert() {
  local ends_at="$1"
  local payload
  payload=$(printf '[{"labels":{"alertname":"StreamForgeTelegramTest","severity":"warning","service":"telegram-test","container":"manual"},"annotations":{"description":"Manual notification test","action":"No action required."},"startsAt":"%s","endsAt":"%s"}]' "$START" "$ends_at")
  docker exec -e TEST_ALERT_PAYLOAD="$payload" dev_alertmanager \
    /bin/sh -c 'wget -qO- --header="Content-Type: application/json" --post-data="$TEST_ALERT_PAYLOAD" http://127.0.0.1:9093/api/v2/alerts'
}
send_test_alert "$END"
sleep 70
send_test_alert "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

The notification test requires valid Telegram credentials and an applied
Alertmanager configuration. No real service needs to be stopped for this
manual test.

### Monitoring container hardening

Monitoring configuration files and host bind mounts are mounted read-only.
Prometheus, Grafana, Loki, Alertmanager, Alloy, cAdvisor, Node Exporter, and
Blackbox Exporter use a read-only container root filesystem, drop Linux
capabilities, and enable `no-new-privileges`. Writable service state is kept
in named Docker volumes; short-lived runtime files use `tmpfs`.

cAdvisor is no longer privileged and no longer receives the host root,
Docker data directory, `/var/run` directory, or device tree. It receives
only `/sys` plus the Docker and containerd sockets as read-only mounts, and
collects the CPU, memory, network, and health metrics used by the alerts.
The sockets still expose powerful APIs: a read-only socket mount does not
make Docker/containerd API calls read-only. cAdvisor therefore has no host
port and remains on the internal monitoring network. Alloy does not mount
the Docker socket; it talks to a dedicated internal socket proxy that only
allows container/network reads and log retrieval, with API writes disabled.
The proxy itself has the socket mounted read-only and has no published port.

These settings require Terraform to recreate the affected monitoring
containers when applied. Named Prometheus, Grafana, Alloy, Loki, and
Alertmanager volumes preserve data across later container replacements. On
the first rollout, existing Prometheus/Grafana/Alloy data currently stored in
container writable layers is not copied automatically into the new volumes;
historical metrics, UI state, and Alloy read positions may reset unless you
back them up or migrate them first. Review the environment plan before
applying.

Check bucket versioning and uploaded objects with:

```sh
docker exec dev_minio mc version info streamforge/streamforge-manifests
docker exec dev_minio mc version info streamforge/streamforge-chunks
docker exec dev_minio mc find streamforge/streamforge-manifests
docker exec dev_minio mc find streamforge/streamforge-chunks
```

### Upload a DASH video manually

Install the app dependencies on the host if they are not already installed,
then pass the local video folder to the uploader:

```sh
npm ci --prefix app
./app/scripts/upload-video.js /path/to/VideoFolder
```

The folder must contain `manifest.mpd` and at least one `.m4s` file. The
uploader stores them under `VideoFolder/` in their respective buckets and
verifies each uploaded object's size. It uses `MINIO_ENDPOINT` when set (or
`http://127.0.0.1:9000` by default) and reads credentials from
`MINIO_ACCESS_KEY`/`MINIO_SECRET_KEY` or the running `dev_minio` container.

Verify the uploaded keys with:

```sh
docker exec dev_minio mc find streamforge/streamforge-manifests/VideoFolder
docker exec dev_minio mc find streamforge/streamforge-chunks/VideoFolder
```

### Register a stored video in the catalog

In the admin panel, choose **Añadir vídeo** and select an unregistered
manifest from **Vídeo almacenado en MinIO**. The video title and MPD path are
filled from its storage prefix; complete the duration and any optional
description, thumbnail, and category before saving. The backend keeps MinIO
private and streams the manifest and `.m4s` objects through the authenticated
`/video/stream/` route.

## Network Security Policy

StreamForge uses three Docker bridge networks to limit which containers can
communicate:

| Network | Purpose and members |
|---|---|
| `dev_frontend` | Application ingress: Nginx Load Balancer, Web replicas, and Alertmanager for outbound Telegram notifications. |
| `dev_backend` | Private application data: Web replicas, MySQL, Redis, and MinIO. The network is marked `internal`. |
| `dev_monitoring` | Private observability: Prometheus, Grafana, Loki, Alloy, cAdvisor, Node Exporter, and Alertmanager. The network is marked `internal`. |

Web replicas join both frontend and backend so Nginx can reach the application
and the application can reach its data services. MySQL and Redis are only on
the internal backend network. MinIO is also only on the backend network; Web
and the Blackbox Exporter can reach it there. Grafana is only on monitoring
and queries Prometheus and Loki over that network. Alertmanager joins frontend
for Telegram egress and monitoring to receive alerts. Blackbox Exporter joins
the networks needed to probe the load balancer, Web, and backend services; it
does not publish its exporter port.

Only the Nginx Load Balancer is exposed on all host interfaces, at port 8081
in DEV or 8082 in PRO, as the application entry point. Web containers do not
publish their own ports. MinIO, Grafana, and Prometheus bind to `127.0.0.1`
only: DEV uses `9000`/`9001`, `3001`, and `9090`; PRO uses `9100`/`9101`,
`3002`, and `9091`, respectively. MySQL, Redis, Alertmanager, Loki, Alloy,
cAdvisor, Node Exporter, and Blackbox Exporter have no published host ports.
Internal scrapes and Grafana's Prometheus connection use Docker DNS and
container ports, so they do not depend on host port publishing.

For a cloud deployment, expose the application through a public Load Balancer
or an ingress Security Group (prefer HTTPS/443 in production). Allow backend
ports only from the Web service's Security Group; allow Prometheus, Loki, and
exporter ports only from the monitoring Security Group, and Grafana access
only from an administrator's trusted network. Keep MySQL, Redis, and MinIO
without public ingress. Use Network ACLs or firewall rules as an additional
subnet-level boundary, including the required return traffic, and restrict
outbound access to required destinations such as Telegram. Docker network
segmentation on one host is a development analogue, not a replacement for
cloud Security Groups or host security controls.

## Production-like PRO environment

The PRO Terraform root is isolated under `terraform/environments/pro`, so it
has its own local state and can run alongside DEV on the same Docker host. It
deploys the database, Redis, MinIO, three Web replicas, Nginx Load Balancer,
Prometheus, Alertmanager, Grafana, Loki, Alloy, cAdvisor, Blackbox Exporter,
and Node Exporter. The Web replicas use Docker's `unless-stopped` restart
policy; Nginx distributes requests across all three upstreams and retries
another upstream after connection errors/timeouts or 502/503/504 responses.
The UI polls `/instance` and shows which Web container answered.

Redis is enabled in PRO for shared login sessions across replicas. DEV has no
Redis container or Redis probe; the app runs without a cache there and reports
that cache as disabled. Each environment has separate Docker networks,
containers, and named database/storage/monitoring volumes. PRO host ports are
chosen to avoid collisions with DEV as listed in the Network Security Policy.

Configure local secrets and review the plan before deploying:

```sh
cp terraform/environments/pro/pro.tfvars.example \
  terraform/environments/pro/pro.tfvars
# Replace every placeholder with unique, strong values and valid Telegram credentials.
terraform -chdir=terraform/environments/pro init
terraform -chdir=terraform/environments/pro fmt -check
terraform -chdir=terraform/environments/pro validate
terraform -chdir=terraform/environments/pro plan -var-file=pro.tfvars
```

`pro.tfvars` is ignored by Git. Apply only after reviewing the plan:

```sh
terraform -chdir=terraform/environments/pro apply -var-file=pro.tfvars
```

After deployment, visit `http://localhost:8082`; the instance indicator should
change among `pro_web_1`, `pro_web_2`, and `pro_web_3` as it polls. Grafana is
at `http://127.0.0.1:3002`, Prometheus at `http://127.0.0.1:9091`, and the
MinIO console at `http://127.0.0.1:9101`. Use the Grafana admin password from
`pro.tfvars`.

To demonstrate Telegram firing and resolved notifications without stopping a
service, POST a synthetic alert to PRO's Alertmanager (the configured Telegram
chat must be valid):

```sh
START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
END=$(date -u -d '+10 minutes' +%Y-%m-%dT%H:%M:%SZ)
send_pro_test_alert() {
  local ends_at="$1"
  local payload
  payload=$(printf '[{"labels":{"alertname":"StreamForgeProDemo","severity":"warning","service":"demo","container":"manual"},"annotations":{"description":"Synthetic PRO demo alert","action":"No action required."},"startsAt":"%s","endsAt":"%s"}]' "$START" "$ends_at")
  docker exec -e TEST_ALERT_PAYLOAD="$payload" pro_alertmanager \
    sh -c 'wget -qO- --header="Content-Type: application/json" --post-data="$TEST_ALERT_PAYLOAD" http://127.0.0.1:9093/api/v2/alerts'
}
send_pro_test_alert "$END"
sleep 70
send_pro_test_alert "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

This tests Alertmanager-to-Telegram firing/resolved delivery without causing
an outage. It is a single-host educational simulation, not production-grade
high availability: Docker restart policies and three replicas do not protect
against host, database, Redis, or storage failure. The project also has no
TLS termination, so PRO cookies are configured for the current HTTP demo.
For a real production deployment, use HTTPS at a cloud load balancer and set
secure cookies, spread replicas across failure zones, and provide appropriate
HA/backup for stateful services.
