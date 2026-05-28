#!/bin/bash
# =============================================================================
# Roboshop - Shipping Service Setup Script
# Runs ON: shipping server
# Tech  : Java / Maven, connects to Cart + MySQL
# =============================================================================
set -euo pipefail

CART_HOST="cart.sagar90s.online"
MYSQL_HOST="mysql.sagar90s.online"
MYSQL_ROOT_PASS="RoboShop@1"

log()  { echo -e "\n\033[1;34m[shipping]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[shipping][OK]\033[0m $*"; }

# ── 1. Install Maven (brings Java) ────────────────────────────────────────────
log "Installing maven (includes Java)..."
dnf install maven -y
ok "Maven/Java installed."

# ── 2. Create roboshop system user (idempotent) ───────────────────────────────
log "Creating roboshop system user..."
id roboshop &>/dev/null || useradd --system --home /app --shell /sbin/nologin \
    --comment "roboshop system user" roboshop
ok "User 'roboshop' ready."

# ── 3. Download and extract application ──────────────────────────────────────
log "Downloading shipping application..."
mkdir -p /app
curl -sL -o /tmp/shipping.zip \
    https://roboshop-artifacts.s3.amazonaws.com/shipping-v3.zip
cd /app && unzip -o /tmp/shipping.zip
ok "Application extracted to /app."

# ── 4. Build the Java application ────────────────────────────────────────────
log "Building shipping JAR (mvn clean package)..."
cd /app
mvn clean package -q
mv target/shipping-1.0.jar shipping.jar
ok "shipping.jar built."

# ── 5. Write systemd service ──────────────────────────────────────────────────
log "Writing /etc/systemd/system/shipping.service..."
cat > /etc/systemd/system/shipping.service <<EOF
[Unit]
Description=Shipping Service

[Service]
User=roboshop
Environment=CART_ENDPOINT=${CART_HOST}:8080
Environment=DB_HOST=${MYSQL_HOST}
ExecStart=/bin/java -jar /app/shipping.jar
SyslogIdentifier=shipping

[Install]
WantedBy=multi-user.target
EOF
ok "Service file written."

# ── 6. Enable and start service ───────────────────────────────────────────────
log "Enabling and starting shipping service..."
systemctl daemon-reload
systemctl enable shipping
systemctl restart shipping
ok "Shipping service is running."

# ── 7. Load MySQL schema and master data ─────────────────────────────────────
log "Installing mysql client..."
dnf install mysql -y

log "Loading MySQL schema, app-user, and master data..."
mysql -h "${MYSQL_HOST}" -uroot -p"${MYSQL_ROOT_PASS}" < /app/db/schema.sql
mysql -h "${MYSQL_HOST}" -uroot -p"${MYSQL_ROOT_PASS}" < /app/db/app-user.sql
mysql -h "${MYSQL_HOST}" -uroot -p"${MYSQL_ROOT_PASS}" < /app/db/master-data.sql
ok "MySQL data loaded."

# ── 8. Restart shipping so it picks up the loaded schema ─────────────────────
log "Restarting shipping to pick up loaded schema..."
systemctl restart shipping
ok "Shipping restarted successfully."
