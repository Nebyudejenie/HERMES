#!/usr/bin/env bash
#
# provision-hermis-vm.sh — create an Ubuntu Server VM to host Hermis Agent.
#
# Supports TWO backends and changes nothing on the host except creating the VM
# (+ downloading the install ISO):
#
#   • proxmox  — uses `qm` (Proxmox VE), SeaBIOS, virtio
#   • libvirt  — uses `virt-install` (KVM/QEMU/libvirt), gold-standard defaults:
#                qcow2 + cache=none + io=native + virtio, UEFI(OVMF)+TPM, NAT
#
# The Hermis stack itself is installed INSIDE the VM afterwards by running
# `hermis-agent-installer.sh` — identical on both paths.
#
# This script is additive and reversible: it never edits host config, never
# touches other VMs, and supports --dry-run to preview every command.
#
set -euo pipefail

# ---- Defaults (sized for a 32GB / 1TB host already running other workloads) --
NAME="hermis"
VMID="110"                 # proxmox only (numeric)
RAM_MB="16384"             # 16 GB
VCPUS="4"
DISK_GB="200"
TARGET="auto"              # auto | proxmox | libvirt
BRIDGE="vmbr0"             # proxmox bridge; libvirt uses NAT 'default' by default
LIBVIRT_NET="default"      # libvirt network (NAT). Use a bridge name for LAN.
UBUNTU_VER="24.04.2"
ISO_URL="https://releases.ubuntu.com/24.04/ubuntu-${UBUNTU_VER}-live-server-amd64.iso"
DRYRUN="false"

C_G='\033[0;32m'; C_Y='\033[1;33m'; C_R='\033[0;31m'; C_B='\033[0;34m'; C_N='\033[0m'
say()  { echo -e "${C_B}[*]${C_N} $*"; }
ok()   { echo -e "${C_G}[✓]${C_N} $*"; }
warn() { echo -e "${C_Y}[!]${C_N} $*"; }
die()  { echo -e "${C_R}[✗]${C_N} $*" >&2; exit 1; }

usage() {
    cat <<EOF
Provision an Ubuntu Server VM for Hermis Agent.

Usage: sudo bash provision-hermis-vm.sh [options]

Options:
  --target <auto|proxmox|libvirt>  Backend (default: auto-detect)
  --name <name>        VM name (default: ${NAME})
  --vmid <id>          Proxmox numeric VM id (default: ${VMID})
  --ram <MB>           Memory in MB (default: ${RAM_MB})
  --vcpus <n>          vCPUs (default: ${VCPUS})
  --disk <GB>          Disk size in GB (default: ${DISK_GB})
  --bridge <name>      Proxmox bridge (default: ${BRIDGE})
  --libvirt-net <name> libvirt network/bridge (default: ${LIBVIRT_NET} = NAT)
  --dry-run            Print every command, change nothing
  -h, --help           Show this help

After the VM installs Ubuntu, inside it run:
  git clone https://github.com/Nebyudejenie/HERMES.git
  cd HERMES && sudo bash hermis-agent-installer.sh
EOF
}

# ------------------------------------------------------------------- arg parse
while [ $# -gt 0 ]; do
    case "$1" in
        --target)      TARGET="$2"; shift 2;;
        --name)        NAME="$2"; shift 2;;
        --vmid)        VMID="$2"; shift 2;;
        --ram)         RAM_MB="$2"; shift 2;;
        --vcpus)       VCPUS="$2"; shift 2;;
        --disk)        DISK_GB="$2"; shift 2;;
        --bridge)      BRIDGE="$2"; shift 2;;
        --libvirt-net) LIBVIRT_NET="$2"; shift 2;;
        --dry-run)     DRYRUN="true"; shift;;
        -h|--help)     usage; exit 0;;
        *) die "Unknown option: $1 (see --help)";;
    esac
done

# run a command, honoring --dry-run
run() {
    echo -e "${C_Y}  + $*${C_N}"
    [ "$DRYRUN" = "true" ] && return 0
    "$@"
}

require_root() { [ "$(id -u)" -eq 0 ] || die "Run as root (sudo)."; }

detect_target() {
    if [ "$TARGET" != "auto" ]; then echo "$TARGET"; return; fi
    if command -v qm >/dev/null 2>&1 && [ -d /etc/pve ]; then echo "proxmox"; return; fi
    if command -v virt-install >/dev/null 2>&1 || command -v virsh >/dev/null 2>&1; then echo "libvirt"; return; fi
    die "Could not detect a backend. Install Proxmox (qm) or libvirt (virt-install), or pass --target."
}

