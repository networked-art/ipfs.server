#!/bin/sh

# Create a fixed-size ext4 cache volume on the large /home filesystem. The
# Rainbow cache cannot exceed this filesystem even when its GC is delayed.
# Run only once on the target host, before deploying the service.
set -eu

image="${RAINBOW_IMAGE_PATH:-/home/ipfs/rainbow-cache.img}"
mountpoint="${RAINBOW_MOUNTPOINT:-/home/ipfs/rainbow}"
size="${RAINBOW_CACHE_SIZE:-250G}"

if mountpoint -q "$mountpoint"; then
  echo "already mounted: $mountpoint"
  exit 0
fi

test ! -e "$image" || { echo "refusing existing image: $image" >&2; exit 1; }
mkdir -p "$mountpoint"
fallocate -l "$size" "$image"
mkfs.ext4 -F -m 0 "$image"
mount -o loop,nosuid,nodev,noexec "$image" "$mountpoint"
chown 1000:1000 "$mountpoint"

grep -Fq " $mountpoint ext4 " /etc/fstab || \
  printf '%s %s ext4 loop,nosuid,nodev,noexec 0 2\n' "$image" "$mountpoint" >> /etc/fstab
