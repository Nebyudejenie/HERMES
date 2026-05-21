# 🎛️ Hermis Agent Control Guide

Control your Hermis Agent services with simple commands.

---

## **⚡ Quick Commands**

### **Start Services**
```bash
sudo bash up.sh
```

or

```bash
sudo bash hermis-control.sh up
```

### **Stop Services**
```bash
sudo bash down.sh
```

or

```bash
sudo bash hermis-control.sh down
```

### **Restart Services**
```bash
sudo bash hermis-control.sh restart
```

### **Check Status**
```bash
bash hermis-control.sh status
```

### **View Logs**
```bash
bash hermis-control.sh logs
```

---

## **📊 What Each Command Does**

### `up` - Start Services ✅

**What happens:**
1. ✓ Checks Docker is running
2. ✓ Starts all containers
3. ✓ Waits 20 seconds for initialization
4. ✓ Verifies services are online
5. ✓ Shows access URLs

**Output:**
```
[*] Starting Hermis Agent...

[1] Checking Docker...
✓ Docker ready

[2] Starting services...
✓ Services starting

[3] Waiting for initialization (20 seconds)...

[4] Verifying services...
╔════════════════════════════════════════╗
║  HERMIS AGENT STARTED                  ║
╚════════════════════════════════════════╝

Running services: 12 / 14

Access:
  • Grafana:    http://localhost:3000
  • Portainer:  http://localhost:9000
  • Traefik:    http://localhost:8080

Monitor:
  docker compose logs -f
```

**Time:** 30-45 seconds

---

### `down` - Stop Services ⬇️

**What happens:**
1. ✓ Gracefully stops all containers
2. ✓ Preserves all data
3. ✓ Preserves all configurations
4. ✓ Verifies shutdown complete

**Output:**
```
[*] Stopping Hermis Agent...

[1] Stopping services gracefully...
✓ Services stopped

[2] Verifying shutdown...
✓ All services stopped

╔════════════════════════════════════════╗
║  HERMIS AGENT STOPPED                  ║
╚════════════════════════════════════════╝

Data preserved in:
  /opt/hermis/data/

To start again:
  sudo bash hermis-control.sh up
```

**Time:** 10-15 seconds

---

### `restart` - Restart Services 🔄

**What happens:**
1. ✓ Stops all services (gracefully)
2. ✓ Waits 3 seconds
3. ✓ Starts all services
4. ✓ Shows status

**Output:**
```
Combines down + up output
```

**Time:** 45-60 seconds

---

### `status` - Check Status 📊

**What happens:**
1. ✓ Lists all services
2. ✓ Shows running count
3. ✓ Indicates online/offline

**Output:**
```
[*] Checking Hermis Agent status...

Services:
NAME        STATUS
traefik     Up 2 days
postgres    Up 2 days
redis       Up 2 days
...

Summary:
  Running: 12 / 14
  Status: ✓ Online
```

**Time:** 2-3 seconds

---

### `logs` - View Logs 📜

**What happens:**
1. ✓ Shows live logs from all services
2. ✓ Updates in real-time
3. ✓ Press Ctrl+C to stop

**Output:**
```
[*] Showing logs (Ctrl+C to stop)...

traefik_1      | 2026-05-21T15:30:00Z INFO msg="Starting services"
postgres_1     | 2026-05-21T15:30:01Z LOG: database initialized
redis_1        | 2026-05-21T15:30:02Z * Ready to accept connections
...
```

---

## **📁 File Structure**

```
~/HERMES/
├── hermis-control.sh    ← Main control script (all commands)
├── up.sh                ← Quick start shortcut
├── down.sh              ← Quick stop shortcut
├── docker-compose.yml   ← Service definitions
└── /opt/hermis/
    ├── .env             ← Configuration (passwords, etc)
    ├── data/            ← Database & file storage (PRESERVED)
    └── config/          ← Service configs (PRESERVED)
```

---

## **⚠️ Important Notes**

### **Data Preservation**
- ✅ All data in `/opt/hermis/data/` is SAFE when you stop
- ✅ All configurations are PRESERVED
- ✅ When you start again, everything is restored

### **No Data Loss**
```bash
# This is SAFE
sudo bash down.sh      # Stop services
# ... do something ...
sudo bash up.sh        # Start again
# All data is still there!
```

### **Complete Reset (if needed)**
```bash
# WARNING: This DELETES all data
sudo rm -rf /opt/hermis/data/*
sudo bash up.sh        # Reinitialize fresh
```

---

## **🐛 Troubleshooting**

### **Services won't start**
```bash
# Check logs
bash hermis-control.sh logs

# Try restart
sudo bash hermis-control.sh restart

# Check docker
docker ps -a
```

### **Services won't stop**
```bash
# Forceful stop (not recommended)
sudo docker compose -f /opt/hermis/docker-compose.yml down -v

# Then restart
sudo bash up.sh
```

### **Check specific service**
```bash
docker logs traefik
docker logs postgres
docker logs redis
```

---

## **📝 Quick Reference**

| Command | Use Case | Time |
|---------|----------|------|
| `sudo bash up.sh` | Start all services | 30-45s |
| `sudo bash down.sh` | Stop all services | 10-15s |
| `sudo bash hermis-control.sh restart` | Restart all | 45-60s |
| `bash hermis-control.sh status` | Check status | 2-3s |
| `bash hermis-control.sh logs` | View logs live | ∞ |

---

## **🎯 Typical Usage**

### **Morning: Start services**
```bash
sudo bash up.sh
```

### **During day: Check if running**
```bash
bash hermis-control.sh status
```

### **Need to update config**
```bash
sudo bash down.sh
# Edit /opt/hermis/.env
sudo bash up.sh
```

### **Evening: Stop services**
```bash
sudo bash down.sh
```

### **Emergency restart**
```bash
sudo bash hermis-control.sh restart
```

---

## **🎉 That's it!**

Simple, safe, and easy to control your Hermis Agent services!

```bash
# Start
sudo bash up.sh

# Stop (safe, preserves data)
sudo bash down.sh

# Check status
bash hermis-control.sh status

# View logs
bash hermis-control.sh logs
```
