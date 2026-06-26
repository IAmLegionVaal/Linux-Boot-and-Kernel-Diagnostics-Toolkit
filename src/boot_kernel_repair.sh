#!/usr/bin/env bash
set -u

REBUILD_INITRAMFS=false
UPDATE_BOOTLOADER=false
SERVICE=""
ENABLE_SERVICE=false
RESET_FAILED=false
DRY_RUN=false
ASSUME_YES=false
OUTPUT_DIR=""
FAILURES=0
ACTIONS=0

usage() {
  cat <<'EOF'
Usage: boot_kernel_repair.sh [options]

  --rebuild-initramfs       Rebuild installed initramfs images.
  --update-bootloader       Regenerate the GRUB configuration.
  --service UNIT            Restart and verify one boot-related systemd unit.
  --enable-service          Enable the selected unit while repairing it.
  --reset-failed            Clear failed systemd unit state.
  --dry-run                 Show commands without changing the system.
  --yes                     Skip confirmation prompts.
  --output DIR              Save logs and before/after evidence in DIR.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --rebuild-initramfs) REBUILD_INITRAMFS=true; shift ;;
    --update-bootloader) UPDATE_BOOTLOADER=true; shift ;;
    --service) SERVICE="${2:-}"; shift 2 ;;
    --enable-service) ENABLE_SERVICE=true; shift ;;
    --reset-failed) RESET_FAILED=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if ! $REBUILD_INITRAMFS && ! $UPDATE_BOOTLOADER && [ -z "$SERVICE" ] && ! $RESET_FAILED; then echo "Choose at least one repair action." >&2; exit 2; fi
command -v systemctl >/dev/null 2>&1 || { echo "systemd is required." >&2; exit 3; }
if [ -n "$SERVICE" ]; then systemctl cat "$SERVICE" >/dev/null 2>&1 || { echo "Unit not found: $SERVICE" >&2; exit 2; }; fi
if $ENABLE_SERVICE && [ -z "$SERVICE" ]; then echo "--enable-service requires --service UNIT." >&2; exit 2; fi

STAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="${OUTPUT_DIR:-./boot-kernel-repair-$STAMP}"
BACKUP_DIR="$OUTPUT_DIR/backup"
mkdir -p "$OUTPUT_DIR" "$BACKUP_DIR"
LOG="$OUTPUT_DIR/repair.log"
BEFORE="$OUTPUT_DIR/before.txt"
AFTER="$OUTPUT_DIR/after.txt"
: > "$LOG"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
confirm() { $ASSUME_YES && return 0; read -r -p "$1 [y/N]: " answer; case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac; }
run_action() {
  local description="$1"; shift
  ACTIONS=$((ACTIONS + 1)); log "$description"
  if $DRY_RUN; then
    {
      printf 'DRY-RUN:'
      printf ' %q' "$@"
      printf '\n'
    } >> "$LOG"
    return 0
  fi
  if "$@" >> "$LOG" 2>&1; then log "SUCCESS: $description"; return 0; fi
  FAILURES=$((FAILURES + 1)); log "WARNING: $description failed"; return 1
}
run_root() { local description="$1"; shift; if [ "$(id -u)" -eq 0 ]; then run_action "$description" "$@"; else run_action "$description" sudo "$@"; fi; }
collect_state() {
  local destination="$1"
  {
    echo "Collected: $(date -Is)"
    uname -a
    cat /proc/cmdline 2>/dev/null || true
    echo
    systemctl --failed --no-pager 2>/dev/null || true
    echo
    systemd-analyze time 2>/dev/null || true
    echo
    ls -lh /boot 2>/dev/null || true
    echo
    journalctl -b -p err --no-pager -n 150 2>/dev/null || true
    if [ -n "$SERVICE" ]; then echo; systemctl status "$SERVICE" --no-pager -l 2>&1 || true; fi
  } > "$destination"
}

collect_state "$BEFORE"
if [ -f /etc/default/grub ]; then
  cp -a /etc/default/grub "$BACKUP_DIR/grub-default" 2>/dev/null || true
fi
confirm "Apply the selected boot and kernel repair actions? A reboot may be required afterward." || { log "Repair cancelled."; exit 10; }

if $RESET_FAILED; then run_root "Clearing failed systemd unit state" systemctl reset-failed || true; fi

if [ -n "$SERVICE" ]; then
  run_root "Reloading systemd unit files" systemctl daemon-reload || true
  run_root "Clearing failed state for $SERVICE" systemctl reset-failed "$SERVICE" || true
  if $ENABLE_SERVICE; then run_root "Enabling and starting $SERVICE" systemctl enable --now "$SERVICE" || true; else run_root "Restarting $SERVICE" systemctl restart "$SERVICE" || true; fi
fi

if $REBUILD_INITRAMFS; then
  if command -v update-initramfs >/dev/null 2>&1; then
    run_root "Rebuilding initramfs images" update-initramfs -u -k all || true
  elif command -v dracut >/dev/null 2>&1; then
    run_root "Rebuilding initramfs with dracut" dracut -f --regenerate-all || true
  elif command -v mkinitcpio >/dev/null 2>&1; then
    run_root "Rebuilding initramfs with mkinitcpio" mkinitcpio -P || true
  else
    FAILURES=$((FAILURES + 1)); log "WARNING: supported initramfs tool not found."
  fi
fi

if $UPDATE_BOOTLOADER; then
  if command -v update-grub >/dev/null 2>&1; then
    run_root "Regenerating GRUB configuration" update-grub || true
  elif command -v grub2-mkconfig >/dev/null 2>&1; then
    GRUB_OUTPUT=""
    [ -e /boot/grub2/grub.cfg ] && GRUB_OUTPUT=/boot/grub2/grub.cfg
    [ -z "$GRUB_OUTPUT" ] && [ -e /etc/grub2.cfg ] && GRUB_OUTPUT=$(readlink -f /etc/grub2.cfg)
    [ -z "$GRUB_OUTPUT" ] && [ -e /etc/grub2-efi.cfg ] && GRUB_OUTPUT=$(readlink -f /etc/grub2-efi.cfg)
    if [ -n "$GRUB_OUTPUT" ]; then run_root "Regenerating GRUB configuration at $GRUB_OUTPUT" grub2-mkconfig -o "$GRUB_OUTPUT" || true; else FAILURES=$((FAILURES + 1)); log "WARNING: GRUB output path could not be determined."; fi
  elif command -v grub-mkconfig >/dev/null 2>&1; then
    run_root "Regenerating GRUB configuration" grub-mkconfig -o /boot/grub/grub.cfg || true
  else
    FAILURES=$((FAILURES + 1)); log "WARNING: supported GRUB configuration tool not found."
  fi
fi

$DRY_RUN || sleep 2
collect_state "$AFTER"
if [ -n "$SERVICE" ]; then systemctl is-active --quiet "$SERVICE" || { FAILURES=$((FAILURES + 1)); log "WARNING: $SERVICE is not active after repair."; }; fi
if [ "$FAILURES" -gt 0 ]; then exit 20; fi
log "Repair completed successfully. Actions performed: $ACTIONS. Review whether a reboot is required."
exit 0
