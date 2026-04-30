#!/bin/bash
# tmux status bar — system info for Linux (including WSL)
# Called by tmux every status-interval seconds

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"

sample_net() {
    local net_down=0 net_up=0 iface dir name rx tx
    for iface in /sys/class/net/*/statistics; do
        [[ -d "$iface" ]] || continue
        dir=$(dirname "$iface")
        name=$(basename "$dir")
        [[ "$name" == "lo" ]] && continue
        rx=$(cat "$iface/rx_bytes" 2>/dev/null) || continue
        tx=$(cat "$iface/tx_bytes" 2>/dev/null) || continue
        net_down=$(( net_down + rx ))
        net_up=$(( net_up + tx ))
    done
    printf '%s %s\n' "$net_down" "$net_up"
}

# Network sample 1 — paired with the CPU sample sleep below.
read -r net_down_1 net_up_1 < <(sample_net)

# CPU — from /proc/stat (1-second sample)
read -r _ u1 n1 s1 i1 _ < /proc/stat
sleep 1
read -r _ u2 n2 s2 i2 _ < /proc/stat
read -r net_down_2 net_up_2 < <(sample_net)

idle=$((i2 - i1))
total=$(( (u2+n2+s2+i2) - (u1+n1+s1+i1) ))
if (( total > 0 )); then
    cpu=$(( 100 * (total - idle) / total ))
else
    cpu=0
fi

# Memory — from /proc/meminfo
mem_total_kb=$(awk '/^MemTotal/ {print $2}' /proc/meminfo)
mem_avail_kb=$(awk '/^MemAvailable/ {print $2}' /proc/meminfo)
mem_total_gb=$(awk "BEGIN {printf \"%.0f\", $mem_total_kb / 1048576}")
mem_used_gb=$(awk "BEGIN {printf \"%.0f\", ($mem_total_kb - $mem_avail_kb) / 1048576}")
mem="${mem_used_gb}/${mem_total_gb}GB"

# Network — from /sys/class/net (1-second delta matches CPU sample)
net_down=$(( net_down_2 - net_down_1 ))
net_up=$(( net_up_2 - net_up_1 ))

format_bytes() {
    local b=$1 dir=$2
    if (( b > 1048576 )); then
        awk "BEGIN {printf \"%.1fMB%s\", $b/1048576, \"$dir\"}"
    elif (( b > 1024 )); then
        awk "BEGIN {printf \"%.0fkB%s\", $b/1024, \"$dir\"}"
    else
        printf "0B%s" "$dir"
    fi
}

net="$(format_bytes $net_down '↓') $(format_bytes $net_up '↑')"

# Battery — from /sys/class/power_supply or upower
batt_str=""
if [[ -d /sys/class/power_supply/BAT0 ]]; then
    capacity=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null)
    status=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null)
    if [[ -n "$capacity" ]]; then
        if [[ "$status" == "Charging" || "$status" == "Full" ]]; then
            batt_str="AC:${capacity}%"
        else
            batt_str="DC:${capacity}%"
        fi
    fi
fi

# Output
out="CPU:${cpu}%  MEM:${mem}  NET:${net}"
[[ -n "$batt_str" ]] && out+="  ${batt_str}"
echo "$out"
