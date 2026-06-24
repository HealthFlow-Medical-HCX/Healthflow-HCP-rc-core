#!/bin/bash
set -e
TARGET="/mnt/healthflow-data"
mkdir -p "$TARGET"
DEV=/dev/disk/by-id/scsi-0DO_Volume_ndp-healthflow-data
mountpoint -q "$TARGET" || mount -o defaults,nofail,discard "$DEV" "$TARGET"
grep -q "scsi-0DO_Volume_ndp-healthflow-data" /etc/fstab || echo "$DEV $TARGET ext4 defaults,nofail,discard 0 2" >> /etc/fstab
df -h "$TARGET"
echo "--- fstab ---"; grep healthflow-data /etc/fstab
