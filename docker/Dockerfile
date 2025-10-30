FROM debian:12-slim

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      qemu-system-x86 qemu-utils cloud-image-utils genisoimage \
      curl ca-certificates jq socat iproute2 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /home/container
