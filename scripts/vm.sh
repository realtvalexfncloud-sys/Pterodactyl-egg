#!/bin/bash
set -euo pipefail
QMP="/home/container/vm/qmp.sock"

usage() {
  echo "Usage: $0 {status|poweroff|reboot|kill|info}"
  exit 1
}

status() {
  if pgrep -f qemu-system-x86_64 >/dev/null; then
    echo "VM läuft (PID: $(pgrep -f qemu-system-x86_64 | tr '\n' ' '))"
  else
    echo "VM ist gestoppt"
  fi
}

qmp() {
  local cmd="$1"
  if [ -S "$QMP" ]; then
    (echo '{ "execute": "qmp_capabilities" }'; sleep 0.2; echo "{ \"execute\": \"${cmd}\" }") \
      | socat - UNIX-CONNECT:"$QMP"
  else
    echo "QMP Socket nicht gefunden: $QMP" >&2
    return 1
  fi
}

poweroff() { qmp system_powerdown || true; }
reboot()   { qmp system_reset || true; }
kill_vm()  { pkill -9 -f qemu-system-x86_64 || true; }

info() {
  echo "OS=${OS_FAMILY:-?} ${OS_VERSION:-?} | RAM=${RAM_MB:-?}MB | vCPU=${CPU_CORES:-?} | Disk=${DISK_SIZE_GB:-?}G"
  echo "SSH-Port (Host): ${SERVER_PORT:-?} -> VM:22"
  echo "Weitere Forwards: ${FORWARD_PORTS:-<none>}"
  if [ -f "/home/container/vm/disk.qcow2" ]; then
    echo "Disk Info:"
    qemu-img info /home/container/vm/disk.qcow2 || true
  fi
}

case "${1:-}" in
  status)   status ;;
  poweroff) poweroff ;;
  reboot)   reboot ;;
  kill)     kill_vm ;;
  info)     info ;;
  *)        usage ;;
esac
