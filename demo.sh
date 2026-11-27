#!/usr/bin/env bash

set -Eeuo pipefail

readonly PRO_URL="http://localhost:8082"
readonly PRO_WEB="pro_web_1"
readonly PRO_WEB_PEERS=("pro_web_2" "pro_web_3")
readonly PRO_LB="pro_load_balancer"
readonly PRO_PROMETHEUS="pro_prometheus"
readonly PRO_ALERTMANAGER="pro_alertmanager"
readonly DEV_DB="dev_database"
readonly DEV_VOLUME="dev_mysql_data"

web_restore_needed=0
db_restore_needed=0
demo_table=""
demo_marker=""
pro_demo_active=0
pro_demo_summary_printed=0
pro_demo_failed=0
pro_demo_initial_healthy=0
pro_demo_initial_distribution=0
pro_demo_stopped=0
pro_demo_failover=0
pro_demo_alert_fired=0
pro_demo_alertmanager_received=0
pro_demo_telegram_confirmed=0
pro_demo_recovery_healthy=0
pro_demo_post_lb_operational=0
pro_demo_web_back_in_rotation=0
pro_demo_alert_state="not checked"
pro_demo_outage_status="not stopped"
pro_demo_stop_started=0
pro_demo_downtime=0
pro_demo_initial_http_errors=0
pro_demo_initial_violations=0
pro_demo_failover_http_errors=0
pro_demo_failover_violations=0
pro_demo_post_http_errors=0
pro_demo_post_violations=0
pro_demo_telegram_delta=0
pro_demo_telegram_failures=0
declare -A pro_demo_initial_counts=()
declare -A pro_demo_failover_counts=()
declare -A pro_demo_post_counts=()

info() { printf '[INFO] %s\n' "$*"; }
pass() { printf '[OK] %s\n' "$*"; }
warn() { printf '[AVISO] %s\n' "$*" >&2; }
fail() { printf '[ERROR] %s\n' "$*" >&2; }

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        fail "No se encuentra el comando requerido: $1"
        return 1
    fi
}

require_docker() {
    require_command docker
    if ! docker info >/dev/null 2>&1; then
        fail "Docker no está disponible. Comprueba que el daemon esté iniciado y accesible."
        return 1
    fi
}

pause_enter() {
    printf '\n%s\n' "$1"
    printf 'Pulsa ENTER para continuar... '
    read -r _
}

confirm() {
    local answer
    printf '%s\n' "$1"
    printf 'Escribe S para continuar: '
    read -r answer
    [[ "$answer" == "S" || "$answer" == "s" ]]
}

container_state() {
    docker inspect --format '{{.State.Status}}|{{.RestartCount}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}sin-healthcheck{{end}}' "$1" 2>/dev/null
}

wait_for_healthy() {
    local container="$1"
    local timeout="$2"
    local deadline=$((SECONDS + timeout))
    local state

    while (( SECONDS < deadline )); do
        if ! state="$(container_state "$container")"; then
            sleep 2
            continue
        fi
        if [[ "$state" == "running|"*"|healthy" ]]; then
            return 0
        fi
        sleep 2
    done

    fail "$container no llegó al estado healthy en ${timeout}s. Último estado: ${state:-desconocido}"
    return 1
}

check_running_healthy() {
    local container="$1"
    local state

    if ! state="$(container_state "$container")"; then
        fail "No existe el contenedor esperado: $container"
        return 1
    fi
    if [[ "$state" != "running|"*"|healthy" ]]; then
        fail "$container debe estar running/healthy; estado actual: $state"
        return 1
    fi
}

get_instance() {
    local url="$1"
    curl --fail --silent --show-error --max-time 5 "$url/instance" |
        python3 -c 'import json,sys; print(json.load(sys.stdin)["instance"])'
}

prometheus_web_container_alert_state() {
    docker exec "$PRO_PROMETHEUS" wget -qO- http://127.0.0.1:9090/api/v1/rules |
        python3 -c '
import json,sys
container=sys.argv[1]
groups=json.load(sys.stdin).get("data",{}).get("groups",[])
rules=[
    rule for group in groups for rule in group.get("rules",[])
    if rule.get("name") == "WebContainerMissing"
    and rule.get("labels",{}).get("container") == container
]
if len(rules) != 1:
    raise SystemExit(f"Expected one WebContainerMissing rule for {container}; found {len(rules)}")
print(rules[0].get("state","unknown"))
' "$PRO_WEB"
}

