#!/usr/bin/env bash
set -euo pipefail

# Allowed TCP ports
ALLOWED_PORTS=("22" "80" "443" "3000" "8000" "9090")

# Set to 0 to actually stop/disable/mask units
DRY_RUN=1

is_allowed_port() {
    local p="$1"
    for ap in "${ALLOWED_PORTS[@]}"; do
        [[ "$p" == "$ap" ]] && return 0
    done
    return 1
}

echo "[*] Collecting listening TCP sockets..."
mapfile -t listeners < <(ss -ltnpH | awk '{print $4 "|" $NF}')

declare -A units_to_disable=()

for line in "${listeners[@]}"; do
    addr="${line%%|*}"
    procinfo="${line#*|}"

    port="${addr##*:}"
    port="${port//[\[\]]/}"

    if is_allowed_port "$port"; then
        echo "[KEEP] port $port"
        continue
    fi

    pid="$(echo "$procinfo" | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | head -n1)"
    [[ -z "${pid:-}" ]] && continue

    unit="$(systemctl status "$pid" 2>/dev/null | sed -n 's/.*CGroup: .*\/\(.*\.service\).*/\1/p' | head -n1)"

    # Fallback: ask systemd directly
    if [[ -z "${unit:-}" ]]; then
        unit="$(ps -p "$pid" -o unit= 2>/dev/null | awk '{$1=$1;print}')"
    fi

    if [[ -z "${unit:-}" || "$unit" == "-" ]]; then
        echo "[WARN] Could not map pid $pid on port $port to a systemd service"
        continue
    fi

    units_to_disable["$unit"]=1
    echo "[MARK] port $port -> $unit"
done

echo
echo "[*] Units marked:"
for unit in "${!units_to_disable[@]}"; do
    echo "  $unit"
done

echo
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[DRY RUN] No changes made."
    echo "Set DRY_RUN=0 to apply."
    exit 0
fi

for unit in "${!units_to_disable[@]}"; do
    echo "[*] Stopping/disabling/masking $unit"
    sudo systemctl stop "$unit" || true
    sudo systemctl disable "$unit" || true
    sudo systemctl mask "$unit" || true
done

echo
echo "[*] Done. Remaining listeners:"
ss -ltnp