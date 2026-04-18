#!/usr/bin/env bash
set -u

OUT="/root/reboot-source-ir-$(date +%F-%H%M%S)"
mkdir -p "$OUT"

run() {
  local name="$1"
  shift
  {
    echo ">>> $*"
    eval "$@" 2>&1
  } > "$OUT/$name.txt"
}

echo "Saving to: $OUT"

run boots "journalctl --list-boots"
run lastx "last -x | head -120"

run current_boot_reboot "journalctl -b 0 --no-pager | egrep -i 'shutdown|reboot|poweroff|halt|systemctl reboot|systemctl poweroff|Reached target Shutdown|Reached target Reboot|Starting reboot|Starting power-off'"
run prev_boot_reboot "journalctl -b -1 --no-pager | egrep -i 'shutdown|reboot|poweroff|halt|systemctl reboot|systemctl poweroff|Reached target Shutdown|Reached target Reboot|Starting reboot|Starting power-off'"
run prev2_boot_reboot "journalctl -b -2 --no-pager | egrep -i 'shutdown|reboot|poweroff|halt|systemctl reboot|systemctl poweroff|Reached target Shutdown|Reached target Reboot|Starting reboot|Starting power-off'"

run authlog "grep -iE 'sudo|COMMAND=|shutdown|reboot|poweroff|halt|systemctl' /var/log/auth.log /var/log/auth.log.1 2>/dev/null | tail -500"
run sudojournal "journalctl --no-pager | egrep -i 'sudo|COMMAND=|shutdown|reboot|poweroff|halt|systemctl' | tail -500"

run suspicious_units "grep -RniE 'reboot|poweroff|halt|shutdown|systemctl reboot|systemctl poweroff|init 0' /etc/systemd/system /usr/lib/systemd/system /etc /opt 2>/dev/null | head -1500"
run unit_files "systemctl list-unit-files | egrep 'securebootmgr|firewalld-fallback|logctl-agent|pkgloader|rpc-service-helper|cron-repair|socket-guard|netfilter-wrap|bios-updater|vault-mirror|timetrackd|sysstartupd|dnsmonitord|modtrackd|mountwatchd|authwatchd|fswatcherd|pkgcached'"
run securebootmgr "systemctl cat securebootmgr.service 2>/dev/null; echo; systemctl status securebootmgr.service --no-pager 2>/dev/null"

run apt_hooks "find /etc/apt/apt.conf.d -maxdepth 1 -type f -exec ls -l {} \; -exec sed -n '1,220p' {} \; 2>/dev/null"
run cron_at "find /var/spool/cron /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly -type f -exec ls -l {} \; -exec sed -n '1,220p' {} \; 2>/dev/null"
run histories "for f in /root/.bash_history /home/*/.bash_history; do [ -f \"$f\" ] && echo \"---- $f ----\" && grep -niE 'shutdown|reboot|poweroff|halt|systemctl' \"$f\"; done"

run postgres_journal "journalctl -u postgresql --no-pager | tail -300"

echo
echo "Done. Read these first:"
echo "  $OUT/lastx.txt"
echo "  $OUT/current_boot_reboot.txt"
echo "  $OUT/prev_boot_reboot.txt"
echo "  $OUT/prev2_boot_reboot.txt"
echo "  $OUT/authlog.txt"
echo "  $OUT/sudojournal.txt"
echo "  $OUT/suspicious_units.txt"
echo "  $OUT/securebootmgr.txt"
echo "  $OUT/apt_hooks.txt"
echo "  $OUT/histories.txt"