alertmanager_telegram_counts() {
    docker exec "$PRO_ALERTMANAGER" wget -qO- http://127.0.0.1:9093/metrics |
        python3 -c '
import sys
total=failed=0
seen_total=False
for line in sys.stdin:
    if line.startswith("#") or "{" not in line:
        continue
    name, remainder=line.split("{",1)
    if name not in ("alertmanager_notifications_total","alertmanager_notifications_failed_total"):
        continue
    labels=remainder.split("}",1)[0]
    if '\''integration="telegram"'\'' not in labels:
        continue
    value=int(float(line.rsplit(None,1)[-1]))
    if name == "alertmanager_notifications_total":
        total += value
        seen_total=True
    else:
        failed += value
if not seen_total:
    raise SystemExit("No Telegram notification counters found")
print(f"{total}|{failed}")
'
}

alertmanager_active_alert_count() {
    docker exec "$PRO_ALERTMANAGER" wget -qO- http://127.0.0.1:9093/api/v2/alerts |
        python3 -c 'import json,sys; print(len(json.load(sys.stdin)))'
}

alertmanager_has_web_alert() {
    docker exec "$PRO_ALERTMANAGER" wget -qO- http://127.0.0.1:9093/api/v2/alerts |
        python3 -c '
import json,sys
container=sys.argv[1]
alerts=json.load(sys.stdin)
found=any(
    alert.get("labels",{}).get("alertname") == "WebContainerMissing"
    and alert.get("labels",{}).get("container") == container
    for alert in alerts
)
raise SystemExit(0 if found else 1)
' "$PRO_WEB"
}

alertmanager_can_resolve_telegram() {
    docker exec "$PRO_ALERTMANAGER" busybox nslookup -type=A api.telegram.org >/dev/null 2>&1
}

web_container_alert_is_inactive() {
    local state
    if ! state="$(prometheus_web_container_alert_state)"; then
        fail "No se pudo consultar la alerta WebContainerMissing en Prometheus."
        return 1
    fi
    [[ "$state" == "inactive" ]]
}

wait_for_web_container_alert_inactive() {
    local timeout="$1"
    local deadline=$((SECONDS + timeout))
    local state
    while (( SECONDS < deadline )); do
        if ! state="$(prometheus_web_container_alert_state)"; then
            fail "No se pudo consultar la alerta WebContainerMissing en Prometheus."
            return 1
        fi
        if [[ "$state" == "inactive" ]]; then
            return 0
        fi
        sleep 5
    done
    fail "WebContainerMissing para $PRO_WEB no volvió a inactive."
    return 1
}

sample_lb_requests() {
    local phase="$1"
    local requests="$2"
    local counts_name="$3"
    local errors_name="$4"
    local violations_name="$5"
    local forbidden_instance="${6:-}"
    local instance
    local -n counts_ref="$counts_name"
    local -n errors_ref="$errors_name"
    local -n violations_ref="$violations_name"

    counts_ref["$PRO_WEB"]=0
    counts_ref["${PRO_WEB_PEERS[0]}"]=0
    counts_ref["${PRO_WEB_PEERS[1]}"]=0
    counts_ref[unexpected]=0
    errors_ref=0
    violations_ref=0

    local request
    for ((request = 1; request <= requests; request++)); do
        if instance="$(get_instance "$PRO_URL" 2>/dev/null)"; then
            case "$instance" in
                "$PRO_WEB"|"${PRO_WEB_PEERS[0]}"|"${PRO_WEB_PEERS[1]}")
                    counts_ref["$instance"]=$(( ${counts_ref["$instance"]:-0} + 1 ))
                    ;;
                *)
                    counts_ref[unexpected]=$(( ${counts_ref[unexpected]:-0} + 1 ))
                    ;;
            esac
            printf '[%s] Request %02d -> %s\n' "$phase" "$request" "$instance"
            if [[ -n "$forbidden_instance" && "$instance" == "$forbidden_instance" ]]; then
                violations_ref=$((violations_ref + 1))
                fail "El Load Balancer devolvió la réplica no disponible $forbidden_instance."
            fi
        else
            errors_ref=$((errors_ref + 1))
            printf '[%s] Request %02d -> ERROR HTTP/JSON\n' "$phase" "$request"
        fi
        sleep 0.1
    done

    printf '[%s] Resumen:\n' "$phase"
    printf '  %s: %d\n' "$PRO_WEB" "${counts_ref[$PRO_WEB]}"
    printf '  %s: %d\n' "${PRO_WEB_PEERS[0]}" "${counts_ref[${PRO_WEB_PEERS[0]}]}"
    printf '  %s: %d\n' "${PRO_WEB_PEERS[1]}" "${counts_ref[${PRO_WEB_PEERS[1]}]}"
    if (( counts_ref[unexpected] > 0 )); then
        printf '  Réplicas inesperadas: %d\n' "${counts_ref[unexpected]}"
    fi
    printf '  Errores HTTP/JSON: %d\n' "$errors_ref"

    (( errors_ref == 0 && violations_ref == 0 && counts_ref[unexpected] == 0 ))
}

