#!/usr/bin/env bash
#
# extend-vm-disk.sh — grow the VM's root filesystem to use the whole disk.
# RUN INSIDE THE VM (the Ubuntu guest), as root.
#
# Handles the common Ubuntu-Server layout: GPT partition -> LVM PV -> root LV.
# Your guest currently shows root LV = 29 GB of a 58 GB volume group, so the
# extra space is unused until this runs. Idempotent + safe (each step no-ops if
# there's nothing to grow). Supports --dry-run.
#
set -euo pipefail

DRYRUN="false"
[ "${1:-}" = "--dry-run" ] && DRYRUN="true"

C_G='\033[0;32m'; C_Y='\033[1;33m'; C_R='\033[0;31m'; C_B='\033[0;34m'; C_N='\033[0m'
say(){ echo -e "${C_B}[*]${C_N} $*"; }
ok(){ echo -e "${C_G}[✓]${C_N} $*"; }
warn(){ echo -e "${C_Y}[!]${C_N} $*"; }
die(){ echo -e "${C_R}[✗]${C_N} $*" >&2; exit 1; }
run(){ echo -e "${C_Y}  + $*${C_N}"; [ "$DRYRUN" = "true" ] && return 0; "$@"; }

[ "$DRYRUN" = "true" ] || [ "$(id -u)" -eq 0 ] || die "Run as root (sudo bash extend-vm-disk.sh)."

echo -e "${C_B}╔══════════════════════════════════════════════╗${C_N}"
echo -e "${C_B}║  VM Root Disk Expander                       ║${C_N}"
echo -e "${C_B}╚══════════════════════════════════════════════╝${C_N}"
say "Before:"; df -h / | sed 's/^/    /'
echo

ROOT_SRC="$(findmnt -no SOURCE /)"
FSTYPE="$(findmnt -no FSTYPE /)"
say "root device: ${ROOT_SRC}   fs: ${FSTYPE}"

# Ensure growpart is available (cloud-guest-utils)
if ! command -v growpart >/dev/null 2>&1; then
    say "Installing cloud-guest-utils (provides growpart)..."
    run apt-get update -qq
    run apt-get install -y cloud-guest-utils >/dev/null
fi

grow_fs() {
    case "$FSTYPE" in
        ext4|ext3|ext2) run resize2fs "$ROOT_SRC" ;;
        xfs)            run xfs_growfs / ;;
        *) warn "Unknown fs '${FSTYPE}' — grow it manually after extending the LV." ;;
    esac
}

if lsblk -no TYPE "$ROOT_SRC" 2>/dev/null | grep -q lvm || [[ "$ROOT_SRC" == *mapper* ]]; then
    # ---- LVM path -------------------------------------------------------
    VG="$(lvs --noheadings -o vg_name "$ROOT_SRC" 2>/dev/null | tr -d ' ')"
    [ -n "$VG" ] || die "Could not determine volume group for ${ROOT_SRC}."
    PV="$(pvs --noheadings -o pv_name --select "vg_name=${VG}" 2>/dev/null | head -1 | tr -d ' ')"
    [ -n "$PV" ] || die "Could not find a PV in VG ${VG}."
    PART="$(basename "$PV")"
    PARENT="$(lsblk -no PKNAME "$PV" | head -1)"
    DISK="/dev/${PARENT}"
    PARTNUM="$(cat "/sys/class/block/${PART}/partition" 2>/dev/null || echo '')"

    say "LVM: VG=${VG}  PV=${PV}  disk=${DISK}  part#=${PARTNUM}  rootLV=${ROOT_SRC}"
    echo

    say "1/4 Grow the partition to fill the disk (no-op if already full)..."
    if [ -n "$PARTNUM" ]; then run growpart "$DISK" "$PARTNUM" || warn "  partition already full (NOCHANGE) — ok"; fi

    say "2/4 Resize the LVM physical volume..."
    run pvresize "$PV"

    say "3/4 Extend the root logical volume to use all free space..."
    run lvextend -l +100%FREE "$ROOT_SRC" || warn "  no free extents to add — ok"

    say "4/4 Grow the filesystem..."
    grow_fs
else
    # ---- plain partition root ------------------------------------------
    PART="$(basename "$ROOT_SRC")"
    PARENT="$(lsblk -no PKNAME "$ROOT_SRC" | head -1)"
    DISK="/dev/${PARENT}"
    PARTNUM="$(cat "/sys/class/block/${PART}/partition" 2>/dev/null || echo '')"
    say "Plain root partition on ${DISK} (part ${PARTNUM})"
    [ -n "$PARTNUM" ] && run growpart "$DISK" "$PARTNUM" || warn "  partition already full — ok"
    grow_fs
fi

echo
say "After:"; df -h / | sed 's/^/    /'
echo
ok "Root filesystem expansion complete."
[ "$DRYRUN" = "true" ] && warn "(dry-run: nothing was changed)"
