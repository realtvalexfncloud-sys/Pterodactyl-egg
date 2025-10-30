#!/bin/bash
set -euo pipefail
QMP="/home/container/vm/qmp.sock"

if [ -S "$QMP" ]; then
  (echo '{ "execute": "qmp_capabilities" }'; sleep 0.2; echo '{ "execute": "system_powerdown" }') \
    | socat - UNIX-CONNECT:"$QMP" >/dev/null 2>&1 || true
  for i in {1..20}; do
    sleep 1
    if ! pgrep -f qemu-system-x86_64 >/dev/null; then
      exit 0
    fi
  done
fi

pkill -SIGTERM -f qemu-system-x86_64 || true
