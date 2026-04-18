systemctl stop rpcbind rpcbind.socket nfs-server nfs-kernel-server nfs-mountd rpc-statd rpc-statd-notify nfs-idmapd 2>/dev/null || true
systemctl disable rpcbind rpcbind.socket nfs-server nfs-kernel-server nfs-mountd rpc-statd rpc-statd-notify nfs-idmapd 2>/dev/null || true
systemctl mask rpcbind rpcbind.socket nfs-server nfs-kernel-server nfs-mountd rpc-statd rpc-statd-notify nfs-idmapd 2>/dev/null || true

# kill leftovers
pkill -f 'rpc\.' || true
pkill -f nfs || true