#!/usr/bin/env bash
set -uo pipefail

log() { printf '\n[+] %s\n' "$*"; }
warn() { printf '\n[!] %s\n' "$*" >&2; }
try() {
  printf '    -> %s\n' "$*"
  bash -lc "$*" || warn "command failed: $*"
}

BACKUP_DIR="/root/ir-resume-$(date +%F-%H%M%S)"
mkdir -p "$BACKUP_DIR"

log "Backing up SSH and systemd state"
[ -f /root/.ssh/authorized_keys ] && cp -a /root/.ssh/authorized_keys "$BACKUP_DIR/" || true
[ -f /etc/ssh/sshd_config ] && cp -a /etc/ssh/sshd_config "$BACKUP_DIR/" || true
cp -a /etc/systemd/system "$BACKUP_DIR/" 2>/dev/null || true
cp -a /usr/lib/systemd/system "$BACKUP_DIR/" 2>/dev/null || true

log "Cleaning attacker root authorized_keys entry"
mkdir -p /root/.ssh
chmod 700 /root/.ssh
if [ -f /root/.ssh/authorized_keys ]; then
  tmp_keys=$(mktemp)
  grep -v 'WE ARE A TEAM' /root/.ssh/authorized_keys > "$tmp_keys" || true
  cat "$tmp_keys" > /root/.ssh/authorized_keys
  rm -f "$tmp_keys"
else
  touch /root/.ssh/authorized_keys
fi
chmod 600 /root/.ssh/authorized_keys

log "Reasserting safe SSH setting and restarting ssh"
if [ -f /etc/ssh/sshd_config ]; then
  sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
  grep -q '^PermitRootLogin no$' /etc/ssh/sshd_config || echo 'PermitRootLogin no' >> /etc/ssh/sshd_config
fi
try "sshd -t"
try "systemctl restart ssh"
try "systemctl status ssh --no-pager"

log "Finding malicious-looking systemd unit files"
PATTERN='Red Team Was Here :\)|cmd_exec\.so|/usr/bin/rangd|/var/tmp/ksession|/opt/platform/runtime|/opt/runtime/cachesyncd|/sbin/mount\.recoveryfs|/var/lib/misc/audit|/var/cache/fontconfig|/var/lib/dbus/systemhelper|/var/opt/runtime/session-cache|/udev/\.udev/firmware|/usr/lib/firmware/fw'
mapfile -t BAD_UNIT_FILES < <(grep -RIlE "$PATTERN" /etc/systemd/system /usr/lib/systemd/system 2>/dev/null | sort -u)

if [ "${#BAD_UNIT_FILES[@]}" -eq 0 ]; then
  warn "No matching malicious unit files found"
else
  printf '\n[+] Matched unit files:\n'
  printf '    %s\n' "${BAD_UNIT_FILES[@]}"
fi

log "Stopping, disabling, and masking matched units"
for f in "${BAD_UNIT_FILES[@]}"; do
  unit="$(basename "$f")"
  try "systemctl stop '$unit'"
  try "systemctl disable '$unit'"
  try "systemctl mask '$unit'"
done

log "Removing wants/aliases that point at matched unit files"
while IFS= read -r link; do
  target="$(readlink -f "$link" 2>/dev/null || true)"
  for f in "${BAD_UNIT_FILES[@]}"; do
    if [ "$target" = "$f" ]; then
      try "rm -f '$link'"
      break
    fi
  done
done < <(find /etc/systemd/system -type l 2>/dev/null)

log "Special-case stop/disable/mask for known bad units seen in your output"
for unit in \
  redis.service pulseaudio.service pkgcached.service fswatcherd.service \
  updatetrackd.service authwatchd.service dnsmonitord.service \
  modtrackd.service sysstartupd.service cronassistd.service \
  mountwatchd.service timetrackd.service logctl-agent.timer \
  firewalld-fallback.timer rpc-service-helper.timer cron-repair.service \
  socket-guard.socket
do
  if systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -qx "$unit"; then
    try "systemctl stop '$unit'"
    try "systemctl disable '$unit'"
    try "systemctl mask '$unit'"
  fi
done

log "Reloading systemd"
try "systemctl daemon-reload"
try "systemctl reset-failed"

log "Restarting scoring-critical services"
for unit in nginx ssh snb_backend snb_frontend; do
  if systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -qx "${unit}.service"; then
    try "systemctl restart '$unit'"
  fi
done

log "Verification"
try "grep -n '^PermitRootLogin' /etc/ssh/sshd_config"
try "grep -n 'WE ARE A TEAM' /root/.ssh/authorized_keys"
try \"grep -RniE 'WE ARE A TEAM|aio-linux|172\\.18\\.1\\.30|cmd_exec\\.so|/usr/bin/rangd|Red Team Was Here' /etc/systemd/system /usr/lib/systemd/system /root/.ssh /var/spool/cron 2>/dev/null\"
try "systemctl is-active nginx ssh snb_backend snb_frontend"
try "systemctl list-unit-files | grep -E 'redis|pulseaudio|pkgcached|fswatcherd|updatetrackd|authwatchd|dnsmonitord|modtrackd|sysstartupd|cronassistd|mountwatchd|timetrackd|logctl-agent|firewalld-fallback|rpc-service-helper|cron-repair|socket-guard'"

log "Done"
echo
echo "Backups saved in: $BACKUP_DIR"
echo "Retest web, SSL, admin login, create-user flow, and SSH scoring users now."