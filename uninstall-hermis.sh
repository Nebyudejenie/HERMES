#!/usr/bin/env bash
#
# uninstall-hermis.sh — remove EVERYTHING the Hermis installer put on this VM.
# RUN INSIDE THE VM as root.  This is destructive (deletes /opt/hermis + data).
#
#   sudo bash uninstall-hermis.sh                 # remove stack + data + configs, prune Docker images
#   sudo bash uninstall-hermis.sh --purge-docker  # also uninstall the Docker engine
#   sudo bash uninstall-hermis.sh --all           # purge Docker AND delete the ~/HERMES repo
#   add --yes to skip the confirmation prompt
#
set -uo pipefail

PURGE_DOCKER=false
REMOVE_REPO=false
ASSUME_YES=false
for a in "$@"; do case "$a" in
    --purge-docker) PURGE_DOCKER=true;;
    --remove-repo)  REMOVE_REPO=true;;
    --all)          PURGE_DOCKER=true; REMOVE_REPO=true;;
    --yes|-y)       ASSUME_YES=true;;
    *) echo "Unknown option: $a"; exit 1;;
esac; done

C_G='\033[0;32m'; C_Y='\033[1;33m'; C_R='\033[0;31m'; C_N='\033[0m'
say(){ echo -e "${C_Y}[*]${C_N} $*"; }
ok(){ echo -e "${C_G}[✓]${C_N} $*"; }
die(){ echo -e "${C_R}[✗]${C_N} $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root (sudo bash uninstall-hermis.sh)."

echo -e "${C_R}╔══════════════════════════════════════════════╗${C_N}"
echo -e "${C_R}║  HERMIS UNINSTALL — this DELETES /opt/hermis ║${C_N}"
echo -e "${C_R}╚══════════════════════════════════════════════╝${C_N}"
echo "Will remove: the container stack, all images/volumes, /opt/hermis (incl. data),"
echo "the 'hermis' command, cron job, and Hermis system configs (sshd drop-in, sysctl,"
echo "fail2ban, auditd rules), and reset UFW."
$PURGE_DOCKER && echo "ALSO: uninstall the Docker engine."
$REMOVE_REPO  && echo "ALSO: delete the ~/HERMES repo."
echo
if [ "$ASSUME_YES" != true ]; then
    read -r -p "Type 'WIPE' to proceed: " ans
    [ "$ans" = "WIPE" ] || die "Aborted."
fi
echo

# 1) Stop & remove the container stack ---------------------------------------
say "Stopping and removing the container stack..."
if [ -f /opt/hermis/docker-compose.yml ]; then
    (cd /opt/hermis && docker compose down -v --remove-orphans 2>/dev/null) || true
fi
for c in traefik portainer postgres redis ollama openwebui qdrant minio \
         prometheus grafana loki promtail cadvisor node-exporter keycloak vault autoheal; do
    docker rm -f "$c" 2>/dev/null || true
done
# remove the compose projects regardless of name
for p in hermis hermes; do docker compose -p "$p" down -v --remove-orphans 2>/dev/null || true; done
ok "Stack removed."

# 2) Prune Docker images/volumes/networks ------------------------------------
if command -v docker >/dev/null 2>&1; then
    say "Pruning Docker images, volumes, networks..."
    docker system prune -af --volumes 2>/dev/null || true
    docker network rm hermis_hermis-internal hermis_hermis-ai hermis_hermis-monitoring 2>/dev/null || true
    ok "Docker pruned."
fi

# 3) Remove Hermis files + command + cron ------------------------------------
say "Removing /opt/hermis, the 'hermis' command, and cron job..."
rm -rf /opt/hermis 2>/dev/null || true
rm -f /usr/local/bin/hermis 2>/dev/null || true
rm -f /etc/cron.d/hermis-backup 2>/dev/null || true
ok "Files removed."

# 4) Revert system hardening configs -----------------------------------------
say "Reverting Hermis system configs..."
rm -f /etc/ssh/sshd_config.d/99-hermis.conf 2>/dev/null || true
[ -f /etc/ssh/sshd_config.backup ] && cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config 2>/dev/null || true
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
rm -f /etc/sysctl.d/99-hermis.conf 2>/dev/null || true
sysctl --system >/dev/null 2>&1 || true
rm -f /etc/fail2ban/jail.d/hermis.conf 2>/dev/null || true
systemctl restart fail2ban 2>/dev/null || true
auditctl -W /opt/hermis -p wa -k hermis_changes 2>/dev/null || true
auditctl -W /etc/docker -p wa -k docker_config 2>/dev/null || true
ok "Configs reverted."

# 5) Reset the firewall ------------------------------------------------------
if command -v ufw >/dev/null 2>&1; then
    say "Resetting UFW (SSH stays reachable; firewall left disabled)..."
    ufw --force reset >/dev/null 2>&1 || true
    ufw --force disable >/dev/null 2>&1 || true
    ok "UFW reset."
fi

# 6) Optionally uninstall the Docker engine ----------------------------------
if $PURGE_DOCKER; then
    say "Uninstalling the Docker engine..."
    systemctl stop docker docker.socket containerd 2>/dev/null || true
    DEBIAN_FRONTEND=noninteractive apt-get purge -y \
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker.io 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
    rm -rf /var/lib/docker /var/lib/containerd /etc/docker 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/docker.list /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null || true
    groupdel docker 2>/dev/null || true
    ok "Docker engine removed."
else
    echo -e "${C_Y}[i]${C_N} Docker engine kept. Re-run with --purge-docker to remove it too."
fi

# 7) Optionally remove the repo ----------------------------------------------
if $REMOVE_REPO; then
    for d in /root/HERMES /home/*/HERMES; do
        [ -d "$d" ] && { say "Removing repo $d..."; rm -rf "$d" 2>/dev/null || true; }
    done
    ok "Repo removed."
fi

echo
ok "Uninstall complete. The VM is clean."
echo "Verify:  docker ps 2>/dev/null ; ls /opt/hermis 2>/dev/null ; echo done"
