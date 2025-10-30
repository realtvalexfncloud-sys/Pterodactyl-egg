#!/bin/bash
set -euo pipefail

cd /home/container

RAM_MB="${RAM_MB:-2048}"
CPU_CORES="${CPU_CORES:-2}"
DISK_SIZE_GB="${DISK_SIZE_GB:-20}"
OS_FAMILY="${OS_FAMILY:-ubuntu}"
OS_VERSION="${OS_VERSION:-22.04}"
ENABLE_KVM="${ENABLE_KVM:-1}"
CONSOLE="${CONSOLE:-serial}"
FORWARD_PORTS="${FORWARD_PORTS:-}"
SSH_PORT="${SERVER_PORT:-2222}"

VM_USER="${VM_USER:-ptero}"
VM_PASSWORD="${VM_PASSWORD:-ChangeMe123!}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-}"
VM_HOSTNAME="${VM_HOSTNAME:-vm}"

VM_DIR="./vm"
mkdir -p "$VM_DIR"
BASE_IMG="$VM_DIR/base.img"
DISK_IMG="$VM_DIR/disk.qcow2"
SEED_ISO="$VM_DIR/seed.iso"
QMP_SOCK="$VM_DIR/qmp.sock"

# Map Ubuntu/Debian Version -> Codename und URL
ubuntu_url() {
  local v="$1" codename=""
  case "$v" in
    20.04) codename="focal" ;;
    22.04) codename="jammy" ;;
    24.04) codename="noble" ;;
    *) echo "Unsupported Ubuntu version: $v" >&2; exit 1 ;;
  esac
  echo "https://cloud-images.ubuntu.com/releases/${codename}/release/ubuntu-${v}-server-cloudimg-amd64.img"
}

debian_url() {
  local v="$1" codename=""
  case "$v" in
    11) codename="bullseye" ;;
    12) codename="bookworm" ;;
    *) echo "Unsupported Debian version: $v" >&2; exit 1 ;;
  esac
  echo "https://cloud.debian.org/images/cloud/${codename}/latest/debian-${v}-genericcloud-amd64.qcow2"
}

img_url=""
case "$OS_FAMILY" in
  ubuntu) img_url="$(ubuntu_url "$OS_VERSION")" ;;
  debian) img_url="$(debian_url "$OS_VERSION")" ;;
  *) echo "Unsupported OS_FAMILY: $OS_FAMILY" >&2; exit 1 ;;
esac

# Download Base-Image (einmalig)
if [ ! -f "$BASE_IMG" ]; then
  echo "Downloading cloud image: $img_url"
  curl -fL --retry 3 --connect-timeout 10 "$img_url" -o "$BASE_IMG.tmp"
  mv "$BASE_IMG.tmp" "$BASE_IMG"
fi

# Disk anlegen (Overlay über Base, damit Upgrades weniger Platz brauchen)
if [ ! -f "$DISK_IMG" ]; then
  echo "Creating disk $DISK_IMG size ${DISK_SIZE_GB}G"
  qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMG" "$DISK_IMG" "${DISK_SIZE_GB}G" >/dev/null
fi

# Cloud-Init Seed erzeugen (User/Pass/SSH-Key/Hostname)
if [ ! -f "$SEED_ISO" ]; then
  cat > user-data <<EOF
#cloud-config
users:
  - name: ${VM_USER}
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    lock_passwd: false
ssh_pwauth: true
chpasswd:
  list: |
    ${VM_USER}:${VM_PASSWORD}
  expire: false
$( [ -n "$SSH_PUBLIC_KEY" ] && echo "ssh_authorized_keys:" && echo "  - ${SSH_PUBLIC_KEY}" )
package_update: true
package_upgrade: false
timezone: UTC
EOF

  cat > meta-data <<EOF
instance-id: ptero-${P_SERVER_UUID:-0}
local-hostname: ${VM_HOSTNAME}
EOF

  # cloud-localds erzeugt ISO mit cidata
  cloud-localds -v "$SEED_ISO" user-data meta-data
  rm -f user-data meta-data
fi

# Port-Forwards
HOSTFWD_OPTS="hostfwd=tcp:0.0.0.0:${SSH_PORT}-:22"
if [ -n "$FORWARD_PORTS" ]; then
  IFS=',' read -ra PAIRS <<< "$FORWARD_PORTS"
  for pair in "${PAIRS[@]}"; do
    hp="${pair%%->*}"
    gp="${pair##*->}"
    if [[ "$hp" =~ ^[0-9]+$ ]] && [[ "$gp" =~ ^[0-9]+$ ]]; then
      HOSTFWD_OPTS="${HOSTFWD_OPTS},hostfwd=tcp:0.0.0.0:${hp}-:${gp}"
    else
      echo "Ignoring invalid FORWARD_PORTS entry: $pair"
    fi
  done
fi

# Beschleunigung
ACCEL="tcg,thread=multi"
CPU="qemu64"
if [ "${ENABLE_KVM}" = "1" ] && [ -e /dev/kvm ]; then
  ACCEL="kvm"
  CPU="host"
else
  echo "WARN: KVM nicht verfügbar – die VM wird langsam sein."
fi

# Konsole/Display
DISPLAY_OPTS="-nographic -serial mon:stdio -display none"
if [ "${CONSOLE}" = "vnc" ]; then
  VNC_DISPLAY="${VNC_DISPLAY:-0}"
  DISPLAY_OPTS="-vnc 0.0.0.0:${VNC_DISPLAY} -serial none -display vnc"
fi

# Aufräumen & 
