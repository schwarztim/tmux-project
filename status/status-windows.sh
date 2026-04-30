#!/bin/bash
# tmux status bar — system info for MSYS2/Git Bash on Windows
# Called by tmux every status-interval seconds
# Falls back to wmic/powershell for Windows-native metrics

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/mingw64/bin:$PATH"

# Detect if running in WSL — if so, use the Linux status script
if [[ -f /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    exec "$SCRIPT_DIR/status-linux.sh"
fi

# CPU — via wmic
cpu=$(wmic cpu get loadpercentage 2>/dev/null | awk 'NR==2 {gsub(/\r/,""); print $1}')
[[ -z "$cpu" ]] && cpu="?"

# Memory — via wmic
mem_info=$(wmic OS get FreePhysicalMemory,TotalVisibleMemorySize /value 2>/dev/null)
mem_total_kb=$(echo "$mem_info" | awk -F= '/TotalVisibleMemorySize/ {gsub(/\r/,""); print $2}')
mem_free_kb=$(echo "$mem_info" | awk -F= '/FreePhysicalMemory/ {gsub(/\r/,""); print $2}')
if [[ -n "$mem_total_kb" && -n "$mem_free_kb" ]]; then
    mem_total_gb=$(awk "BEGIN {printf \"%.0f\", $mem_total_kb / 1048576}")
    mem_used_gb=$(awk "BEGIN {printf \"%.0f\", ($mem_total_kb - $mem_free_kb) / 1048576}")
    mem="${mem_used_gb}/${mem_total_gb}GB"
else
    mem="?GB"
fi

# Network — simplified (no per-second delta on native Windows without perf counters)
net="N/A"

# Battery — via wmic
batt_info=$(wmic path Win32_Battery get EstimatedChargeRemaining,BatteryStatus 2>/dev/null)
batt_pct=$(echo "$batt_info" | awk 'NR==2 {gsub(/\r/,""); print $1}')
batt_status=$(echo "$batt_info" | awk 'NR==2 {gsub(/\r/,""); print $2}')
batt_str=""
if [[ -n "$batt_pct" && "$batt_pct" != "" ]]; then
    if [[ "$batt_status" == "2" ]]; then
        batt_str="AC:${batt_pct}%"
    else
        batt_str="DC:${batt_pct}%"
    fi
fi

# Output
out="CPU:${cpu}%  MEM:${mem}  NET:${net}"
[[ -n "$batt_str" ]] && out+="  ${batt_str}"
echo "$out"
