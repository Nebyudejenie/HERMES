# Hermis Agent — Deployment Runbook (KVM/libvirt + Proxmox)

End-to-end, copy-paste runbook to deploy the Hermis Agent AI platform **inside a
VM** and run it reliably long-term. Every block is labelled **[HOST]** (the
hypervisor) or **[VM]** (the Ubuntu guest). Nothing here runs Hermis on a
hypervisor host — that is unsupported and breaks production stacks.

Reference environment (this deployment):
- **[HOST]** `cosmicServer` — HP EliteBook 840 G3, Ubuntu 24.04 LTS, i5-6300U
  (4 threads, **no GPU**), 32 GB RAM, ~1 TB NVMe, KVM/QEMU/libvirt, NAT `virbr0`.
- **[VM]** libvirt domain `hermis-ubuntu-ai` (guest hostname `hermis`),
  Ubuntu 24.04 LTS, NAT IP `192.168.122.146`.

Repo: https://github.com/Nebyudejenie/HERMES

---

## 0. One-time: get the repo on both host and VM

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/Nebyudejenie/HERMES.git && cd HERMES
```

---

## 1. [HOST] Right-size the VM — RAM

The guest ships with 8 GB; bump it to 28 GB (host keeps ~4 GB). Safe because the
guest uses virtio-balloon (28 GB is a ceiling, not a reservation).

```bash
cd ~/HERMES
sudo bash extend-vm-ram.sh            # default 28 GB for domain hermis-ubuntu-ai
# custom split:  sudo NEW_RAM_GB=26 bash extend-vm-ram.sh
```

Rollback (if it ever won't boot) is printed by the script:
`virsh shutdown … && virsh define <backup.xml> && virsh start …`

## 2. [VM] Right-size the VM — disk

The guest root LV is only 29 GB of its 58 GB disk. Grow it **before** installing
(models + images need the space).

```bash
# SSH into the VM from the host:
ssh hermis@192.168.122.146

cd ~ ; git clone https://github.com/Nebyudejenie/HERMES.git ; cd HERMES
sudo bash extend-vm-disk.sh --dry-run     # preview
sudo bash extend-vm-disk.sh               # grow to full disk
df -h /                                     # confirm ~57 GB
```

---

## 3. [VM] Install Hermis

```bash
cd ~/HERMES
sudo bash hermis-agent-installer.sh
```

What it does (all idempotent, safe to re-run):
- prerequisite + disk checks, base packages, Docker, hardening
- generates `/opt/hermis/docker-compose.yml` (17 services) + monitoring configs
- pulls a **CPU-friendly** model set by default: `llama3.2:3b` + `nomic-embed-text`
  (≈3.5 GB; 3B keeps a GPU-less i5 responsive). Override:
  `sudo HERMIS_MODELS="llama3.2:3b mistral:7b nomic-embed-text" bash hermis-agent-installer.sh`
- frees required ports, removes stale containers, brings the stack up
- pulls the models into the Ollama container

Time: ~10–15 min (most of it model download).

---

## 4. [VM] Validate

```bash
cd ~/HERMES
bash validate.sh
```

Green = ready. It checks: Docker, all containers running, no unhealthy
containers, autoheal active, Ollama/Qdrant/Grafana/Prometheus/Portainer
reachable, models loaded, and a **real OpenAI-compatible prompt answers**.

---

## 5. Access the platform

Services bind inside the VM. From your laptop, tunnel over SSH (simplest, secure):

```bash
ssh -L 3000:localhost:3000 -L 9000:localhost:9000 -L 11434:localhost:11434 \
    hermis@192.168.122.146
```

| What | URL (after tunnel) | Default creds |
|------|--------------------|---------------|
| Grafana | http://localhost:3000 | admin / `ChangeMe@123` |
| Portainer | http://localhost:9000 | admin / `ChangeMe@123` |
| OpenAI-compatible API (Ollama) | http://localhost:11434/v1 | — |
| Prometheus | http://localhost:9090 | — |
| MinIO console | (tunnel 9901) | minioadmin / `ChangeMe@123` |

OpenWebUI chat UI is routed via Traefik (`webui.localhost`); reach it by tunneling
port 80 and adding a hosts entry, or use Ollama's API directly.

**Use the AI (OpenAI-compatible):**
```bash
curl http://localhost:11434/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"llama3.2:3b","messages":[{"role":"user","content":"Hello"}]}'
```

---

## 6. Day-2 operations

```bash
# Lifecycle (from /opt/hermis or via the control script)
cd /opt/hermis
docker compose ps                 # status
docker compose logs -f <svc>      # logs
docker compose restart <svc>      # restart one service
sudo bash ~/HERMES/hermis-control.sh up|down|status|logs

# Models
docker exec ollama ollama list
docker exec ollama ollama pull qwen2.5:3b
docker exec -it ollama ollama run llama3.2:3b "your prompt"

# Backups (Postgres + data); daily cron is installed automatically
sudo bash ~/HERMES/backup-restore.sh backup
```

**Change default passwords** before real use:
```bash
sudo nano /opt/hermis/.env        # set strong values
cd /opt/hermis && docker compose up -d
```

---

## 7. Self-healing & reliability

- **Per-container:** every service has `restart: unless-stopped`; Docker restarts
  them on crash and on host reboot (Docker is enabled at boot).
- **Health-based:** the `autoheal` container watches healthchecks every 15 s and
  **restarts any container that goes `unhealthy`** automatically.
- **Boot resume:** libvirt resumes the VM; Docker restarts the stack; models
  persist in the `ollama` volume.

---

## 8. Troubleshooting

| Symptom | Action |
|---------|--------|
| A service shows `unhealthy` briefly | normal on first boot; autoheal recovers it; re-run `validate.sh` |
| Install fails on disk space | run step 2 (`extend-vm-disk.sh`) first |
| AI very slow | expected on CPU; use a 3B model (`llama3.2:3b`); avoid 7B+ on this host |
| Port already allocated | installer auto-frees known ports; check `ss -ltnp \| grep <port>` |
| Need to reset a service | `docker compose -f /opt/hermis/docker-compose.yml up -d --force-recreate <svc>` |
| View installer log | `/opt/hermis/logs/hermis-installer.log` |

---

## 9. Provisioning a fresh VM (if you don't have one yet)

On a clean hypervisor, the provisioner builds the VM for you (auto-detects
Proxmox vs libvirt):

```bash
# [HOST]
sudo bash provision-hermis-vm.sh --dry-run          # preview
sudo bash provision-hermis-vm.sh --ram 28672 --vcpus 4 --disk 200
# then install Ubuntu via console, and continue from step 2.
```

---

## Quick reference — the whole flow

```text
[HOST] extend-vm-ram.sh            # 8 GB -> 28 GB
[VM]   extend-vm-disk.sh           # 29 GB -> full disk
[VM]   hermis-agent-installer.sh   # deploy 17-service stack + models
[VM]   validate.sh                 # confirm READY ✅
[YOU]  ssh -L … ; use Grafana / Ollama API / OpenWebUI
```
