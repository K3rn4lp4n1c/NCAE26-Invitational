#!/usr/bin/env bash
set -uo pipefail

log() { printf '\n[+] %s\n' "$*"; }
warn() { printf '\n[!] %s\n' "$*" >&2; }
run() {
  printf '    -> %s\n' "$*"
  bash -lc "$*" || warn "command failed: $*"
}

BACKUP_DIR="/root/ir-backups-$(date +%F-%H%M%S)"
mkdir -p "$BACKUP_DIR"

log "Backing up key files"
for f in \
  /etc/ssh/sshd_config \
  /root/.ssh/authorized_keys \
  /var/spool/cron/atjobs \
  /var/spool/cron/atspool \
  /etc/systemd/system \
  /usr/lib/systemd/system
do
  if [ -e "$f" ]; then
    run "cp -a '$f' '$BACKUP_DIR/'"
  fi
done

log "Stopping and disabling atd persistence"
run "systemctl stop atd"
run "systemctl disable atd"

log "Removing queued at jobs"
if command -v atq >/dev/null 2>&1; then
  JOBS="$(atq 2>/dev/null | awk '{print $1}')"
  if [ -n "${JOBS:-}" ]; then
    for j in $JOBS; do
      run "atrm '$j'"
    done
  fi
fi
run "find /var/spool/cron/atjobs -maxdepth 1 -type f ! -name '.SEQ' -delete"
run "find /var/spool/cron/atspool -maxdepth 1 -type f -delete"

log "Repairing SSH config"
if [ -f /etc/ssh/sshd_config ]; then
  run "sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config"
  run "grep -q '^PermitRootLogin no$' /etc/ssh/sshd_config || echo 'PermitRootLogin no' >> /etc/ssh/sshd_config"
fi

log "Cleaning attacker root authorized_keys entry"
run "mkdir -p /root/.ssh"
run "chmod 700 /root/.ssh"
if [ -f /root/.ssh/authorized_keys ]; then
  TMP_KEYS=\$(mktemp)
  grep -v 'WE ARE A TEAM' /root/.ssh/authorized_keys > \"\$TMP_KEYS\" || true
  cat \"\$TMP_KEYS\" > /root/.ssh/authorized_keys
  rm -f \"\$TMP_KEYS\"
else
  run "touch /root/.ssh/authorized_keys"
fi
run "chmod 600 /root/.ssh/authorized_keys"

log "Validating and restarting ssh"
run "sshd -t"
run "systemctl restart ssh"

log "Finding clearly malicious systemd units"
mapfile -t BAD_UNIT_FILES < <(
  grep -RIlE \
    "Red Team Was Here :\)|cmd_exec\.so|/usr/bin/rangd|/var/tmp/ksession" \
    /etc/systemd/system /usr/lib/systemd/system 2>/dev/null | sort -u
)

if [ "${#BAD_UNIT_FILES[@]}" -eq 0 ]; then
  warn "No matching malicious unit files found with current patterns"
else
  printf '\n[+] Malicious-looking unit files:\n'
  printf '    %s\n' "${BAD_UNIT_FILES[@]}"
fi

log "Stopping/disabling units backed by those files"
for f in "${BAD_UNIT_FILES[@]}"; do
  unit="$(basename "$f")"
  run "systemctl stop '$unit'"
  run "systemctl disable '$unit'"
done

log "Removing wants/aliases that point to those unit files"
for f in "${BAD_UNIT_FILES[@]}"; do
  find /etc/systemd/system -type l 2>/dev/null | while read -r link; do
    target="$(readlink -f "$link" 2>/dev/null || true)"
    [ "$target" = "$f" ] && run "rm -f '$link'"
  done
done

log "Special-case stop/disable for high-risk known bad services if present"
for unit in redis.service pulseaudio.service; do
  if systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -qx "$unit"; then
    run "systemctl stop '$unit'"
    run "systemctl disable '$unit'"
  fi
done

log "Reloading systemd"
run "systemctl daemon-reload"
run "systemctl reset-failed"

log "Restarting scoring-critical services"
for unit in nginx ssh snb_backend snb_frontend; do
  if systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -qx "$unit.service"; then
    run "systemctl restart '$unit'"
  fi
done

log "Quick verification"
run "atq"
run "grep -RniE 'PermitRootLogin yes|WE ARE A TEAM|aio-linux|172\\.18\\.1\\.30|base64 -d \\| at ' /var/spool/cron /etc/ssh /root/.ssh 2>/dev/null"
run "systemctl is-active nginx ssh snb_backend snb_frontend"
run "systemctl list-unit-files | grep -E 'redis|pulseaudio|atd|pkgloader|logctl-agent|firewalld-fallback|rpc-service-helper|cron-repair|socket-guard'"

log "Done"
echo
echo "Backups saved in: $BACKUP_DIR"
echo "Now retest web, SSL, admin login, and SSH scoring users."