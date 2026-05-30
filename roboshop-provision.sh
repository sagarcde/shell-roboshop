#!/bin/bash

# =============================================================================
# Roboshop - Multi-Tier Microservices Infrastructure Provisioning Script
# Author  : DevOps / AWS Solutions Architect
# Purpose : Provision EC2 instances + Security Groups for all 11 Roboshop services
# Usage   : chmod +x roboshop-provision.sh && ./roboshop-provision.sh
# =============================================================================

set -euo pipefail   # Exit on error, unbound vars, pipe failures
IFS=$'\n\t'

# =============================================================================
# SECTION 1: CONFIGURATION VARIABLES
# =============================================================================

VPC_ID="vpc-06f14609690a23709"
AMI_ID="ami-0220d79f3f480ecf5"
INSTANCE_TYPE="t3.micro"
SUBNET_ID="subnet-04a504e7b57258a53"
MY_IP="49.204.26.231"

# SSH Access (no key pair — AMI has pre-configured credentials)
# Username : ec2-user
# Password : DevOps321

# Derived
MY_IP_CIDR="${MY_IP}/32"

# =============================================================================
# SECTION 2: HELPER FUNCTIONS
# =============================================================================

log()  { echo -e "\n\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[OK]\033[0m    $*"; }
err()  { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# Creates a Security Group and echoes back its ID
# Usage: SG_ID=$(create_sg "sg-name" "description")
create_sg() {
    local name="$1"
    local desc="$2"
    local sg_id

    sg_id=$(aws ec2 create-security-group \
        --group-name   "$name" \
        --description  "$desc" \
        --vpc-id       "$VPC_ID" \
        --query        'GroupId' \
        --output       text)

    # Tag with a human-readable Name
    aws ec2 create-tags \
        --resources "$sg_id" \
        --tags "Key=Name,Value=${name}" "Key=Project,Value=Roboshop"

    echo "$sg_id"
}

# Adds an inbound TCP rule from a CIDR block
# Usage: allow_cidr <sg-id> <port> <cidr>
allow_cidr() {
    local sg_id="$1" port="$2" cidr="$3"
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port     "$port" \
        --cidr     "$cidr"
}

# Adds an inbound TCP rule from another Security Group
# Usage: allow_sg <sg-id> <port> <source-sg-id>
allow_sg() {
    local sg_id="$1" port="$2" source_sg_id="$3"
    aws ec2 authorize-security-group-ingress \
        --group-id     "$sg_id" \
        --protocol     tcp \
        --port         "$port" \
        --source-group "$source_sg_id"
}

# Launches one EC2 instance attached to the common SSH SG + its dedicated SG
# Usage: INSTANCE_ID=$(launch_instance "service-name" "dedicated-sg-id")
launch_instance() {
    local name="$1"
    local dedicated_sg_id="$2"
    local instance_id

    instance_id=$(aws ec2 run-instances \
        --image-id           "$AMI_ID" \
        --instance-type      "$INSTANCE_TYPE" \
        --subnet-id          "$SUBNET_ID" \
        --security-group-ids "$COMMON_SSH_SG_ID" "$dedicated_sg_id" \
        --count              1 \
        --tag-specifications \
            "ResourceType=instance,Tags=[{Key=Name,Value=${name}},{Key=Project,Value=Roboshop}]" \
        --query  'Instances[0].InstanceId' \
        --output text)

    echo "$instance_id"
}

# =============================================================================
# SECTION 3: PRE-FLIGHT CHECKS
# =============================================================================

log "Running pre-flight checks..."

command -v aws &>/dev/null           || err "AWS CLI not found. Please install it."
aws sts get-caller-identity &>/dev/null || err "AWS credentials not configured. Run: aws configure"

ok "Pre-flight checks passed. Deploying as: $(aws sts get-caller-identity --query 'Arn' --output text)"

# =============================================================================
# SECTION 4: COMMON SSH SECURITY GROUP
# One shared SG attached to ALL 11 instances — SSH access from your IP only
# =============================================================================

log "Creating common SSH Security Group: roboshop-common-ssh-sg"

COMMON_SSH_SG_ID=$(create_sg \
    "roboshop-common-ssh-sg" \
    "Roboshop - Shared SSH access from admin IP only")

allow_cidr "$COMMON_SSH_SG_ID" 22 "$MY_IP_CIDR"

ok "Common SSH SG created → $COMMON_SSH_SG_ID  (Port 22 from $MY_IP_CIDR)"

# =============================================================================
# SECTION 5: DEDICATED SECURITY GROUPS — CREATE FIRST (Phase 1)
# All 11 SGs are created before any rules are applied.
# This is critical: cross-service rules reference each other's SG IDs,
# so all IDs must exist before we start wiring them together.
# =============================================================================

log "Creating all 11 dedicated Security Groups (Phase 1 — IDs only, no rules yet)..."

FRONTEND_SG_ID=$(create_sg   "roboshop-frontend-sg"   "Roboshop Frontend - public HTTP")
CATALOGUE_SG_ID=$(create_sg  "roboshop-catalogue-sg"  "Roboshop Catalogue service")
USER_SG_ID=$(create_sg       "roboshop-user-sg"        "Roboshop User service")
CART_SG_ID=$(create_sg       "roboshop-cart-sg"        "Roboshop Cart service")
SHIPPING_SG_ID=$(create_sg   "roboshop-shipping-sg"   "Roboshop Shipping service")
PAYMENT_SG_ID=$(create_sg    "roboshop-payment-sg"    "Roboshop Payment service")
DISPATCH_SG_ID=$(create_sg   "roboshop-dispatch-sg"   "Roboshop Dispatch service")
MONGODB_SG_ID=$(create_sg    "roboshop-mongodb-sg"    "Roboshop MongoDB datastore")
REDIS_SG_ID=$(create_sg      "roboshop-redis-sg"      "Roboshop Redis cache")
MYSQL_SG_ID=$(create_sg      "roboshop-mysql-sg"      "Roboshop MySQL datastore")
RABBITMQ_SG_ID=$(create_sg   "roboshop-rabbitmq-sg"   "Roboshop RabbitMQ message broker")

ok "All 11 dedicated Security Groups created."

# =============================================================================
# SECTION 6: INGRESS RULES — APPLY (Phase 2)
# Now that all SG IDs are captured in variables, apply cross-service rules.
# Each rule uses the actual SG ID (not name) as the source — this is how
# AWS evaluates inter-service traffic at the hypervisor level.
# =============================================================================

log "Applying ingress rules (Phase 2)..."

# --- Frontend ---
# Public-facing: accepts HTTP from the open internet
allow_cidr "$FRONTEND_SG_ID"   80    "0.0.0.0/0"
ok "Frontend   → Port 80   from Internet (0.0.0.0/0)"

# --- Catalogue ---
# Called by Frontend (product listing) and Cart (item details)
allow_sg   "$CATALOGUE_SG_ID"  8080  "$FRONTEND_SG_ID"
allow_sg   "$CATALOGUE_SG_ID"  8080  "$CART_SG_ID"
ok "Catalogue  → Port 8080 from Frontend + Cart"

# --- User ---
# Called by Frontend (auth/profile) and Payment (user validation)
allow_sg   "$USER_SG_ID"       8080  "$FRONTEND_SG_ID"
allow_sg   "$USER_SG_ID"       8080  "$PAYMENT_SG_ID"
ok "User       → Port 8080 from Frontend + Payment"

# --- Cart ---
# Called by Frontend (cart page), Shipping (order calc), Payment (checkout)
allow_sg   "$CART_SG_ID"       8080  "$FRONTEND_SG_ID"
allow_sg   "$CART_SG_ID"       8080  "$SHIPPING_SG_ID"
allow_sg   "$CART_SG_ID"       8080  "$PAYMENT_SG_ID"
ok "Cart       → Port 8080 from Frontend + Shipping + Payment"

# --- Shipping ---
# Called only by Frontend (shipping estimate)
allow_sg   "$SHIPPING_SG_ID"   8080  "$FRONTEND_SG_ID"
ok "Shipping   → Port 8080 from Frontend"

# --- Payment ---
# Called only by Frontend (checkout flow)
allow_sg   "$PAYMENT_SG_ID"    8080  "$FRONTEND_SG_ID"
ok "Payment    → Port 8080 from Frontend"

# --- Dispatch ---
# Outbound-only consumer (pulls jobs from RabbitMQ) — no inbound rules needed
ok "Dispatch   → No inbound rules (outbound consumer only)"

# --- MongoDB ---
# Stores catalogue data and user profiles
allow_sg   "$MONGODB_SG_ID"    27017 "$CATALOGUE_SG_ID"
allow_sg   "$MONGODB_SG_ID"    27017 "$USER_SG_ID"
ok "MongoDB    → Port 27017 from Catalogue + User"

# --- Redis ---
# Session cache for User service; cart cache for Cart service
allow_sg   "$REDIS_SG_ID"      6379  "$USER_SG_ID"
allow_sg   "$REDIS_SG_ID"      6379  "$CART_SG_ID"
ok "Redis      → Port 6379 from User + Cart"

# --- MySQL ---
# Stores shipping/order records — only Shipping service connects
allow_sg   "$MYSQL_SG_ID"      3306  "$SHIPPING_SG_ID"
ok "MySQL      → Port 3306 from Shipping"

# --- RabbitMQ ---
# Message broker: Payment publishes orders; Dispatch consumes them
allow_sg   "$RABBITMQ_SG_ID"   5672  "$PAYMENT_SG_ID"
allow_sg   "$RABBITMQ_SG_ID"   5672  "$DISPATCH_SG_ID"
ok "RabbitMQ   → Port 5672 from Payment + Dispatch"

# =============================================================================
# SECTION 7: LAUNCH EC2 INSTANCES
# Each instance gets exactly 2 SGs: common SSH SG + its own dedicated SG
# =============================================================================

log "Launching 11 EC2 instances..."

FRONTEND_ID=$(launch_instance   "roboshop-frontend"   "$FRONTEND_SG_ID")
ok "frontend   → $FRONTEND_ID"

CATALOGUE_ID=$(launch_instance  "roboshop-catalogue"  "$CATALOGUE_SG_ID")
ok "catalogue  → $CATALOGUE_ID"

USER_ID=$(launch_instance       "roboshop-user"        "$USER_SG_ID")
ok "user       → $USER_ID"

CART_ID=$(launch_instance       "roboshop-cart"        "$CART_SG_ID")
ok "cart       → $CART_ID"

SHIPPING_ID=$(launch_instance   "roboshop-shipping"   "$SHIPPING_SG_ID")
ok "shipping   → $SHIPPING_ID"

PAYMENT_ID=$(launch_instance    "roboshop-payment"    "$PAYMENT_SG_ID")
ok "payment    → $PAYMENT_ID"

DISPATCH_ID=$(launch_instance   "roboshop-dispatch"   "$DISPATCH_SG_ID")
ok "dispatch   → $DISPATCH_ID"

MONGODB_ID=$(launch_instance    "roboshop-mongodb"    "$MONGODB_SG_ID")
ok "mongodb    → $MONGODB_ID"

REDIS_ID=$(launch_instance      "roboshop-redis"      "$REDIS_SG_ID")
ok "redis      → $REDIS_ID"

MYSQL_ID=$(launch_instance      "roboshop-mysql"      "$MYSQL_SG_ID")
ok "mysql      → $MYSQL_ID"

RABBITMQ_ID=$(launch_instance   "roboshop-rabbitmq"   "$RABBITMQ_SG_ID")
ok "rabbitmq   → $RABBITMQ_ID"

# =============================================================================
# SECTION 8: SUMMARY REPORT
# =============================================================================

echo ""
echo "════════════════════════════════════════════════════════════════════════"
echo "            ROBOSHOP — PROVISIONING COMPLETE                           "
echo "════════════════════════════════════════════════════════════════════════"
printf "%-14s  %-22s  %-26s  %s\n" "SERVICE" "INSTANCE ID" "DEDICATED SG ID" "SG ATTACHED (2 total)"
echo "────────────────────────────────────────────────────────────────────────"
printf "%-14s  %-22s  %-26s  %s\n" "frontend"   "$FRONTEND_ID"   "$FRONTEND_SG_ID"   "$COMMON_SSH_SG_ID"
printf "%-14s  %-22s  %-26s  %s\n" "catalogue"  "$CATALOGUE_ID"  "$CATALOGUE_SG_ID"  "$COMMON_SSH_SG_ID"
printf "%-14s  %-22s  %-26s  %s\n" "user"       "$USER_ID"       "$USER_SG_ID"       "$COMMON_SSH_SG_ID"
printf "%-14s  %-22s  %-26s  %s\n" "cart"       "$CART_ID"       "$CART_SG_ID"       "$COMMON_SSH_SG_ID"
printf "%-14s  %-22s  %-26s  %s\n" "shipping"   "$SHIPPING_ID"   "$SHIPPING_SG_ID"   "$COMMON_SSH_SG_ID"
printf "%-14s  %-22s  %-26s  %s\n" "payment"    "$PAYMENT_ID"    "$PAYMENT_SG_ID"    "$COMMON_SSH_SG_ID"
printf "%-14s  %-22s  %-26s  %s\n" "dispatch"   "$DISPATCH_ID"   "$DISPATCH_SG_ID"   "$COMMON_SSH_SG_ID"
printf "%-14s  %-22s  %-26s  %s\n" "mongodb"    "$MONGODB_ID"    "$MONGODB_SG_ID"    "$COMMON_SSH_SG_ID"
printf "%-14s  %-22s  %-26s  %s\n" "redis"      "$REDIS_ID"      "$REDIS_SG_ID"      "$COMMON_SSH_SG_ID"
printf "%-14s  %-22s  %-26s  %s\n" "mysql"      "$MYSQL_ID"      "$MYSQL_SG_ID"      "$COMMON_SSH_SG_ID"
printf "%-14s  %-22s  %-26s  %s\n" "rabbitmq"   "$RABBITMQ_ID"   "$RABBITMQ_SG_ID"   "$COMMON_SSH_SG_ID"
echo "════════════════════════════════════════════════════════════════════════"
echo " Common SSH SG : $COMMON_SSH_SG_ID  (Port 22 from $MY_IP_CIDR)"
echo " VPC           : $VPC_ID"
echo " Subnet        : $SUBNET_ID"
echo "════════════════════════════════════════════════════════════════════════"
ok "All done! Roboshop infrastructure is live."