# --------------------------------------------------------------------- proxmox
provision_proxmox() {
    local iso_dir="/var/lib/vz/template/iso"
    local iso_file="ubuntu-${UBUNTU_VER}-live-server-amd64.iso"

    say "Backend: Proxmox (qm)  VMID=${VMID} name=${NAME}"
    if [ "$DRYRUN" != "true" ]; then
        command -v qm >/dev/null 2>&1 || die "qm not found — is this a Proxmox host?"
        if qm status "$VMID" >/dev/null 2>&1; then
            die "VM ${VMID} already exists. Pick another --vmid or 'qm destroy ${VMID}' first."
        fi
    fi

    run mkdir -p "$iso_dir"
    if [ ! -f "${iso_dir}/${iso_file}" ]; then
        say "Downloading Ubuntu ISO..."
        run wget -O "${iso_dir}/${iso_file}" "$ISO_URL"
    else
        ok "ISO already present: ${iso_dir}/${iso_file}"
    fi

    say "Creating VM (SeaBIOS, virtio)..."
    run qm create "$VMID" \
        --name "$NAME" \
        --memory "$RAM_MB" \
        --cores "$VCPUS" \
        --cpu host \
        --net0 "virtio,bridge=${BRIDGE}" \
        --scsihw virtio-scsi-pci \
        --scsi0 "local-lvm:${DISK_GB}" \
        --ide2 "local:iso/${iso_file},media=cdrom" \
        --boot "order=ide2;scsi0" \
        --ostype l26 \
        --agent 1 \
        --onboot 1
    run qm start "$VMID"

    ok "VM ${VMID} started."
    echo "Next: Proxmox web UI -> VM ${VMID} -> Console -> install Ubuntu (enable OpenSSH)."
}

# --------------------------------------------------------------------- libvirt
provision_libvirt() {
    # Pick a storage pool dir: prefer a registered 'vmstore' tree, else default.
    local img_dir="/var/lib/libvirt/images"
    [ -d /vm-storage/images ] && img_dir="/vm-storage/images"
    local iso_file="${img_dir}/ubuntu-${UBUNTU_VER}-live-server-amd64.iso"
    local disk_path="${img_dir}/${NAME}.qcow2"

    say "Backend: libvirt (virt-install)  name=${NAME}  pool_dir=${img_dir}"
    if [ "$DRYRUN" != "true" ]; then
        command -v virt-install >/dev/null 2>&1 || die "virt-install not found. Install: apt-get install -y virtinst libvirt-daemon-system qemu-kvm ovmf swtpm"
        if virsh dominfo "$NAME" >/dev/null 2>&1; then
            die "Domain '${NAME}' already exists. Pick another --name or 'virsh undefine ${NAME}'."
        fi
    fi

    run mkdir -p "$img_dir"
    if [ ! -f "$iso_file" ]; then
        say "Downloading Ubuntu ISO..."
        run wget -O "$iso_file" "$ISO_URL"
    else
        ok "ISO already present: ${iso_file}"
    fi

    # TPM only if swtpm is available (gold-standard UEFI+TPM); otherwise skip it.
    local tpm_args=()
    if command -v swtpm >/dev/null 2>&1; then
        tpm_args=(--tpm model=tpm-crb,backend.type=emulator,backend.version=2.0)
    else
        warn "swtpm not installed — creating VM without vTPM (UEFI still used)."
    fi

    say "Creating domain (qcow2 cache=none io=native virtio, UEFI, NAT='${LIBVIRT_NET}')..."
    run virt-install \
        --name "$NAME" \
        --memory "$RAM_MB" \
        --vcpus "$VCPUS" \
        --cpu host-passthrough \
        --osinfo ubuntu24.04 \
        --disk "path=${disk_path},size=${DISK_GB},format=qcow2,bus=virtio,cache=none,io=native" \
        --cdrom "$iso_file" \
        --network "network=${LIBVIRT_NET},model=virtio" \
        --boot uefi \
        "${tpm_args[@]}" \
        --graphics vnc,listen=0.0.0.0 \
        --noautoconsole \
        --autostart

    ok "Domain '${NAME}' created and starting."
    echo "Connect a console to run the Ubuntu installer:"
    echo "  virsh domdisplay ${NAME}      # shows the VNC address"
    echo "  # or:  virt-viewer ${NAME}"
}

# ------------------------------------------------------------------------ main
[ "$DRYRUN" = "true" ] || require_root
backend="$(detect_target)"

echo -e "${C_B}╔══════════════════════════════════════════════╗${C_N}"
echo -e "${C_B}║  Hermis VM Provisioner                       ║${C_N}"
echo -e "${C_B}╚══════════════════════════════════════════════╝${C_N}"
say "target=${backend}  ram=${RAM_MB}MB  vcpus=${VCPUS}  disk=${DISK_GB}GB  dry-run=${DRYRUN}"
echo

case "$backend" in
    proxmox) provision_proxmox;;
    libvirt) provision_libvirt;;
    *) die "Unknown target '${backend}' (use proxmox|libvirt)";;
esac

echo
ok "VM provisioned. Install Ubuntu via the console, then INSIDE the VM:"
echo "  sudo apt update && sudo apt install -y git curl"
echo "  git clone https://github.com/Nebyudejenie/HERMES.git"
echo "  cd HERMES && sudo bash hermis-agent-installer.sh"
