#!/bin/sh
set -eu

/usr/bin/docker-entrypoint.sh "$@" &
silo_pid=$!

cleanup() {
  if kill -0 "$silo_pid" 2>/dev/null; then
    kill -TERM "$silo_pid" 2>/dev/null || true
    wait "$silo_pid" 2>/dev/null || true
  fi
}

trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

export MC_CONFIG_DIR=/tmp/.mc
until /usr/bin/curl -fsS -o /dev/null \
  http://127.0.0.1:9000/minio/health/ready; do
  if ! kill -0 "$silo_pid" 2>/dev/null; then
    wait "$silo_pid"
  fi
  sleep 1
done

/usr/bin/mc alias set streamforge http://127.0.0.1:9000 \
  "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
/usr/bin/mc mb --ignore-existing \
  streamforge/streamforge-manifests \
  streamforge/streamforge-chunks

for bucket in streamforge-manifests streamforge-chunks; do
  /usr/bin/mc version enable "streamforge/$bucket"
done

if [ ! -d /media ]; then
  echo "Media directory /media is not mounted." >&2
  exit 1
fi

upload_extension() (
  for item in "$1"/*; do
    [ -e "$item" ] || continue

    if [ -d "$item" ]; then
      upload_extension "$item" "$2" "$3"
    elif [ "${item##*.}" = "$3" ]; then
      relative_path=${item#/media/}
      target="streamforge/$2/$relative_path"

      if ! /usr/bin/mc stat "$target" >/dev/null 2>&1; then
        /usr/bin/mc cp "$item" "$target"
      else
        printf 'Keeping existing object: %s\n' "$target"
      fi
    fi
  done
)

upload_extension /media streamforge-manifests mpd
upload_extension /media streamforge-chunks m4s

wait "$silo_pid"
