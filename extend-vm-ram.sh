#!/usr/bin/env bash
#
# extend-vm-ram.sh — safely resize a VM's RAM. Works on BOTH backends:
#   • proxmox  -> qm    (identifier = numeric VMID)
#   • libvirt  -> virsh (identifier = domain name)
# Auto-detects which one this host uses. RUN ON THE HYPERVISOR HOST.
#
# Default target: 28 GB, leaving a host floor. Safe + reversible: records the
# old memory, graceful shutdown, sets memory, restarts, and rolls back if the
# VM won't start.
#
set -euo pipefail

TARGET="auto"                 # auto | proxmox | libvirt
VM=""                         # VMID (proxmox) or domain name (libvirt); auto if empty
NEW_RAM_GB="${NEW_RAM_GB:-28}"
MIN_HOST_GB="${MIN_HOST_GB:-3}"
SHUTDOWN_WAIT="${SHUTDOWN_WAIT:-120}"

C_G='\033[0;32m'; C_Y='\033[1;33m'; C_R='\033[0;31m'; C_B='\033[0;34m'; C_N='\033[0m'
say(){ echo -e "${C_B}[*]${C_N} $*"; }
ok(){ echo -e "${C_G}[✓]${C_N} $*"; }
warn(){ echo -e "${C_Y}[!]${C_N} $*"; }
die(){ echo -e "${C_R}[✗]${C_N} $*" >&2; exit 1; }

usage(){ cat <<EOF
Resize a VM's RAM on Proxmox or libvirt (auto-detected).

Usage: sudo bash extend-vm-ram.sh [--target proxmox|libvirt] [--vm <id|name>] [options]
  --target    backend (default: auto-detect)
  --vm        VMID (proxmox) or domain name (libvirt). Auto-finds a 'hermis' VM if omitted.
  Env: NEW_RAM_GB (default 28), MIN_HOST_GB (default 3)
Examples:
  sudo bash extend-vm-ram.sh                          # auto everything -> 28 GB
  sudo bash extend-vm-ram.sh --target proxmox --vm 110
  sudo NEW_RAM_GB=26 bash extend-vm-ram.sh --vm hermis-ubuntu-ai
EOF
}

while [ $# -gt 0 ]; do case "$1" in
    --target) TARGET="$2"; shift 2;;
    --vm) VM="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "Unknown option: $1 (see --help)";;
esac; done

[ "$(id -u)" -eq 0 ] || die "Run as root (sudo)."

detect_target(){
    if [ "$TARGET" != "auto" ]; then echo "$TARGET"; return; fi
    if command -v qm >/dev/null 2>&1 && [ -d /etc/pve ]; then echo proxmox; return; fi
    if command -v virsh >/dev/null 2>&1; then echo libvirt; return; fi
    die "Neither Proxmox (qm) nor libvirt (virsh) found. Run on the hypervisor host."
}
backend="$(detect_target)"

# Host capacity (shared by both backends)
HOST_TOTAL_GB=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1048576 ))
LEFT_GB=$(( HOST_TOTAL_GB - NEW_RAM_GB ))
NEW_MB=$(( NEW_RAM_GB * 1024 ))
NEW_KIB=$(( NEW_RAM_GB * 1048576 ))

echo -e "${C_B}╔══════════════════════════════════════════════╗${C_N}"
echo -e "${C_B}║  VM RAM Resizer (Proxmox / libvirt)          ║${C_N}"
echo -e "${C_B}╚══════════════════════════════════════════════╝${C_N}"
say "backend=${backend}  host=${HOST_TOTAL_GB}GB  new=${NEW_RAM_GB}GB  host-left=${LEFT_GB}GB (floor ${MIN_HOST_GB})"
[ "$LEFT_GB" -ge "$MIN_HOST_GB" ] || die "Refusing: host would keep only ${LEFT_GB}GB (< ${MIN_HOST_GB}). Lower NEW_RAM_GB."
echo

