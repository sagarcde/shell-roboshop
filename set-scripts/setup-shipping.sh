#!/usr/bin/env bash
# =============================================================================
# Component  : Shipping (Java/Maven + MySQL schema loader)
# Run From   : deploy-all.sh via sshpass (on shipping server)
# Env Vars   : CART_HOST, MYSQL_HOST (injected by deploy-all.sh)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()    { echo -e "${CYAN}[shipping]${NC} $*"; }
log_success() { echo -e "${GREEN}[shipping]${NC} $*"; }
log_error()   { echo -e "${RED}[shipping]${NC} $*" >&2; }

CART_HOST="${CART_HOST:-cart.sagar90s.online}"
MYSQL_HOST="${MYSQL_HOST:-mysql.sagar90s.online}"
MYSQL_ROOT_PASS="RoboShop@1"

log_info "Starting Shipping setup (CART=${CART_HOST}, MYSQL=${MYSQL_HOST}) ..."

# ─── 1. Maven (includes Java) ─────────────────────────────────────────────────
log_info "Installing Maven (brings OpenJDK as dependency) ..."
dnf install -y maven
java -version 2>&1 | head -1
mvn  -version | head -1
log_success "Maven and Java installed."

# ─── 2. Application user ──────────────────────────────────────────────────────
if id roboshop &>/dev/null; then
  log_info "User 'roboshop' already exists – skipping."
else
  useradd --system --home /app --shell /sbin/nologin \
          --comment "roboshop system user" roboshop
fi

# ─── 3. App directory & code ─────────────────────────────────────────────────
[[ -d /app ]] || mkdir -p /app
log_info "Downloading shipping application code ..."
curl -sL -o /tmp/shipping.zip \
  https://roboshop-artifacts.s3.amazonaws.com/shipping-v3.zip
cd /app && unzip -o /tmp/shipping.zip
log_success "Application code extracted."

# ─── 4. Build with Maven ─────────────────────────────────────────────────────
log_info "Building shipping JAR with Maven (this may take a few minutes) ..."
cd /app
mvn clean package -q
mv target/shipping-1.0.jar shipping.jar
log_success "shipping.jar built."

# ─── 5. SystemD service unit ─────────────────────────────────────────────────
cat > /etc/systemd/system/shipping.service <<EOF
[Unit]
Description=Shipping Service

[Service]
User=roboshop
Environment=CART_ENDPOINT=${CART_HOST}:8080
Environment=DB_HOST=${MYSQL_HOST}
ExecStart=/bin/java -jar /app/shipping.jar
SyslogIdentifier=shipping
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
log_success "shipping.service unit written."

# ─── 6. Start service (initial start to ensure it picks up schemas) ──────────
systemctl daemon-reload
systemctl enable --now shipping
sleep 5  # brief wait before schema load

# ─── 7. MySQL client + schema loading ────────────────────────────────────────
log_info "Installing mysql client ..."
dnf install -y mysql
log_success "mysql client installed."

log_info "Waiting for MySQL to be reachable at ${MYSQL_HOST} ..."
for i in $(seq 1 12); do
  mysql -h "${MYSQL_HOST}" -uroot -p"${MYSQL_ROOT_PASS}" -e "SELECT 1;" >/dev/null 2>&1 \
    && break || { log_info "MySQL not ready yet (attempt ${i}/12) – waiting 5s ..."; sleep 5; }
done

log_info "Loading schema.sql ..."
mysql -h "${MYSQL_HOST}" -uroot -p"${MYSQL_ROOT_PASS}" < /app/db/schema.sql
log_success "schema.sql loaded."

log_info "Loading app-user.sql (shipping app MySQL user) ..."
mysql -h "${MYSQL_HOST}" -uroot -p"${MYSQL_ROOT_PASS}" < /app/db/app-user.sql
log_success "app-user.sql loaded."

log_info "Loading master-data.sql (countries/cities/distances) ..."
mysql -h "${MYSQL_HOST}" -uroot -p"${MYSQL_ROOT_PASS}" < /app/db/master-data.sql
log_success "master-data.sql loaded."

# ─── 8. Restart service so it can connect to populated DB ────────────────────
log_info "Restarting shipping service (post schema load) ..."
systemctl restart shipping
sleep 5
systemctl is-active --quiet shipping && log_success "shipping is RUNNING." \
  || { log_error "shipping service failed!"; journalctl -u shipping -n 30 --no-pager; exit 1; }

log_success "Shipping setup COMPLETE."
