# 🤖 Roboshop Deployment Runbook

**Architecture:** 3-Tier Microservices on AWS EC2 | **Zone:** `sagar90s.online`

---

## Overview

The deployment is split into two decoupled phases to prevent race conditions:

| Phase | Location | Scripts | Purpose |
|---|---|---|---|
| **Phase 1** | Local Workstation | `provision-infra.sh`, `update-dns.sh` | AWS infrastructure + Route 53 DNS |
| **Phase 2** | Frontend EC2 Node | `deploy-all.sh` + setup scripts | Application configuration across all nodes |

---

## Prerequisites

### Local Workstation (Phase 1)
```bash
# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip /tmp/awscliv2.zip && sudo ./aws/install

# Install jq
sudo dnf install -y jq  # or: sudo apt install -y jq

# Configure AWS credentials
aws configure
# Enter: AWS Access Key ID, Secret, Region (e.g. ap-south-1), output format (json)

# Verify credentials
aws sts get-caller-identity
```

---

## Phase 1 — From Your Local Workstation

### Step 1 — Make scripts executable

```bash
cd roboshop-automation/phase1/
chmod +x provision-infra.sh update-dns.sh
```

### Step 2 — Provision Infrastructure

```bash
./provision-infra.sh
```

**What this does:**
- Creates `roboshop-common-ssh-sg` (allows SSH from your IP `49.204.26.231/32`)
- Creates 11 dedicated security groups (one per service)
- Applies all cross-service ingress rules (zero-trust, port-specific)
- Launches 11 EC2 `t3.micro` instances in subnet `subnet-04a504e7b57258a53`
- **Blocks** until all 11 instances pass AWS 2/2 status checks
- Saves all instance IDs and SG IDs to `/tmp/roboshop_provision_state.env`

> ⏱️ **Expected time:** ~5–8 minutes (mostly waiting for EC2 status checks)

**If it fails mid-way:** Simply re-run `./provision-infra.sh` — it reads the state file and resumes from where it left off.

---

### Step 3 — Sync DNS Records

```bash
./update-dns.sh
```

**What this does:**
- Reads instance IDs from `/tmp/roboshop_provision_state.env`
- Fetches PUBLIC IP for `frontend` → upserts `sagar90s.online`
- Fetches PRIVATE IPs for all 9 backend services → upserts their subdomains
- Queries `dispatch` private IP via static Instance ID `i-09cc18ef27c7d5216` (logs only, no DNS)
- Authorises the Frontend server's private IP for SSH on `roboshop-common-ssh-sg`
- Saves resolved IPs + DNS names to `/tmp/roboshop_dns_state.env`

> ⏱️ **Expected time:** ~1–2 minutes

After completion, note the output line:
```
[INFO]  SSH to frontend: ssh ec2-user@<FRONTEND_PUBLIC_IP>
```

---

### Step 4 — Set `DISPATCH_PRIVATE_IP` for Phase 2

```bash
# Read it from the DNS state file
source /tmp/roboshop_dns_state.env
echo "Dispatch IP: ${DISPATCH_PRIVATE_IP}"

# Export it so Phase 2 can use it (or just note it down)
```

---

## Phase 2 — From the Frontend EC2 Server

### Step 5 — SSH into the Frontend Server

```bash
ssh ec2-user@<FRONTEND_PUBLIC_IP>
# Password: DevOps321
```

### Step 6 — Upload Phase 2 scripts to the Frontend server

From your **local workstation**, copy the Phase 2 scripts up:

```bash
# Copy entire phase2 directory to frontend
scp -r roboshop-automation/phase2/ ec2-user@<FRONTEND_PUBLIC_IP>:/home/ec2-user/
# Enter password: DevOps321 when prompted
```

### Step 7 — (On frontend) Install sshpass and set dispatch IP

```bash
# SSH back into frontend
ssh ec2-user@<FRONTEND_PUBLIC_IP>

# Install sshpass (needed by deploy-all.sh)
sudo dnf install -y sshpass

# Set the dispatch private IP (from Step 4 above)
export DISPATCH_PRIVATE_IP="<DISPATCH_PRIVATE_IP>"
```

### Step 8 — Make all scripts executable

```bash
cd ~/phase2/
chmod +x deploy-all.sh
chmod +x setup-scripts/*.sh
```

### Step 9 — Run the Master Orchestrator

