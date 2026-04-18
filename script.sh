#!/usr/bin/env bash
set -u

OUT="/root/nginx-port-ir-$(date +%F-%H%M%S)"
mkdir -p "$OUT"

section() {
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

section "Output directory"
echo "$OUT"

section "1) Current listeners and nginx processes"
run listeners "sudo lsof -iTCP -sTCP:LISTEN -nP | egrep 'nginx|:80|:443|:444|:8443|:3000|:8000|:9090'"
run ss_ports "sudo ss -ltnp | egrep ':80 |:443 |:444 |:8443 |:3000 |:8000 |:9090 '"
run ps_nginx "ps auxww | egrep '[n]ginx|[u]vicorn|[n]ext-server'"

section "2) Full nginx config and listen directives"
run nginx_test "sudo nginx -t"
run nginx_dump "sudo nginx -T"
run nginx_listen_grep "sudo nginx -T 2>/dev/null | egrep -n 'listen|server_name|ssl_certificate|ssl_certificate_key|proxy_pass|return 301|return 302|rewrite'"
run nginx_file_grep "sudo grep -RniE 'listen .*443|listen .*444|listen .*8443|server_name|ssl_certificate|ssl_certificate_key|proxy_pass|return 301|return 302|rewrite' /etc/nginx 2>/dev/null"

section "3) Nginx file metadata and recent changes"
run nginx_find "sudo find /etc/nginx -type f -printf '%TY-%Tm-%Td %TH:%TM:%TS %u:%g %m %p\n' | sort"
run nginx_recent "sudo find /etc/nginx -type f -mtime -7 -ls"
run nginx_stat "sudo find /etc/nginx -type f -exec stat -c '%n | size=%s | perms=%a | owner=%U:%G | mtime=%y | ctime=%z' {} \; | sort"

section "4) Package ownership and integrity for nginx service/config"
run dpkg_nginx "dpkg -S /usr/lib/systemd/system/nginx.service /etc/nginx 2>/dev/null"
run debsums_nginx "sudo debsums -c nginx-common nginx-core nginx-full nginx 2>/dev/null"
run nginx_service_cat "sudo systemctl cat nginx"
run nginx_service_file "sudo sed -n '1,220p' /usr/lib/systemd/system/nginx.service"

section "5) Journal and log evidence around nginx/port changes"
run journal_nginx "sudo journalctl -u nginx --no-pager | tail -400"
run journal_ports "sudo journalctl --no-pager | egrep -i 'nginx|443|444|8443|listen|sites-enabled|sites-available|ssl' | tail -500"
run authlog_nginx "sudo grep -iE 'nginx|443|444|8443|sites-enabled|sites-available|sed |perl |python |tee ' /var/log/auth.log /var/log/auth.log.1 2>/dev/null | tail -400"
run syslog_nginx "sudo grep -iE 'nginx|443|444|8443|sites-enabled|sites-available|listen|ssl' /var/log/syslog /var/log/syslog.1 2>/dev/null | tail -400"

section "6) Shell history for nginx/444 changes"
run histories_nginx "for f in /root/.bash_history /root/.zsh_history /home/*/.bash_history /home/*/.zsh_history; do [ -f \"$f\" ] && echo \"---- $f ----\" && grep -niE 'nginx|444|8443|443|sites-enabled|sites-available|ssl_certificate|listen |sed -i|perl -pi|systemctl reload nginx|systemctl restart nginx|nginx -t' \"$f\"; done"

section "7) Cron, at, and systemd persistence mentioning nginx/ports"
run cron_nginx "sudo grep -RniE 'nginx|443|444|8443|sites-enabled|sites-available|ssl' /etc/cron* /var/spool/cron 2>/dev/null"
run atjobs_nginx "sudo find /var/spool/cron/atjobs /var/spool/cron/atspool -type f -maxdepth 2 -exec grep -HniE 'nginx|443|444|8443|sites-enabled|sites-available|ssl' {} \; 2>/dev/null"
run systemd_nginx_refs "sudo grep -RniE 'nginx|443|444|8443|sites-enabled|sites-available|ssl' /etc/systemd /usr/lib/systemd/system 2>/dev/null"

section "8) Firewall / NAT / redirect rules that could move 443 to 444"
run nft_rules "sudo nft list ruleset 2>/dev/null | egrep -n '443|444|8443|redir|dnat|snat|redirect'"
run iptables_nat "sudo iptables -t nat -S 2>/dev/null | egrep '443|444|8443|REDIRECT|DNAT|SNAT'"
run iptables_filter "sudo iptables -S 2>/dev/null | egrep '443|444|8443'"
run ufw_status "sudo ufw status verbose"

section "9) Symlinks in nginx sites and suspicious replacements"
run nginx_symlinks "sudo find /etc/nginx -type l -exec ls -l {} \;"
run nginx_checksums "sudo find /etc/nginx -type f -exec sha256sum {} \; | sort"

section "10) Optional audit logs if auditd is present"
if command -v ausearch >/dev/null 2>&1; then
  run audit_nginx "sudo ausearch -f /etc/nginx -i 2>/dev/null | tail -400"
  run audit_nginx_service "sudo ausearch -f /usr/lib/systemd/system/nginx.service -i 2>/dev/null | tail -200"
else
  echo "ausearch not present" > "$OUT/audit_nginx.txt"
fi

section "11) Quick summary hints"
{
  echo "Likely first files to inspect:"
  echo "  $OUT/nginx_listen_grep.txt"
  echo "  $OUT/nginx_file_grep.txt"
  echo "  $OUT/nginx_recent.txt"
  echo "  $OUT/journal_nginx.txt"
  echo "  $OUT/authlog_nginx.txt"
  echo "  $OUT/histories_nginx.txt"
  echo "  $OUT/atjobs_nginx.txt"
  echo "  $OUT/systemd_nginx_refs.txt"
  echo "  $OUT/nft_rules.txt"
  echo "  $OUT/iptables_nat.txt"
  echo
  echo "Output directory:"
  echo "  $OUT"
} | tee "$OUT/README.txt"

echo
echo "Done. Evidence saved to: $OUT"