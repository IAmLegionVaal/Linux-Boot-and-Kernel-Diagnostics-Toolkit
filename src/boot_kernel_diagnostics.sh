#!/usr/bin/env bash
set -u

HOURS=24
OUTPUT_DIR=""

usage() {
  echo "Usage: boot_kernel_diagnostics.sh [--hours N] [--output DIR]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hours) HOURS="${2:-24}"; shift 2 ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ "$HOURS" =~ ^[0-9]+$ ]] || { echo "--hours must be numeric" >&2; exit 2; }

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./boot-kernel-diagnostics-$STAMP}"
mkdir -p "$OUTPUT_DIR"
REPORT="$OUTPUT_DIR/boot-kernel-report.txt"
CSV="$OUTPUT_DIR/failed-units.csv"
JSON="$OUTPUT_DIR/summary.json"
ERRORS="$OUTPUT_DIR/command-errors.log"
: > "$REPORT"
: > "$ERRORS"

echo 'unit,load,active,sub,description' > "$CSV"

section() {
  local title="$1"
  shift
  {
    printf '\n===== %s =====\n' "$title"
    "$@"
  } >> "$REPORT" 2>> "$ERRORS" || true
}

have() { command -v "$1" >/dev/null 2>&1; }

section "Collection metadata" bash -c 'date -Is; hostname -f 2>/dev/null || hostname; cat /etc/os-release 2>/dev/null || true; uname -a; uptime'
section "Kernel command line" cat /proc/cmdline
section "Current boot ID" cat /proc/sys/kernel/random/boot_id
section "Boot history" bash -c 'journalctl --list-boots --no-pager 2>/dev/null || true'

if have systemd-analyze; then
  section "Boot time" systemd-analyze time
  section "Boot blame" systemd-analyze blame
  section "Critical chain" systemd-analyze critical-chain
fi

if have systemctl; then
  section "Failed units" systemctl --failed --no-pager -l
  systemctl --failed --no-legend --plain 2>/dev/null | while read -r unit load active sub description; do
    [[ -z "$unit" ]] && continue
    description="${description//\"/\"\"}"
    printf '"%s","%s","%s","%s","%s"\n' "$unit" "$load" "$active" "$sub" "$description" >> "$CSV"
  done
  section "Default target" systemctl get-default
fi

if have journalctl; then
  section "Current boot errors" journalctl -b -p 0..3 --no-pager -n 500
  section "Current boot warnings" journalctl -b -p 0..4 --no-pager -n 1000
  section "Previous boot errors" journalctl -b -1 -p 0..3 --no-pager -n 500
  section "Recent kernel events" journalctl -k --since "$HOURS hours ago" --no-pager -n 1000
  section "Driver, firmware and hardware indicators" bash -c "journalctl -k --since '$HOURS hours ago' --no-pager 2>/dev/null | grep -Ei 'firmware|failed to load|module verification|acpi|pci.*error|mce|machine check|watchdog|nvme|ata[0-9]|I/O error|link is down|renamed from|oom-killer|out of memory' | tail -n 1000 || true"
fi

if have dmesg; then
  section "Kernel warning and error ring buffer" bash -c 'dmesg --level=emerg,alert,crit,err,warn 2>/dev/null || dmesg 2>/dev/null | grep -Ei "error|fail|warn|timeout|reset" | tail -n 1000 || true'
fi

section "Kernel taint and panic settings" bash -c 'printf "Taint: "; cat /proc/sys/kernel/tainted 2>/dev/null || true; sysctl kernel.panic kernel.panic_on_oops 2>/dev/null || true'
section "Loaded modules" bash -c 'lsmod 2>/dev/null || true'
section "Initramfs inventory" bash -c 'ls -lh /boot/initr* /boot/initramfs* 2>/dev/null || true'
section "Kernel images" bash -c 'ls -lh /boot/vmlinuz* /boot/kernel* 2>/dev/null || true'
section "GRUB inventory" bash -c 'ls -l /etc/default/grub /boot/grub*/grub.cfg 2>/dev/null || true; sed -n "1,200p" /etc/default/grub 2>/dev/null || true'
section "CPU and firmware context" bash -c 'lscpu 2>/dev/null || true; dmidecode -t bios -t system 2>/dev/null || true'

FAILED_UNITS="$(awk 'END {print NR-1}' "$CSV")"
CURRENT_ERRORS=0
PREVIOUS_ERRORS=0
BOOT_SECONDS="null"
TAINT="$(cat /proc/sys/kernel/tainted 2>/dev/null || echo 0)"

if have journalctl; then
  CURRENT_ERRORS="$(journalctl -b -p 0..3 --no-pager 2>/dev/null | sed '/^-- No entries --$/d;/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
  PREVIOUS_ERRORS="$(journalctl -b -1 -p 0..3 --no-pager 2>/dev/null | sed '/^-- No entries --$/d;/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
fi

if have systemd-analyze; then
  userspace="$(systemd-analyze time 2>/dev/null | sed -n 's/.*+ \([0-9.]*\)s (userspace).*/\1/p')"
  [[ -n "$userspace" ]] && BOOT_SECONDS="$userspace"
fi

OVERALL="Healthy"
if [[ "${FAILED_UNITS:-0}" -gt 0 || "${CURRENT_ERRORS:-0}" -gt 0 || "${TAINT:-0}" -ne 0 ]]; then
  OVERALL="Attention required"
fi

cat > "$JSON" <<EOF
{
  "collected_at": "$(date -Is)",
  "hostname": "$(hostname -f 2>/dev/null || hostname)",
  "kernel": "$(uname -r)",
  "failed_units": ${FAILED_UNITS:-0},
  "current_boot_error_entries": ${CURRENT_ERRORS:-0},
  "previous_boot_error_entries": ${PREVIOUS_ERRORS:-0},
  "kernel_taint_value": ${TAINT:-0},
  "userspace_boot_seconds": $BOOT_SECONDS,
  "overall_status": "$OVERALL"
}
EOF

printf '\nBoot and kernel diagnostics completed: %s\n' "$OUTPUT_DIR" | tee -a "$REPORT"