print_pro_demo_counts() {
    local label="$1"
    local counts_name="$2"
    local -n counts_ref="$counts_name"
    printf '%s: %s=%d, %s=%d, %s=%d, inesperadas=%d\n' \
        "$label" "$PRO_WEB" "${counts_ref[$PRO_WEB]:-0}" \
        "${PRO_WEB_PEERS[0]}" "${counts_ref[${PRO_WEB_PEERS[0]}]:-0}" \
        "${PRO_WEB_PEERS[1]}" "${counts_ref[${PRO_WEB_PEERS[1]}]:-0}" \
        "${counts_ref[unexpected]:-0}"
}

summary_result() {
    local verified="$1"
    local message="$2"
    if (( verified )); then
        pass "$message"
    else
        fail "$message"
    fi
}

print_pro_demo_summary() {
    (( pro_demo_active && !pro_demo_summary_printed )) || return 0
    pro_demo_summary_printed=1

    printf '\n===============================================\n'
    printf '           RESUMEN DEMO STREAMFORGE\n'
    printf '===============================================\n\n'
    summary_result "$pro_demo_initial_healthy" "Estado inicial: las tres Web estaban running/healthy."
    print_pro_demo_counts "Peticiones iniciales" pro_demo_initial_counts
    summary_result "$pro_demo_initial_distribution" "Distribución inicial del Load Balancer."
    summary_result "$pro_demo_stopped" "$PRO_WEB detenida correctamente."
    printf 'Estado de %s durante la caída: %s\n' "$PRO_WEB" "$pro_demo_outage_status"
    print_pro_demo_counts "Peticiones durante failover" pro_demo_failover_counts
    printf 'Errores HTTP iniciales/failover/post-recovery: %d/%d/%d\n' \
        "$pro_demo_initial_http_errors" "$pro_demo_failover_http_errors" "$pro_demo_post_http_errors"
    printf 'Respuestas indebidas de la réplica detenida: %d; respuestas indebidas post-recovery: %d\n' \
        "$pro_demo_failover_violations" "$pro_demo_post_violations"
    summary_result "$pro_demo_failover" "Failover atendido solo por las otras réplicas."
    summary_result "$pro_demo_alert_fired" "Prometheus: WebContainerMissing -> FIRING."
    summary_result "$pro_demo_alertmanager_received" "Alertmanager recibió la alerta de $PRO_WEB."
    summary_result "$pro_demo_telegram_confirmed" "Notificación Telegram confirmada (contador +$pro_demo_telegram_delta; fallos +$pro_demo_telegram_failures)."
    printf 'Estado final observado de la alerta: %s\n' "$pro_demo_alert_state"
    printf 'Tiempo que %s estuvo detenida: %ss\n' "$PRO_WEB" "$pro_demo_downtime"
    summary_result "$pro_demo_recovery_healthy" "Recovery: $PRO_WEB -> RUNNING / HEALTHY."
    summary_result "$pro_demo_post_lb_operational" "Load Balancer operativo después del recovery."
    print_pro_demo_counts "Peticiones posteriores al recovery" pro_demo_post_counts
    summary_result "$pro_demo_web_back_in_rotation" "$PRO_WEB volvió a recibir tráfico."

    if (( !pro_demo_failed &&
        pro_demo_initial_healthy &&
        pro_demo_initial_distribution &&
        pro_demo_stopped &&
        pro_demo_failover &&
        pro_demo_alert_fired &&
        pro_demo_alertmanager_received &&
        pro_demo_telegram_confirmed &&
        pro_demo_recovery_healthy &&
        pro_demo_post_lb_operational &&
        pro_demo_web_back_in_rotation )); then
        printf '\nDEMO COMPLETADA CORRECTAMENTE\n\n'
    else
        printf '\nDEMO INCOMPLETA: revisa los errores anteriores.\n\n'
    fi
}