# ---------------------------------------------------------------- Proxmox (qm)
resize_proxmox(){
    if [ -z "$VM" ]; then
        VM="$(qm list 2>/dev/null | awk 'tolower($2) ~ /hermis/ {print $1; exit}')"
        [ -n "$VM" ] || die "No 'hermis' VM found. Pass --vm <VMID>.  (qm list to see IDs)"
        say "Auto-selected VMID ${VM}"
    fi
    qm status "$VM" >/dev/null 2>&1 || die "VMID ${VM} not found (qm list)."

    local old_mb; old_mb="$(qm config "$VM" | awk -F': ' '/^memory:/{print $2}')"
    say "VMID ${VM}: ${old_mb:-?} MB -> ${NEW_MB} MB"

    if [ "${old_mb:-0}" = "$NEW_MB" ]; then ok "Already ${NEW_MB} MB. Nothing to do."; return; fi

    if [ "$(qm status "$VM" | awk '{print $2}')" = "running" ]; then
        say "Graceful shutdown..."
        qm shutdown "$VM" --timeout "$SHUTDOWN_WAIT" 2>/dev/null || qm stop "$VM" 2>/dev/null || true
        for _ in $(seq 1 "$SHUTDOWN_WAIT"); do
            [ "$(qm status "$VM" | awk '{print $2}')" = "stopped" ] && break; sleep 1
        done
        [ "$(qm status "$VM" | awk '{print $2}')" = "stopped" ] || { qm stop "$VM" || true; sleep 2; }
    fi

    say "Setting memory to ${NEW_MB} MB (balloon off = fixed)..."
    qm set "$VM" --memory "$NEW_MB" --balloon 0 || die "qm set failed."

    say "Starting VMID ${VM}..."
    if ! qm start "$VM"; then
        warn "VM failed to start — rolling back to ${old_mb} MB."
        qm set "$VM" --memory "${old_mb}" 2>/dev/null || true
        qm start "$VM" 2>/dev/null || true
        die "Rolled back."
    fi
    ok "VMID ${VM} now ${NEW_MB} MB and running."
    echo "Rollback: qm shutdown ${VM} && qm set ${VM} --memory ${old_mb} && qm start ${VM}"
}

# --------------------------------------------------------------- libvirt (virsh)
resize_libvirt(){
    [ -n "$VM" ] || VM="$(virsh list --all --name 2>/dev/null | grep -i hermis | head -1)"
    [ -n "$VM" ] || die "No 'hermis' domain found. Pass --vm <domain>.  (virsh list --all)"
    virsh dominfo "$VM" >/dev/null 2>&1 || die "Domain '${VM}' not found (virsh list --all)."

    local cur_kib; cur_kib="$(virsh dominfo "$VM" | awk '/Max memory/{print $3}')"
    say "Domain ${VM}: $(( cur_kib/1048576 )) GB -> ${NEW_RAM_GB} GB"
    [ "$NEW_KIB" -le "$cur_kib" ] && { ok "Already >= ${NEW_RAM_GB} GB. Nothing to do."; return; }

    local backup="/root/hermis-vm-${VM}-$(date +%Y%m%d-%H%M%S).xml"
    virsh dumpxml "$VM" > "$backup"; ok "Backed up XML -> $backup"

    if [ "$(virsh domstate "$VM" 2>/dev/null)" = "running" ]; then
        say "Graceful shutdown..."
        virsh shutdown "$VM" >/dev/null 2>&1 || true
        for _ in $(seq 1 "$SHUTDOWN_WAIT"); do
            [ "$(virsh domstate "$VM" 2>/dev/null)" = "shut off" ] && break; sleep 1
        done
        [ "$(virsh domstate "$VM" 2>/dev/null)" = "shut off" ] || { virsh destroy "$VM" >/dev/null 2>&1 || true; sleep 2; }
    fi

    say "Setting maxMemory + current memory to ${NEW_RAM_GB} GB..."
    virsh setmaxmem "$VM" "$NEW_KIB" --config || { virsh define "$backup" >/dev/null; virsh start "$VM" || true; die "setmaxmem failed; restored."; }
    virsh setmem "$VM" "$NEW_KIB" --config || true

    say "Starting domain ${VM}..."
    if ! virsh start "$VM" >/dev/null 2>&1; then
        warn "Failed to start — rolling back."; virsh define "$backup" >/dev/null; virsh start "$VM" || true
        die "Rolled back to $(( cur_kib/1048576 )) GB (from $backup)."
    fi
    ok "Domain ${VM} now ${NEW_RAM_GB} GB and running."
    echo "Rollback: virsh shutdown ${VM} && virsh define ${backup} && virsh start ${VM}"
}

case "$backend" in
    proxmox) resize_proxmox;;
    libvirt) resize_libvirt;;
esac

echo
ok "Done. Verify inside the VM:  free -h"
