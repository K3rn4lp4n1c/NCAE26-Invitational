#!/usr/bin/env bash
set -u

echo "=============================="
echo " NCAE Cron and Timer Sweep"
echo "=============================="
echo

run() {
  echo
  echo ">>> $*"
  eval "$@" 2>/dev/null || true
}

echo "[1] Root crontab"
run "sudo crontab -l"

echo
echo "[2] Per-user crontabs"
while IFS=: read -r user _ uid _ _ home shell; do
  echo
  echo "---- $user ----"
  sudo crontab -u "$user" -l 2>/dev/null || echo "(no crontab)"
done < /etc/passwd

echo
echo "[3] Cron directories"
run "sudo ls -la /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly"

echo
echo "[4] Contents of cron directory files"
for d in /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly; do
  [ -d "$d" ] || continue
  echo
  echo "==== Directory: $d ===="
  find "$d" -maxdepth 1 -type f 2>/dev/null | while read -r f; do
    echo
    echo "---- FILE: $f ----"
    ls -l "$f" 2>/dev/null || true
    sed -n '1,200p' "$f" 2>/dev/null || true
  done
done

echo
echo "[5] Spool cron locations"
run "sudo ls -la /var/spool/cron /var/spool/cron/crontabs"

echo
echo "[6] Contents of spool cron files"
for d in /var/spool/cron /var/spool/cron/crontabs; do
  [ -d "$d" ] || continue
  echo
  echo "==== Directory: $d ===="
  find "$d" -type f 2>/dev/null | while read -r f; do
    echo
    echo "---- FILE: $f ----"
    ls -l "$f" 2>/dev/null || true
    sed -n '1,200p' "$f" 2>/dev/null || true
  done
done

echo
echo "[7] Suspicious patterns in cron locations"
run "sudo grep -RniE 'curl|wget|nc |ncat|bash -i|sh -i|python -c|perl -e|socat|/tmp/|/dev/shm|chmod \\+s|useradd|nohup|base64|openssl|php -r' /etc/cron* /var/spool/cron /var/spool/cron/crontabs"

echo
echo "[8] All systemd timers"
run "sudo systemctl list-timers --all"

echo
echo "[9] Enabled timer and service units"
run \"sudo systemctl list-unit-files --type=timer --type=service | grep enabled\"

echo
echo "[10] Suspicious systemd unit search"
run "sudo grep -RniE 'curl|wget|nc |ncat|bash -i|sh -i|python -c|perl -e|socat|/tmp/|/dev/shm|nohup|base64|ExecStart=' /etc/systemd /usr/lib/systemd/system"

echo
echo "=============================="
echo " Sweep complete"
echo "=============================="