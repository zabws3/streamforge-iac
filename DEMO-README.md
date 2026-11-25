# StreamForge - demo de resiliencia Docker

Ejecuta `./demo.sh` (o `make demo`) desde el repositorio. Requiere Bash, Docker
CLI con acceso al daemon, `curl` y Python 3. No ejecuta Terraform ni crea o
elimina contenedores o volúmenes.

## Menú

| Opción | Entorno | Prueba |
|---|---|---|
| 1 | PRO | Prueba el failover deteniendo brevemente `pro_web_1` y exige respuestas del Load Balancer desde otras réplicas; lo restaura y verifica que vuelva a recibir tráfico. Después mata el contenedor y comprueba el incremento de `RestartCount`, `unless-stopped` y el healthcheck. Por último, mantiene una caída hasta que Prometheus active `WebInstanceUnreachable` y Alertmanager registre el envío exitoso a Telegram. Requiere confirmación y puede tardar hasta 5 minutos. |
| 2 | PRO | Envía 20 solicitudes a `http://localhost:8082/instance`, cuenta qué réplicas responden y requiere observar al menos dos de las tres Web. |
| 3 | DEV | Comprueba que `/var/lib/mysql` está montado desde `dev_mysql_data`, crea una tabla/valor temporal, para e inicia `dev_database`, espera a MySQL y lee el valor de nuevo. Elimina solo la tabla temporal; nunca borra el volumen ni los datos existentes. Requiere confirmación. |

Las pruebas PRO suponen `pro_web_1`, `pro_web_2`, `pro_web_3`,
`pro_load_balancer`, `pro_prometheus` y `pro_alertmanager`; DEV usa
`dev_database` y `dev_mysql_data`. Los endpoints son los puertos locales
documentados en [README.md](./README.md).

## Seguridad y recuperación

- La opción 1 detiene y mata una réplica en PRO, y solo debe usarse en el
  entorno local/aislado de la práctica, nunca en producción real o compartida.
  La parada intencional se restaura con `docker start`; por separado, matar el
  contenedor prueba la recuperación automática real de Docker.
- `WebInstanceUnreachable` tiene `for: 2m` y Alertmanager `group_wait: 30s`.
  La demo mantiene la réplica detenida hasta detectar la alerta en firing y un
  log `Notify success` del grupo Web en el receptor Telegram; no confunde la
  mera aceptación de la alerta por la API con la entrega del mensaje.
- La entrega requiere que Alertmanager resuelva y alcance `api.telegram.org`.
  Si falla el preflight DNS, la demo permite ejecutar solo failover y
  recuperación, pero marca la prueba completa como fallida y no afirma que
  Telegram funcione. La configuración actual de red da salida a Alertmanager
  por `pro_frontend`; un fallo de resolución dentro de ese contenedor debe
  corregirse en el DNS/runtime de Docker, no ocultarse con un filtro PromQL ni
  con un DNS público fijo en Terraform.
- La opción 3 reinicia MySQL en DEV y puede causar una breve indisponibilidad de
  la aplicación. La prueba falla de forma explícita si el contenedor no usa el
  volumen esperado.
- Ctrl+C, errores y salida normal intentan restaurar Web/MySQL y limpiar la
  tabla temporal. No mates el daemon Docker durante una prueba. Si la limpieza
  no puede completarse, la demo indica el recurso que debe revisarse
  manualmente.
- La demo no muestra variables de entorno, contraseñas ni datos reales. El
  único dato insertado es un marcador sintético y temporal.

## Ejecución

```bash
./demo.sh
```

Antes de presentar, despliega y comprueba los entornos por separado. La opción
1 exige saludables las tres réplicas, el balanceador y la monitorización PRO;
la opción 2 requiere saludables las tres réplicas y observar al menos dos.
Las opciones 1 y 3 solicitan confirmación antes de modificar el estado de
Docker.