restore_pro_web() {
    local state
    local container_status health attempt
    for ((attempt = 1; attempt <= 3; attempt++)); do
        if ! state="$(container_state "$PRO_WEB")"; then
            fail "No existe el contenedor que debe restaurarse: $PRO_WEB"
            return 1
        fi
        container_status="${state%%|*}"
        if [[ "$container_status" == "exited" || "$container_status" == "created" || "$container_status" == "dead" ]]; then
            warn "Restaurando $PRO_WEB..."
            if ! docker start "$PRO_WEB" >/dev/null; then
                warn "No se pudo iniciar $PRO_WEB en el intento $attempt; se volverá a comprobar su estado."
                sleep 2
                continue
            fi
            if ! state="$(container_state "$PRO_WEB")"; then
                warn "No se pudo volver a consultar el estado de $PRO_WEB tras iniciarlo."
                sleep 2
                continue
            fi
            container_status="${state%%|*}"
        fi
        if [[ "$container_status" != "running" && "$container_status" != "restarting" ]]; then
            fail "Estado no restaurable automáticamente para $PRO_WEB: $container_status"
            return 1
        fi
        info "$PRO_WEB -> $container_status"
        health="${state##*|}"
        if [[ "$container_status" == "running" && "$health" == "healthy" ]] ||
            wait_for_healthy "$PRO_WEB" 60; then
            info "$PRO_WEB -> healthy"
            if (( pro_demo_active && pro_demo_stop_started > 0 )); then
                pro_demo_downtime=$(( $(date +%s) - pro_demo_stop_started ))
                pro_demo_recovery_healthy=1
                pro_demo_stop_started=0
            fi
            web_restore_needed=0
            return 0
        fi
    done
    fail "$PRO_WEB no llegó a healthy después de tres intentos de recuperación."
    return 1
}

mysql_query() {
    local query="$1"
    docker exec "$DEV_DB" sh -eu -c \
        'export MYSQL_PWD="$MYSQL_PASSWORD"; exec mysql --protocol=TCP -h 127.0.0.1 -u "$MYSQL_USER" "$MYSQL_DATABASE" --batch --skip-column-names -e "$1"' \
        sh "$query"
}