```bash
bash deploy-all.sh
```

**What this does (in order):**
1. **mongodb** — installs, configures binding, starts `mongod`
2. **redis** — installs Redis 7, binds `0.0.0.0`, disables `protected-mode`
3. **mysql** — installs MySQL 8, sets root password `RoboShop@1`
4. **rabbitmq** — installs with Erlang repo, creates `roboshop` AMQP user
5. **catalogue** — Node.js 20, installs app, connects to MongoDB, seeds `master-data.js`
6. **user** — Node.js 20, installs app, connects to MongoDB + Redis
7. **cart** — Node.js 20, installs app, connects to Redis + Catalogue
8. **shipping** — Maven/Java, builds JAR, loads MySQL schema + master data, restarts
9. **payment** — Python 3 + uWSGI, connects to Cart + User + RabbitMQ
10. **dispatch** — Go binary, connects to RabbitMQ (AMQP consumer only)
11. **frontend** *(local)* — Nginx 1.24, deploys static assets, writes reverse proxy config

> ⏱️ **Expected time:** ~15–25 minutes total

---

### Step 10 — Resuming from failure

If any step fails, the script stops and logs:
```
[ERROR]  Step 'shipping' FAILED. Check logs above.
```

The failure is recorded in `/var/tmp/roboshop_deploy_state.txt`.

To resume after fixing the issue:
```bash
# Simply re-run – completed steps are automatically skipped
bash deploy-all.sh
```

To reset a specific step for a retry:
```bash
# Remove the COMPLETED entry for that step
sed -i '/^COMPLETED:shipping$/d' /var/tmp/roboshop_deploy_state.txt
bash deploy-all.sh
```

To start completely fresh (re-run all):
```bash
rm /var/tmp/roboshop_deploy_state.txt
bash deploy-all.sh
```

---

## Verification Checklist

### From the Frontend server, verify each backend:
```bash
# Test catalogue
curl -s http://catalog.sagar90s.online:8080/catalogue | head -c 200

# Test user service
curl -s http://user.sagar90s.online:8080/health

# Test cart
curl -s http://cart.sagar90s.online:8080/health

# Check all systemd services on each node via sshpass:
sshpass -p DevOps321 ssh -o StrictHostKeyChecking=no \
  ec2-user@mongodb.sagar90s.online "systemctl is-active mongod"
```

### From your browser:
```
http://sagar90s.online
```
You should see the Roboshop storefront.

---

## Service → DNS → Port Quick Reference

| Service | DNS Record | Port | Protocol |
|---|---|---|---|
| Frontend | `sagar90s.online` | 80 | HTTP (public) |
| Catalogue | `catalog.sagar90s.online` | 8080 | Node.js |
| User | `user.sagar90s.online` | 8080 | Node.js |
| Cart | `cart.sagar90s.online` | 8080 | Node.js |
| Shipping | `shipping.sagar90s.online` | 8080 | Java |
| Payment | `payment.sagar90s.online` | 8080 | Python/uWSGI |
| Dispatch | *(private IP only)* | N/A | Go AMQP consumer |
| MongoDB | `mongodb.sagar90s.online` | 27017 | MongoDB 7 |
| Redis | `redis.sagar90s.online` | 6379 | Redis 7 |
| MySQL | `mysql.sagar90s.online` | 3306 | MySQL 8 |
| RabbitMQ | `rabbitmq.sagar90s.online` | 5672 | AMQP |

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `aws: command not found` | AWS CLI not installed | Install AWS CLI v2 |
| `credentials not configured` | No AWS profile set up | Run `aws configure` |
| Phase 1 hangs at "status checks" | Instances slow to boot | Wait – normal for t3.micro, up to 10 min |
| `sshpass: command not found` | Missing on frontend | `sudo dnf install -y sshpass` |
| Service fails to start | DNS not resolved yet | Check Route 53 propagation; wait 30–60s and retry |
| Catalogue has no products | MongoDB seed failed | SSH to catalogue node, manually run `mongosh --host mongodb.sagar90s.online < /app/db/master-data.js` |
| Shipping crashes at startup | MySQL schema not loaded | SSH to shipping node, manually re-run the mysql commands from `setup-shipping.sh` |
| Payment service errors | pip packages missing | SSH to payment node, `cd /app && pip3 install -r requirements.txt` |

---

*Good luck with your first project! You've got this. 🚀*
