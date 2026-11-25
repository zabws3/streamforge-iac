# StreamForge P2 interactive demo

Run `./demo.sh` from any working directory; the script resolves the repository
root from its own path. It requires Bash, Docker CLI/daemon, `curl`, and Python
3. There are no additional package dependencies. The demo is fixed to PRO:
all runtime checks, HTTP requests, evidence collection, Terraform validation,
and optional state-changing tests target only the PRO environment. It has no
DEV selector or environment override.

The demo is read-only by default. It never runs Terraform apply/destroy, removes
containers or volumes, or prints container environment variables. The following
operations explicitly request confirmation:

- Stopping and restarting one existing PRO Web replica for failover.
- A bounded HTTP load test (the high profile has an extra confirmation).
- Creating and dropping a unique temporary MySQL table and restarting only
  `pro_database`. This requires two confirmations.
- Sending a synthetic firing/resolved Alertmanager event to the configured
  Telegram receiver; this may send two real Telegram messages.
- Running a Terraform plan.

Ctrl+C and normal exit attempt to restore a Web replica stopped by the demo and
drop a temporary persistence table. No table is dropped unless its unique name
was created by the current demo run. Do not kill the host or Docker daemon
mid-test; if interrupted externally, use the displayed container/table name to
check recovery manually. Never run this against a shared production deployment.

## Menu-to-requirement map

| Requirement | Menu option | What it actually checks |
|---|---:|---|
| Infrastructure/runtime inventory | 1 | Docker container states/health, published ports, MySQL/MinIO volumes, Terraform state resource addresses |
| Web load balancing | 2 | Repeated real requests to `/instance`; prints observed replica counts |
| Replica failover/recovery and alert | 3 | Checks the specific Prometheus Web alert is initially inactive, temporarily stops one PRO replica, waits for `WebInstanceUnreachable` to fire, probes the LB, restores the replica, and checks that the alert resolves |
| Controlled traffic/load | 4 | Bounded real HTTP requests; status distribution, latency, p95 and instance counts |
| MySQL persistence | 5 | Isolated unique test table/row, named volume check, database restart, read-after-restart, table cleanup |
| P1/P2 healthcheck comparison | 6 | Prints settings verified in each source tree and checks live app/Container health |
| Metrics/monitoring | 7 | Prometheus health, active targets and metric names discovered through its API; links Grafana/dashboard |
| Centralized logs | 8 | Alloy container, Loki readiness/labels and recent entries via Loki API; does not print raw log bodies |
| Alerts/Telegram | 9 | Prometheus rule API and Alertmanager API; optional confirmed synthetic firing/resolved test |
| MinIO/shared storage | 10 | MinIO readiness, actual volume and read-only listing of the configured buckets |
| Docker network policy | 11 | Runtime network `Internal` flag, connected containers and published ports |
| Terraform PRO | 12 | PRO topology, validate, read-only PRO plan, and allowlisted PRO URL outputs |
| General validation | 13 | Read-only Docker and endpoint checks; summary reflects only executed checks |
| Demo evidence | 14 | Timestamped safe subset of runtime inventory, endpoints, volumes and Prometheus targets |

## Audit findings that shape the demo

- The P2 app implements `/health` using `SELECT 1` and checks Redis only when
  `REDIS_HOST` is configured. It returns JSON fields `status`, `database`, and
  `cache`. `/instance` returns the process hostname. The actual HTTP body is
  shown; an HTTP 200 is not treated as proof that Redis is healthy.
- P2's Web Docker healthcheck uses Node `fetch` on `/health`, interval 30s,
  timeout 5s, 3 retries, and 90s start period. MySQL health checks run
  `SELECT 1`, interval 10s, timeout 5s, 6 retries and 60s start period.
  Nginx's Docker healthcheck probes `/health`; MinIO checks its readiness URL.
- The sibling P1 project is at `../../PRACTICA1` from this repository
  (the literal `../PRACTICA1` path in the supplied prompt does not exist).
  P1's Compose Web check uses `wget --spider /health`, 10s/5s/5 retries;
  MySQL uses `mysqladmin ping`; PRO Redis uses `redis-cli ping`. P1 uses named
  MySQL volumes `dev_db_data` and `prod_db_data`. P2 uses
  `${environment}_mysql_data` on `/var/lib/mysql`.
- P2 Web `docker_container` resources use fixed Terraform-managed replica
  names, and the Nginx upstream is rendered from a fixed list. Adding an
  unmanaged extra container would not update the upstream and would create
  drift. Option 3 therefore demonstrates failure/recovery of one managed
  replica instead of adding an unmanaged replica. Option 3 always runs against
  the isolated PRO lab environment because only PRO deploys alerting; it waits
  for the configured alert's actual `for` duration and restores the container
  even when the expected alert does not fire. Once firing is observed it holds
  the replica down through Alertmanager's initial `group_wait`, then waits for
  the Prometheus alert to resolve and Alertmanager's `group_interval`.
- During the audit, PRO's `WebContainerMissing` alert was already firing for
  all replicas while Docker reported them healthy. The failover demo checks
  the per-target `WebInstanceUnreachable` rule instead, and refuses to proceed
  if that selected replica's alert is already active. This avoids claiming the
  test caused a pre-existing alert.
- MinIO uses `streamforge-manifests` and `streamforge-chunks`; media objects
  are listed read-only. Streaming routes require a logged-in session, so the
  demo does not invent an authenticated playback request.
- Alloy discovers Docker logs and forwards to Loki. The current pipeline exposes
  the Loki `service_name` label; the dashboard uses `unknown_service`, so the
  logs option reports discovered labels and counts without exposing log
  contents. App stream logging occurs in the authenticated DASH route.
- Prometheus, Grafana and MinIO interfaces are bound to loopback in Terraform;
  their environment ports are detected from the current root configuration.
  The application Load Balancer is bound on all interfaces in the current
  setup.
- Alertmanager/rules/Telegram are PRO-only. A synthetic Alertmanager API event
  verifies API acceptance, not receipt by Telegram. The user must confirm the
  two messages in the configured chat. Bot tokens are never read from tfvars or
  printed.
- No P2 assignment PDF was present in the repository at audit time; the
  supplied demo specification is used as the requirement checklist.

## Operation notes

- The runtime demo is pinned to the PRO root: it expects three Web replicas,
  Redis, and Alertmanager and never targets DEV containers or endpoints.
- Some services do not publish host ports. The menu uses container inspection
  and the Prometheus/Loki container IPs for their internal APIs.
- `/api/videos` is a public read-only route, but the live catalogue may be empty.
- Evidence is stored under `demo-evidence/<environment>-<timestamp>/`, with
  restrictive local permissions. Files contain no env vars, complete logs,
  passwords, tokens, cookies, or database rows.
- To review the Terraform plan, select option 12 and choose plan. It uses
  `-refresh=false` and does not save a plan file. Apply and destroy are never
  offered by the tool.

## Before the presentation

1. Deploy PRO yourself and confirm every expected container is healthy.
2. Verify local `*.tfvars` files contain valid values, but do not share them.
3. Verify PRO Telegram messages by choosing option 9, then option 1, and
   confirming that you receive the firing and recovery notifications.
4. Run options 1, 2, 6, 7, 8, 10 and 11 before presenting; actions 3, 4, 5 and
   Telegram notification testing have explicit impact/confirmation prompts.
5. These actions are intended only for the local academic PRO lab, never a
   shared or real production environment.