cleanup() {
    local status=$?
    trap - EXIT INT TERM

    if (( web_restore_needed )); then
        if restore_pro_web; then
            pass "$PRO_WEB está healthy."
        else
            fail "No se pudo restaurar $PRO_WEB; comprueba el contenedor manualmente."
            status=1
        fi
    fi

    if (( db_restore_needed )); then
        local state
        if state="$(container_state "$DEV_DB")" && [[ "$state" != running\|* ]]; then
            warn "Restaurando $DEV_DB al salir..."
            if docker start "$DEV_DB" >/dev/null; then
                pass "$DEV_DB iniciado."
            else
                fail "No se pudo iniciar $DEV_DB; comprueba el contenedor manualmente."
                status=1
            fi
        fi
        if [[ -n "$demo_table" ]] && wait_for_healthy "$DEV_DB" 180; then
            if mysql_query "DROP TABLE IF EXISTS \`$demo_table\`;" >/dev/null; then
                info "Tabla temporal $demo_table eliminada; los datos de la aplicación no se modificaron."
            else
                warn "No se pudo borrar la tabla temporal $demo_table. Puedes eliminarla cuando MySQL esté disponible."
                status=1
            fi
        elif [[ -n "$demo_table" ]]; then
            warn "La tabla de prueba $demo_table sigue en el volumen $DEV_VOLUME porque MySQL no está healthy."
            status=1
        fi
    fi

    if (( pro_demo_active && !pro_demo_summary_printed )); then
        pro_demo_failed=1
        print_pro_demo_summary
    fi

    exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

demo_pro_recovery() {
    require_command curl
    require_command python3
    require_docker
    check_running_healthy "$PRO_WEB"
    for peer in "${PRO_WEB_PEERS[@]}"; do
        check_running_healthy "$peer"
    done
    check_running_healthy "$PRO_LB"
    check_running_healthy "$PRO_PROMETHEUS"
    check_running_healthy "$PRO_ALERTMANAGER"

    if ! web_container_alert_is_inactive; then
        fail "La regla WebContainerMissing para $PRO_WEB no está cargada/inactiva o no se pudo consultar."
        return 1
    fi
    printf '[ALERT] WebContainerMissing -> inactive\n'

    if ! alertmanager_can_resolve_telegram; then
        fail "Alertmanager no puede resolver api.telegram.org; se cancela antes de detener una réplica."
        return 1
    fi

    local active_alerts notification_before total_before failed_before
    if ! active_alerts="$(alertmanager_active_alert_count)"; then
        fail "No se pudo consultar la API de Alertmanager; se cancela antes de detener una réplica."
        return 1
    fi
    if [[ "$active_alerts" != "0" ]]; then
        fail "Alertmanager ya contiene $active_alerts alerta(s) activa(s); no se podrá atribuir con seguridad el envío Telegram a esta demo."
        return 1
    fi
    if ! notification_before="$(alertmanager_telegram_counts)"; then
        fail "No se pudieron leer los contadores Telegram de Alertmanager; se cancela antes de detener una réplica."
        return 1
    fi
    IFS='|' read -r total_before failed_before <<<"$notification_before"
    if [[ ! "$total_before" =~ ^[0-9]+$ || ! "$failed_before" =~ ^[0-9]+$ ]]; then
        fail "Alertmanager devolvió contadores Telegram inválidos."
        return 1
    fi

    if ! curl --fail --silent --show-error --max-time 5 "$PRO_URL/health" >/dev/null; then
        fail "El endpoint de healthcheck del Load Balancer no responde; se cancela antes de detener una réplica."
        return 1
    fi
    pass "Docker, las tres Web, Load Balancer, Prometheus y Alertmanager están operativos."

    if ! confirm "La demo enviará solicitudes reales a PRO y detendrá $PRO_WEB con docker stop --time 5 hasta confirmar WebContainerMissing y una notificación Telegram. La comprobación de FIRING/Telegram será manual con ENTER. Si la regla activa no dispara, se restaurará automáticamente y el resultado será incompleto. Solo continuar en PRO local/aislado, nunca en producción compartida."; then
        info "Prueba cancelada; no se modificó ningún contenedor."
        return 0
    fi

    pro_demo_active=1
    pro_demo_summary_printed=0
    pro_demo_failed=0
    pro_demo_initial_healthy=1
    pro_demo_initial_distribution=0
    pro_demo_stopped=0
    pro_demo_failover=0
    pro_demo_alert_fired=0
    pro_demo_alertmanager_received=0
    pro_demo_telegram_confirmed=0
    pro_demo_recovery_healthy=0
    pro_demo_post_lb_operational=0
    pro_demo_web_back_in_rotation=0
    pro_demo_alert_state="inactive"
    pro_demo_outage_status="not stopped"
    pro_demo_stop_started=0
    pro_demo_downtime=0
    pro_demo_initial_counts=()
    pro_demo_failover_counts=()
    pro_demo_post_counts=()
    pro_demo_initial_http_errors=0
    pro_demo_initial_violations=0
    pro_demo_failover_http_errors=0
    pro_demo_failover_violations=0
    pro_demo_post_http_errors=0
    pro_demo_post_violations=0
    pro_demo_telegram_delta=0
    pro_demo_telegram_failures=0

    info "FASE 1 — Estado inicial"
    local web state status restart_count health
    for web in "$PRO_WEB" "${PRO_WEB_PEERS[@]}"; do
        state="$(container_state "$web")"
        IFS='|' read -r status restart_count health <<<"$state"
        printf '[INITIAL] %s -> %s / %s\n' "$web" "$status" "$health"
    done

    info "FASE 2 — Distribución inicial del Load Balancer (20 solicitudes)"
    if sample_lb_requests "LB" 20 pro_demo_initial_counts pro_demo_initial_http_errors pro_demo_initial_violations; then
        if (( pro_demo_initial_counts[$PRO_WEB] > 0 &&
            pro_demo_initial_counts[${PRO_WEB_PEERS[0]}] > 0 &&
            pro_demo_initial_counts[${PRO_WEB_PEERS[1]}] > 0 )); then
            pro_demo_initial_distribution=1
        fi
    fi
    if (( !pro_demo_initial_distribution )); then
        fail "La distribución inicial no confirmó tráfico correcto por las tres réplicas; no se detendrá ninguna."
        pro_demo_failed=1
        print_pro_demo_summary
        return 1
    fi

    if ! web_container_alert_is_inactive; then
        fail "La alerta dejó de estar inactiva antes de la caída; no se detendrá ninguna réplica."
        pro_demo_failed=1
        print_pro_demo_summary
        return 1
    fi
    if ! active_alerts="$(alertmanager_active_alert_count)" || [[ "$active_alerts" != "0" ]]; then
        fail "Alertmanager dejó de estar libre de alertas activas; no se detendrá ninguna réplica."
        pro_demo_failed=1
        print_pro_demo_summary
        return 1
    fi
    if ! notification_before="$(alertmanager_telegram_counts)"; then
        fail "No se pudieron refrescar los contadores Telegram; no se detendrá ninguna réplica."
        pro_demo_failed=1
        print_pro_demo_summary
        return 1
    fi
    IFS='|' read -r total_before failed_before <<<"$notification_before"
    if [[ ! "$total_before" =~ ^[0-9]+$ || ! "$failed_before" =~ ^[0-9]+$ ]]; then
        fail "Alertmanager devolvió contadores Telegram inválidos; no se detendrá ninguna réplica."
        pro_demo_failed=1
        print_pro_demo_summary
        return 1
    fi

    pause_enter "FASE 3 — Preparado para simular la caída de $PRO_WEB. El siguiente paso lo detendrá."
    info "FASE 3 — Simulando caída de $PRO_WEB"
    printf '\n================================================\n'
    printf 'SIMULANDO CAÍDA DE %s\n' "$PRO_WEB"
    printf '================================================\n'
    web_restore_needed=1
    if ! docker stop --time 5 "$PRO_WEB" >/dev/null; then
        fail "No se pudo detener $PRO_WEB."
        pro_demo_failed=1
        print_pro_demo_summary
        return 1
    fi
    pro_demo_stop_started="$(date +%s)"
    state="$(container_state "$PRO_WEB")"
    pro_demo_outage_status="${state%%|*}"
    info "$PRO_WEB -> $pro_demo_outage_status"
    if [[ "$pro_demo_outage_status" == "exited" ]]; then
        pro_demo_stopped=1
    else
        fail "$PRO_WEB no confirmó estado exited después de docker stop."
        pro_demo_failed=1
    fi

    pause_enter "FASE 4 — $PRO_WEB está detenida. Pulsa ENTER para probar el failover con 20 solicitudes."
    info "FASE 4 — Failover del Load Balancer (20 solicitudes)"
    if sample_lb_requests "FAILOVER" 20 pro_demo_failover_counts pro_demo_failover_http_errors pro_demo_failover_violations "$PRO_WEB"; then
        if (( pro_demo_failover_counts[${PRO_WEB_PEERS[0]}] > 0 &&
            pro_demo_failover_counts[${PRO_WEB_PEERS[1]}] > 0 )); then
            pro_demo_failover=1
        fi
    fi
    if (( !pro_demo_failover )); then
        fail "El failover no quedó completamente confirmado; se mantendrá $PRO_WEB detenida mientras se comprueba la alerta."
        pro_demo_failed=1
    else
        pass "El Load Balancer sigue atendiendo sin $PRO_WEB."
    fi

    info "FASE 5 — Comprobación manual de Prometheus Firing y Telegram"
    while true; do
        pause_enter "Abre Prometheus/Alertmanager, verifica WebContainerMissing y Telegram. Cuando quieras que el script compruebe el estado,"
        local state notification_after total_after failed_after active_alerts_after
        if ! state="$(prometheus_web_container_alert_state)"; then
            fail "No se pudo consultar la alerta WebContainerMissing."
            pro_demo_failed=1
            break
        fi
        pro_demo_alert_state="$state"
        printf '[ALERT] WebContainerMissing -> %s\n' "$state"
        if [[ "$state" == "firing" ]]; then
            pro_demo_alert_fired=1
            if alertmanager_has_web_alert; then
                info "Alertmanager registró WebContainerMissing para $PRO_WEB."
                pro_demo_alertmanager_received=1
                if active_alerts_after="$(alertmanager_active_alert_count)" &&
                    [[ "$active_alerts_after" == "1" ]] &&
                    notification_after="$(alertmanager_telegram_counts)"; then
                    IFS='|' read -r total_after failed_after <<<"$notification_after"
                    pro_demo_telegram_delta=$((total_after - total_before))
                    pro_demo_telegram_failures=$((failed_after - failed_before))
                    if (( pro_demo_telegram_failures > 0 )); then
                        fail "Alertmanager registró fallos en Telegram durante la demo."
                        pro_demo_failed=1
                        break
                    fi
                    if (( pro_demo_telegram_delta > 0 )); then
                        pro_demo_telegram_confirmed=1
                        info "El contador Telegram aumentó en $pro_demo_telegram_delta sin fallos."
                        break
                    else
                        warn "La alerta está FIRING, pero todavía no se confirma un nuevo envío Telegram."
                    fi
                else
                    warn "Prometheus está FIRING, pero no se pudo confirmar Alertmanager/Telegram aún."
                fi
            else
                warn "Prometheus está FIRING, pero Alertmanager aún no muestra la alerta."
            fi
        else
            warn "La alerta todavía no está FIRING."
        fi
        if ! confirm "¿Quieres volver a comprobar (S) o salir de esta comprobación (otra tecla)?"; then
            pro_demo_failed=1
            break
        fi
    done

    if (( !pro_demo_alert_fired )); then
        fail "No se confirmó WebContainerMissing en estado FIRING para $PRO_WEB."
        pro_demo_failed=1
    fi
    if (( pro_demo_alert_fired && !pro_demo_alertmanager_received )); then
        fail "Prometheus activó la alerta, pero Alertmanager no registró la alerta correspondiente."
        pro_demo_failed=1
    fi
    if (( pro_demo_alert_fired && pro_demo_alertmanager_received && !pro_demo_telegram_confirmed )); then
        fail "No se confirmó un envío Telegram exitoso durante la comprobación manual."
        pro_demo_failed=1
    fi

    printf '\n================================================\n'
    printf 'RECUPERANDO %s\n' "$PRO_WEB"
    printf '================================================\n'
    pause_enter "FASE 6 — Pulsa ENTER para iniciar la recuperación de $PRO_WEB."
    info "FASE 6 — Recovery automático"
    info "Esperando healthcheck..."
    if restore_pro_web; then
        pass "$PRO_WEB -> running / healthy"
    else
        fail "No se confirmó la recuperación de $PRO_WEB; el trap volverá a intentarla."
        pro_demo_failed=1
    fi

    if ! wait_for_web_container_alert_inactive 90; then
        pro_demo_failed=1
    fi

    pause_enter "FASE 7 — $PRO_WEB está healthy. Pulsa ENTER para comprobar el tráfico tras la recuperación."
    info "FASE 7 — Tráfico después del recovery (30 solicitudes)"
    if (( pro_demo_recovery_healthy )); then
        if sample_lb_requests "RECOVERY" 30 pro_demo_post_counts pro_demo_post_http_errors pro_demo_post_violations; then
            pro_demo_post_lb_operational=1
            if (( pro_demo_post_counts[$PRO_WEB] > 0 )); then
                pro_demo_web_back_in_rotation=1
            else
                fail "$PRO_WEB está healthy, pero no recibió ninguna de las 30 solicitudes."
                pro_demo_failed=1
            fi
        else
            fail "El Load Balancer no respondió correctamente durante el muestreo posterior al recovery."
            pro_demo_failed=1
        fi
    else
        fail "Se omite el muestreo del Load Balancer porque $PRO_WEB no confirmó healthcheck healthy."
        pro_demo_failed=1
    fi

    if (( !pro_demo_initial_distribution ||
        !pro_demo_failover ||
        !pro_demo_alert_fired ||
        !pro_demo_alertmanager_received ||
        !pro_demo_telegram_confirmed ||
        !pro_demo_recovery_healthy ||
        !pro_demo_post_lb_operational ||
        !pro_demo_web_back_in_rotation )); then
        pro_demo_failed=1
    fi

    print_pro_demo_summary
    if (( pro_demo_failed )); then
        return 1
    fi
}

demo_load_balancer() {
    require_command curl
    require_command python3
    require_docker
    check_running_healthy "$PRO_LB"
    check_running_healthy "$PRO_WEB"
    for peer in "${PRO_WEB_PEERS[@]}"; do
        check_running_healthy "$peer"
    done

    local requests=20
    local completed=0
    local failed=0
    local response instance
    declare -A counts=()

    info "Enviando $requests solicitudes a $PRO_URL/instance..."
    for ((i = 1; i <= requests; i++)); do
        if response="$(get_instance "$PRO_URL" 2>/dev/null)"; then
            instance="$response"
            counts["$instance"]=$(( ${counts["$instance"]:-0} + 1 ))
            completed=$((completed + 1))
        else
            failed=$((failed + 1))
        fi
        sleep 0.1
    done

    printf 'Solicitudes correctas: %d; fallidas: %d\n' "$completed" "$failed"
    printf 'Réplicas observadas:\n'
    local replicas=0
    for instance in "${!counts[@]}"; do
        printf '  %s: %d\n' "$instance" "${counts[$instance]}"
        replicas=$((replicas + 1))
    done

    if (( failed > 0 )); then
        fail "Hubo solicitudes fallidas durante la prueba."
        return 1
    fi
    if (( replicas < 2 )); then
        fail "No se observaron las dos réplicas; revisa el upstream y el estado de PRO."
        return 1
    fi
    pass "El balanceador distribuyó solicitudes entre $replicas réplicas."
}

demo_dev_persistence() {
    require_command curl
    require_command python3
    require_docker
    check_running_healthy "$DEV_DB"

    local mount
    mount="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/var/lib/mysql"}}{{.Type}}|{{.Name}}{{end}}{{end}}' "$DEV_DB")"
    if [[ "$mount" != "volume|$DEV_VOLUME" ]]; then
        fail "$DEV_DB no usa el volumen esperado ($DEV_VOLUME) en /var/lib/mysql; se cancela para evitar una prueba engañosa. Detectado: ${mount:-ninguno}"
        return 1
    fi

    local suffix
    suffix="$(date +%Y%m%d%H%M%S)_$$"
    demo_table="demo_persistence_$suffix"
    demo_marker="persisted_$suffix"

    if ! confirm "La prueba parará y volverá a iniciar $DEV_DB. Es solo DEV. Se creará una tabla temporal y se eliminará al terminar; no se borrará ni recreará el volumen $DEV_VOLUME."; then
        demo_table=""
        info "Prueba cancelada; no se modificó la base de datos."
        return 0
    fi

    local create_sql
    create_sql="CREATE TABLE \`$demo_table\` (marker VARCHAR(100) NOT NULL PRIMARY KEY) ENGINE=InnoDB; INSERT INTO \`$demo_table\` (marker) VALUES ('$demo_marker');"
    db_restore_needed=1
    mysql_query "$create_sql" >/dev/null
    pass "Dato guardado: $demo_marker (contenedor $DEV_DB, volumen $DEV_VOLUME)."

    info "Parando y arrancando el contenedor (sin borrar el volumen)..."
    docker stop --time 10 "$DEV_DB" >/dev/null
    docker start "$DEV_DB" >/dev/null

    info "Esperando que MySQL vuelva a healthy (máximo 180s)..."
    wait_for_healthy "$DEV_DB" 180

    local persisted
    persisted="$(mysql_query "SELECT CONCAT(COUNT(*), '|', COALESCE(MAX(marker), '')) FROM \`$demo_table\`;")"
    if [[ "$persisted" != "1|$demo_marker" ]]; then
        fail "El contenido leído tras reiniciar no coincide con lo guardado: $persisted"
        return 1
    fi

    pass "Persistencia confirmada: después del reinicio se leyó de nuevo '$demo_marker'."
    if ! mysql_query "DROP TABLE \`$demo_table\`;" >/dev/null; then
        fail "No se pudo limpiar la tabla temporal $demo_table."
        return 1
    fi
    info "Tabla temporal eliminada. El volumen $DEV_VOLUME permanece intacto."
    demo_table=""
    db_restore_needed=0
}

show_menu() {
    printf '\n'
    printf '%s\n' '============================================'
    printf '%s\n' ' StreamForge - Demo de resiliencia Docker'
    printf '%s\n' '============================================'
    printf '%s\n' '1) PRO: failover, alerta Telegram y recuperación automática'
    printf '%s\n' '2) PRO: comprobar distribución del Load Balancer'
    printf '%s\n' '3) DEV: reiniciar MySQL y comprobar persistencia del volumen'
    printf '%s\n' '0) Salir'
    printf '\n'
}

main() {
    require_command docker
    require_command curl
    require_command python3

    while true; do
        show_menu
        printf 'Selecciona una opción: '
        local choice
        read -r choice || return 0
        case "$choice" in
            1) demo_pro_recovery ;;
            2) demo_load_balancer ;;
            3) demo_dev_persistence ;;
            0) info "Hasta luego."; return 0 ;;
            *) warn "Opción no válida: $choice" ;;
        esac
    done
}

main "$@"
