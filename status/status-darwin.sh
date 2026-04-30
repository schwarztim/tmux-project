#!/bin/bash
# tmux status bar — system info for macOS
# Called by tmux every status-interval seconds

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"

# CPU — average across cores
cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
cpu=$(ps -A -o %cpu | awk -v c="$cores" '{s+=$1} END {printf "%.0f", s / c}')

# Memory — used/total
mem_used=$(memory_pressure 2>/dev/null | awk '/percentage/{gsub(/%/,"",$5); print $5; exit}')
mem_total=$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f", $1/1073741824}')
if [[ -n "$mem_used" ]]; then
    mem_gb=$(awk "BEGIN {printf \"%.0f\", $mem_total * $mem_used / 100}")
    mem="${mem_gb}/${mem_total}GB"
else
    mem="${mem_total}GB"
fi

# Network — bytes via nettop snapshot
net=$(nettop -P -L 1 -J bytes_in,bytes_out -t wifi -t wired 2>/dev/null | awk -F, '
    NR>1 && $2 != "" {din+=$2; dout+=$3}
    END {
        if (din > 1048576) printf "%.1fMB↓ ", din/1048576
        else if (din > 1024) printf "%.0fkB↓ ", din/1024
        else printf "0B↓ "
        if (dout > 1048576) printf "%.1fMB↑", dout/1048576
        else if (dout > 1024) printf "%.0fkB↑", dout/1024
        else printf "0B↑"
    }')

# Battery
batt=$(pmset -g batt 2>/dev/null | grep -o '[0-9]*%' | head -1)
charging=$(pmset -g batt 2>/dev/null | grep -c 'AC Power')
if [[ -n "$batt" ]]; then
    if [[ "$charging" -gt 0 ]]; then
        batt_str="AC:${batt}"
    else
        batt_str="DC:${batt}"
    fi
else
    batt_str=""
fi

# Output
out="CPU:${cpu}%  MEM:${mem}  NET:${net}"
[[ -n "$batt_str" ]] && out+="  ${batt_str}"
echo "$out"
