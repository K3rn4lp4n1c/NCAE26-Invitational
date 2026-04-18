#!/usr/bin/env bash
set -u

echo "========================================"
echo " NCAE Post-Cleanup Persistence Sweep"
echo "========================================"
echo

run() {
  echo
  echo ">>> $*"
  eval "$@" 2>/dev/null || true
}

echo "[1] SSH trust chain"
run "sudo grep -RniE 'PermitRootLogin|AuthorizedKeys|AuthorizedKeysCommand|PasswordAuthentication|PubkeyAuthentication' /etc/ssh /etc/ssh/sshd_config.d"
run "sudo find /home /root -maxdepth 4 -path '*/.ssh/*' -type f -exec ls -l {} \; -exec sed -n '1,50p' {} \;"

echo
echo "[2] Suspicious unit files and enabled leftovers"
run "sudo systemctl list-unit-files | egrep 'pkgloader|logctl-agent|firewalld-fallback|rpc-service-helper|cron-repair|socket-guard|netfilter-wrap|bios-updater|vault-mirror|timetrackd|sysstartupd|dnsmonitord|modtrackd|mountwatchd|authwatchd|fswatcherd|pkgcached|pulseaudio|redis'"
run "sudo find /etc/systemd/system -type l -ls"
run \"sudo find /etc/systemd/system /usr/lib/systemd/system -maxdepth 3 -type f | egrep 'pkgloader|logctl-agent|firewalld-fallback|rpc-service-helper|cron-repair|socket-guard|netfilter-wrap|bios-updater|vault-mirror|timetrackd|sysstartupd|dnsmonitord|modtrackd|mountwatchd|authwatchd|fswatcherd|pkgcached|pulseaudio|redis'\"

echo
echo "[3] Suspicious binaries and bad paths"
run "sudo ls -l /usr/bin/rangd /usr/local/bin/cmd_exec.so /var/tmp/ksession /opt/platform/runtime /opt/runtime/cachesyncd /sbin/mount.recoveryfs /var/lib/dbus/systemhelper /usr/local/sbin/fsintegrityd /usr/libexec/netlink-monitor"
run "sudo file /usr/bin/rangd /usr/local/bin/cmd_exec.so /var/tmp/ksession /opt/platform/runtime /opt/runtime/cachesyncd /sbin/mount.recoveryfs /var/lib/dbus/systemhelper /usr/local/sbin/fsintegrityd /usr/libexec/netlink-monitor"
run "sudo strings /usr/bin/rangd /var/tmp/ksession /opt/platform/runtime /opt/runtime/cachesyncd 2>/dev/null | head -100"

echo
echo "[4] Redis service and config"
run "sudo systemctl cat redis"
run "sudo lsof -i -P -n | grep 6379"
run "sudo find /etc/redis /var/lib/redis -maxdepth 2 -type f -exec ls -l {} \; -exec sed -n '1,120p' {} \;"

echo
echo "[5] Accounts, UID 0, sudoers, and logins"
run "awk -F: '\$3 == 0 {print}' /etc/passwd"
run "sudo cat /etc/passwd"
run "sudo cat /etc/group"
run "sudo grep -Rni '' /etc/sudoers /etc/sudoers.d"
run "sudo last -a | head -40"

echo
echo "[6] Shell startup and environment persistence"
run \"sudo grep -RniE 'curl|wget|nc |bash -i|nohup|python|perl|base64|172\\.18\\.1\\.30|aio-linux|WE ARE A TEAM' /root /home/*/.*shrc /home/*/.profile /etc/profile /etc/bash.bashrc /etc/environment\"
run "sudo ls -la /home/ansible /home/ansible/.ansible /root"

echo
echo "[7] Live sockets with trusted views"
run "sudo lsof -i -P -n"
run "cat /proc/net/tcp"
run "cat /proc/net/tcp6"
run "cat /proc/net/udp"
run "cat /proc/net/udp6"

echo
echo "[8] Web app, reverse proxy, and recent drift"
run "sudo find /etc/nginx /opt/frontend /opt/backend -type f -mtime -2 -ls"
run \"sudo grep -RniE '172\\.18\\.1\\.30|aio-linux|curl|wget|bash -c|nohup|subprocess|eval|pickle|cmd_exec|rangd' /etc/nginx /opt/frontend /opt/backend\"
run "sudo systemctl cat snb_frontend snb_backend nginx"

echo
echo "[9] atd really stayed dead"
run "systemctl is-enabled atd"
run "systemctl is-active atd"
run "atq"
run "sudo find /var/spool/cron/atjobs /var/spool/cron/atspool -type f -ls"

echo
echo "[10] Timers after cleanup"
run "sudo systemctl list-timers --all"
run \"sudo systemctl list-unit-files --type=timer --type=service | egrep 'certbot|logctl-agent|pkgloader|rpc-service-helper|firewalld-fallback|timed-resync'\"

echo
echo "========================================"
echo " Sweep complete"
echo "========================================"