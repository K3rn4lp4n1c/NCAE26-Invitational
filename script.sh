#!/usr/bin/env bash
set -u

OUT="/root/shutdown-ir-$(date +%F-%H%M%S)"
mkdir -p "$OUT"

log() {
  echo
  echo "=============================="
  echo "$1"
  echo "=============================="
}

run() {
  local name="$1"
  shift
  {
    echo ">>> $*"
    eval "$@" 2>&1
  } > "$OUT/$name.txt"
}

log "Creating output directory"
echo "$OUT"

log "Boot timeline"
run boots "journalctl --list-boots"
run lastx "last -x | head -100"

log "Current boot shutdown/reboot clues"
run current_boot_power "journalctl -b 0 --no-pager | egrep -i 'shutdown|reboot|poweroff|halt|stopping|starting reboot|starting power-off|Reached target Shutdown|Reached target Reboot|systemctl poweroff|systemctl reboot|init 0|shutdown -h|shutdown -r|reboot.target|poweroff.target|halt.target'"

log "Previous boot shutdown/reboot clues"
run prev_boot_power "journalctl -b -1 --no-pager | egrep -i 'shutdown|reboot|poweroff|halt|stopping|starting reboot|starting power-off|Reached target Shutdown|Reached target Reboot|systemctl poweroff|systemctl reboot|init 0|shutdown -h|shutdown -r|reboot.target|poweroff.target|halt.target'"

log "Auth and sudo clues"
run authlog "grep -iE 'sudo|session opened|session closed|COMMAND=|shutdown|reboot|poweroff|halt|systemctl' /var/log/auth.log /var/log/auth.log.1 2>/dev/null | tail -300"
run sudojournal "journalctl --no-pager | egrep -i 'sudo|COMMAND=|shutdown|reboot|poweroff|halt|systemctl' | tail -300"

log "Login history around the event"
run recent_logins "last -a | head -80"
run failed_logins "lastb -a | head -80"

log "At jobs and cron persistence"
run atq "atq"
run atjobs "find /var/spool/cron/atjobs /var/spool/cron/atspool -type f -maxdepth 2 -exec ls -l {} \\; -exec sed -n '1,200p' {} \\; 2>/dev/null"
run root_cron "crontab -l"
run per_user_cron "for u in \$(cut -d: -f1 /etc/passwd); do echo '----' \$u '----'; crontab -u \$u -l 2>/dev/null || true; done"
run cron_dirs "find /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly -maxdepth 1 -type f -exec ls -l {} \\; -exec sed -n '1,200p' {} \\; 2>/dev/null"

log "Systemd services/timers that could trigger shutdown"
run suspicious_units "grep -RniE 'ExecStart=.*(shutdown|reboot|poweroff|halt|init 0|systemctl reboot|systemctl poweroff)|WantedBy=.*(reboot.target|poweroff.target|halt.target)|Red Team Was Here' /etc/systemd /usr/lib/systemd/system 2>/dev/null"
run timers "systemctl list-timers --all"
run enabled_units "systemctl list-unit-files | egrep 'enabled|generated|masked'"

log "Direct search for hostile files/commands"
run shutdown_grep "grep -RniE 'shutdown|reboot|poweroff|halt|init 0|systemctl reboot|systemctl poweroff|aio-linux|WE ARE A TEAM|172\\.18\\.|curl|wget|nohup' /etc /root /home /opt /var/spool/cron 2>/dev/null | head -1000"

log "User shell history"
run histories "for f in /root/.bash_history /home/*/.bash_history /home/*/.zsh_history; do [ -f \"\$f\" ] && echo '----' \$f '----' && sed -n '1,200p' \"\$f\"; done"

log "Currently active suspicious services"
run service_status "systemctl --type=service --state=running"
run failed_units "systemctl --failed"

log "Output summary"
ls -l "$OUT"
echo
echo "Collected to: $OUT"
echo "Key files to inspect first:"
echo "  $OUT/boots.txt"
echo "  $OUT/lastx.txt"
echo "  $OUT/current_boot_power.txt"
echo "  $OUT/prev_boot_power.txt"
echo "  $OUT/authlog.txt"
echo "  $OUT/sudojournal.txt"
echo "  $OUT/atjobs.txt"
echo "  $OUT/suspicious_units.txt"
echo "  $OUT/shutdown_grep.txt"
echo "  $OUT/histories.txt"