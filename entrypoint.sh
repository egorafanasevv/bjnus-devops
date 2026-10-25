#!/bin/sh
set -eu

mkdir -p "$PROBE_OUTPUT_DIR"
chown app:app "$PROBE_OUTPUT_DIR"

printf 'export PROBE_TIMEOUT=%s\nexport PROBE_OUTPUT_DIR=%s\n' \
  "$PROBE_TIMEOUT" "$PROBE_OUTPUT_DIR" > /app/probe-env.sh

exec crond -f -l 8 -c /etc/crontabs
