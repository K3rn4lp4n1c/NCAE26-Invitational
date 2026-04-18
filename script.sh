#!/usr/bin/env bash
set -euo pipefail

echo "[*] Stopping rpcbind/NFS-related systemd units only..."

units=(
  rpcbind.service
  rpcbind.socket
  nfs-server.service
  nfs-kernel-server.service
  nfs-mountd.service
  rpc-statd.service
  rpc-statd-notify.service
  nfs-idmapd.service
  proc-fs-nfsd.mount
)

for unit in "${units[@]}"; do
  if systemctl list-unit-files --no-legend --no-pager | awk '{print $1}' | grep -qx "$unit"; then
    echo "[+] stop/disable/mask $unit"
    sudo systemctl stop "$unit" || true
    sudo systemctl disable "$unit" || true
    sudo systemctl mask "$unit" || true
  fi
done

echo "[*] Stopping NFS-related targets if present..."
targets=(
  nfs-client.target
  nfs-server.target
)

for unit in "${targets[@]}"; do
  if systemctl list-unit-files --type=target --no-legend --no-pager | awk '{print $1}' | grep -qx "$unit"; then
    echo "[+] stop/mask $unit"
    sudo systemctl stop "$unit" || true
    sudo systemctl mask "$unit" || true
  fi
done

echo "[*] Killing leftover rpc/nfs helper processes..."
sudo pkill -x rpcbind || true
sudo pkill -x rpc.statd || true
sudo pkill -x rpc.mountd || true
sudo pkill -x exportfs || true
sudo pkill -f '/usr/sbin/rpc\.' || true

echo "[*] Reloading systemd..."
sudo systemctl daemon-reload

echo "[*] Remaining rpc/nfs listeners, if any:"
ss -ltnp | egrep '(:111|:2049|rpcbind|rpc\.mountd|rpc\.statd|nfs)' || true

echo
echo "[*] Full listening sockets:"
ss -ltnp