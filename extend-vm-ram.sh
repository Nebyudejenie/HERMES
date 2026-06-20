#!/usr/bin/env bash
#
# extend-vm-ram.sh — safely resize a libvirt/KVM guest's RAM.
# RUN ON THE KVM HOST (e.g. cosmicServer), not inside the VM.
#
# Default: set the 'hermis-ubuntu-ai' domain to 28 GB (leaving ~4 GB for the
# host). The guest uses virtio-balloon with mem-lock=off, so this is a CEILING:
# the host only backs pages the guest actually touches.
#
# Safe, reversible: backs up the domain XML + current memory, graceful shutdown,
# sets maxMemory + current memory offline, restarts, and prints a rollback.
#
set -euo pipefail

DOMAIN="${1:-hermis-ubuntu-ai}"
NEW_RAM_GB="${NEW_RAM_GB:-28}"
MIN_HOST_GB="${MIN_HOST_GB:-3}"     # refuse if the host would keep less than this
SHUTDOWN_WAIT="${SHUTDOWN_WAIT:-120}"

C_G='\033[0;32m'; C_Y='\033[1;33m'; C_R='\033[0;31m'; C_B='\033[0;34m'; C_N='\033[0m'
say(){ echo -e "${C_B}[*]${C_N} $*"; }
ok(){ echo -e "${C_G}[✓]${C_N} $*"; }
warn(){ echo -e "${C_Y}[!]${C_N} $*"; }
die(){ echo -e "${C_R}[✗]${C_N} $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root (sudo bash extend-vm-ram.sh)."
command -v virsh >/dev/null 2>&1 || die "virsh not found — run this on the KVM host."

# ---- resolve domain -------------------------------------------------------
if ! virsh dominfo "$DOMAIN" >/dev/null 2>&1; then
    warn "Domain '$DOMAIN' not found. Available domains:"
    virsh list --all
    die "Pass the right name:  sudo bash extend-vm-ram.sh <domain-name>"
fi

NEW_KIB=$(( NEW_RAM_GB * 1048576 ))
HOST_TOTAL_KIB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
HOST_TOTAL_GB=$(( HOST_TOTAL_KIB / 1048576 ))
LEFT_GB=$(( HOST_TOTAL_GB - NEW_RAM_GB ))
CUR_KIB=$(virsh dominfo "$DOMAIN" | awk '/Max memory/{print $3}')
CUR_GB=$(( CUR_KIB / 1048576 ))

echo -e "${C_B}╔══════════════════════════════════════════════╗${C_N}"
echo -e "${C_B}║  KVM VM RAM Resizer                          ║${C_N}"
echo -e "${C_B}╚══════════════════════════════════════════════╝${C_N}"
say "Domain:        $DOMAIN"
say "Host RAM:      ${HOST_TOTAL_GB} GB total"
say "Current VM:    ${CUR_GB} GB  ->  New VM: ${NEW_RAM_GB} GB"
say "Host left:     ${LEFT_GB} GB (floor: ${MIN_HOST_GB} GB)"
echo

[ "$LEFT_GB" -ge "$MIN_HOST_GB" ] || die "Refusing: host would keep only ${LEFT_GB} GB (< ${MIN_HOST_GB} GB). Lower NEW_RAM_GB."
if [ "$NEW_KIB" -le "$CUR_KIB" ]; then
    ok "VM already at ${CUR_GB} GB (>= requested). Nothing to do."
    exit 0
fi

# ---- backup for rollback --------------------------------------------------
ts=$(date +%Y%m%d-%H%M%S)
backup="/root/hermis-vm-${DOMAIN}-${ts}.xml"
virsh dumpxml "$DOMAIN" > "$backup"
ok "Backed up domain XML -> $backup  (old max memory: ${CUR_GB} GB)"

# ---- graceful shutdown ----------------------------------------------------
state=$(virsh domstate "$DOMAIN" 2>/dev/null || echo unknown)
if [ "$state" = "running" ]; then
    say "Gracefully shutting down '$DOMAIN' (up to ${SHUTDOWN_WAIT}s)..."
    virsh shutdown "$DOMAIN" >/dev/null 2>&1 || true
    for i in $(seq 1 "$SHUTDOWN_WAIT"); do
        [ "$(virsh domstate "$DOMAIN" 2>/dev/null)" = "shut off" ] && break
        sleep 1
    done
    if [ "$(virsh domstate "$DOMAIN" 2>/dev/null)" != "shut off" ]; then
        warn "Guest did not power off in time; forcing off."
        virsh destroy "$DOMAIN" >/dev/null 2>&1 || true
        sleep 2
    fi
fi
ok "VM is powered off."

# ---- apply new memory (offline, persistent) -------------------------------
say "Setting maxMemory and current memory to ${NEW_RAM_GB} GB..."
if ! virsh setmaxmem "$DOMAIN" "${NEW_KIB}" --config; then
    warn "setmaxmem failed — restoring original definition."
    virsh define "$backup" >/dev/null && virsh start "$DOMAIN" >/dev/null 2>&1 || true
    die "Aborted; VM restored to ${CUR_GB} GB."
fi
virsh setmem "$DOMAIN" "${NEW_KIB}" --config || warn "setmem (current) failed; max set OK."

# ---- restart and verify ---------------------------------------------------
say "Starting '$DOMAIN'..."
if ! virsh start "$DOMAIN" >/dev/null 2>&1; then
    warn "VM failed to start with new RAM — rolling back."
    virsh define "$backup" >/dev/null
    virsh start "$DOMAIN" >/dev/null 2>&1 || true
    die "Rolled back to ${CUR_GB} GB (from $backup)."
fi

sleep 3
NEW_MAX_GB=$(( $(virsh dominfo "$DOMAIN" | awk '/Max memory/{print $3}') / 1048576 ))
echo
ok "Done. '$DOMAIN' max memory is now ${NEW_MAX_GB} GB and the VM is running."
echo
echo "Verify inside the VM:   free -h"
echo "Rollback if needed:     virsh shutdown $DOMAIN && virsh define $backup && virsh start $DOMAIN"
