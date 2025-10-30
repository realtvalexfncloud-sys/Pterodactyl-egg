#!/bin/bash
set -euo pipefail

cd /home/container

# Banner beim Start (optional)
if [ "${SHOW_BANNER:-1}" = "1" ] && [ -f "./banner.txt" ]; then
  echo
  sed -e 's/\r$//' ./banner.txt || cat ./banner.txt
  echo
fi

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

# URLs für Cloud-Images
ubuntu_url() {
  case "$1" in
    20.04) echo "https://cloud-images.ubuntu.com/releases/focal/release/ubuntu-20.04-server-cloudimg-amd64.img" ;;
    22.04) echo "https://cloud-images.ubuntu.com/releases/jammy/release/ubuntu-22.04-server-cloudimg-amd64.img" ;;
    24.04) echo "https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img" ;;
    *) echo "Unsupported Ubuntu version: $1" >&2; exit 1 ;;
  esac
}
debian_url() {
  case "$1" in
    11) echo "https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2" ;;
    12) echo "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2" ;;
    *) echo "Unsupported Debian version: $1" >&2; exit 1 ;;
  esac
}

case "$OS_FAMILY" in
  ubuntu) IMG_URL="$(ubuntu_url "$OS_VERSION")" ;;
  debian) IMG_URL="$(debian_url "$OS_VERSION")" ;;
  *) echo "Unsupported OS_FAMILY: $OS_FAMILY" >&2; exit 1 ;;
esac

# Base-Image laden
if [ ! -f "$BASE_IMG" ]; then
  echo "Downloading cloud image: $IMG_URL"
  curl -fL --retry 3 --connect-timeout 10 "$IMG_URL" -o "$BASE_IMG.tmp"
  mv "$BASE_IMG.tmp" "$BASE_IMG"
fi

# Overlay-Disk anlegen
if [ ! -f "$DISK_IMG" ]; then
  echo "Creating disk $DISK_IMG size ${DISK_SIZE_GB}G"
  qemu-img create -f qcow2 -b "$BASE_IMG" "$DISK_IMG" "${DISK_SIZE_GB}G" >/dev/null
fi

# Cloud-Init Seed (User/Pass/SSH-Key/Hostname + Autogrow)
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
growpart:
  mode: auto
  devices: ["/dev/vda"]
  ignore_growroot_disabled: false
EOF

  cat > meta-data <<EOF
instance-id: ptero-${P_SERVER_UUID:-0}
local-hostname: ${VM_HOSTNAME}
EOF

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
CPU_MODEL="qemu64"
if [ "${ENABLE_KVM}" = "1" ] && [ -e /dev/kvm ]; then
  ACCEL="kvm"
  CPU_MODEL="host"
else
  echo "WARN: KVM nicht verfügbar – die VM wird langsam sein."
fi

# Konsole
DISPLAY_OPTS="-nographic -serial mon:stdio -display none"
if [ "${CONSOLE}" = "vnc" ]; then
  VNC_DISPLAY="${VNC_DISPLAY:-0}"
  DISPLAY_OPTS="-vnc 0.0.0.0:${VNC_DISPLAY} -serial none -display vnc"
fi

# QMP Socket säubern
rm -f "$QMP_SOCK"

# Infos
echo "OS: ${OS_FAMILY} ${OS_VERSION} | RAM: ${RAM_MB}MB | vCPU: ${CPU_CORES} | Disk: ${DISK_SIZE_GB}G"
echo "SSH: Verbinde auf Node-IP mit Port ${SSH_PORT} (User: ${VM_USER})"
echo "VM_READY"

# Start QEMU (im Vordergrund)
exec qemu-system-x86_64 \
  -machine type=q35,accel=${ACCEL} \
  -cpu ${CPU_MODEL} \
  -smp ${CPU_CORES} \
  -m ${RAM_MB} \
  -name "ptero-${P_SERVER_UUID:-vm}" \
  -qmp unix:"$QMP_SOCK",server,nowait \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0,${HOSTFWD_OPTS} \
  -drive if=virtio,file="$DISK_IMG",format=qcow2,cache=writeback,discard=unmap \
  -drive if=virtio,file="$SEED_ISO",format=raw,readonly=on,media=cdrom \
  ${DISPLAY_OPTS}
