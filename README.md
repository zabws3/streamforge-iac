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

Prometheus and Alertmanager are not published on host ports. Inspect targets
and firing alerts from inside the Prometheus container, and inspect
Alertmanager's API inside its container:

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

Telegram delivery cannot be tested until real local bot credentials are
configured and the infrastructure is applied. No real service needs to be
stopped for the manual notification test.

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
