#!/bin/bash

# =============================================================================
# Roboshop - Infrastructure Cleanup / Delete Script
# Purpose : Terminate all 11 EC2 instances and delete all 12 Security Groups
# Usage   : chmod +x roboshop-delete.sh && ./roboshop-delete.sh
# WARNING : This is IRREVERSIBLE. All instances and SGs will be permanently deleted.
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# SECTION 1: CONFIGURATION
# =============================================================================

VPC_ID="vpc-06f14609690a23709"

# =============================================================================
# SECTION 2: HELPER FUNCTIONS
# =============================================================================

log()  { echo -e "\n\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
err()  { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# Fetch EC2 instance ID by Name tag
# Usage: get_instance_id "roboshop-frontend"
get_instance_id() {
    local name="$1"
    aws ec2 describe-instances \
        --filters \
            "Name=tag:Name,Values=${name}" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text 2>/dev/null || echo "None"
}

# Fetch Security Group ID by Name
# Usage: get_sg_id "roboshop-frontend-sg"
get_sg_id() {
    local name="$1"
    aws ec2 describe-security-groups \
        --filters \
            "Name=group-name,Values=${name}" \
            "Name=vpc-id,Values=${VPC_ID}" \
        --query "SecurityGroups[0].GroupId" \
        --output text 2>/dev/null || echo "None"
}

# =============================================================================
# SECTION 3: PRE-FLIGHT CHECKS
# =============================================================================

log "Running pre-flight checks..."
command -v aws &>/dev/null              || err "AWS CLI not found."
aws sts get-caller-identity &>/dev/null || err "AWS credentials not configured. Run: aws configure"
ok "Logged in as: $(aws sts get-caller-identity --query 'Arn' --output text)"

# =============================================================================
# SECTION 4: CONFIRMATION PROMPT
# =============================================================================

echo ""
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║         ⚠️  ROBOSHOP INFRASTRUCTURE DELETE  ⚠️            ║"
echo "  ║                                                          ║"
echo "  ║  This will PERMANENTLY delete:                          ║"
echo "  ║   • 11 EC2 Instances                                    ║"
echo "  ║   • 12 Security Groups (11 dedicated + 1 common SSH)    ║"
echo "  ║                                                          ║"
echo "  ║  VPC : vpc-06f14609690a23709                            ║"
echo "  ║                                                          ║"
echo "  ║  This action is IRREVERSIBLE.                           ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo ""
read -rp "  Type 'yes' to confirm deletion: " CONFIRM
[[ "$CONFIRM" == "yes" ]] || { echo "Aborted."; exit 0; }

# =============================================================================
# SECTION 5: TERMINATE EC2 INSTANCES
# Instances must be terminated BEFORE deleting their Security Groups.
# AWS will not allow deleting an SG that is still attached to an instance.
# =============================================================================

log "Step 1/4 — Looking up EC2 instance IDs by Name tag..."

SERVICES=(
    roboshop-frontend
    roboshop-catalogue
    roboshop-user
    roboshop-cart
    roboshop-shipping
    roboshop-payment
    roboshop-dispatch
    roboshop-mongodb
    roboshop-redis
    roboshop-mysql
    roboshop-rabbitmq
)

INSTANCE_IDS=()

for svc in "${SERVICES[@]}"; do
    id=$(get_instance_id "$svc")
    if [[ "$id" == "None" || -z "$id" ]]; then
        warn "$svc — instance not found (already deleted or never created)"
    else
        INSTANCE_IDS+=("$id")
        ok "$svc → $id"
    fi
done

if [[ ${#INSTANCE_IDS[@]} -eq 0 ]]; then
    warn "No running instances found. Skipping termination step."
else
    log "Step 2/4 — Terminating ${#INSTANCE_IDS[@]} instance(s)..."

    aws ec2 terminate-instances \
        --instance-ids "${INSTANCE_IDS[@]}" \
        --query 'TerminatingInstances[*].[InstanceId,CurrentState.Name]' \
        --output table

    log "Waiting for all instances to reach 'terminated' state (this may take ~60s)..."
    aws ec2 wait instance-terminated \
        --instance-ids "${INSTANCE_IDS[@]}"
    ok "All instances terminated."
fi

# =============================================================================
# SECTION 6: REVOKE INTER-SG INGRESS RULES
# Security Groups that reference OTHER SGs in their rules must have those
# rules removed before the referenced SG can be deleted. This step strips
# all non-default ingress rules from every dedicated SG.
# =============================================================================

log "Step 3/4 — Revoking inter-SG ingress rules..."

SG_NAMES=(
    roboshop-common-ssh-sg
    roboshop-frontend-sg
    roboshop-catalogue-sg
    roboshop-user-sg
    roboshop-cart-sg
    roboshop-shipping-sg
    roboshop-payment-sg
    roboshop-dispatch-sg
    roboshop-mongodb-sg
    roboshop-redis-sg
    roboshop-mysql-sg
    roboshop-rabbitmq-sg
)

for sg_name in "${SG_NAMES[@]}"; do
    sg_id=$(get_sg_id "$sg_name")
    if [[ "$sg_id" == "None" || -z "$sg_id" ]]; then
        warn "$sg_name — not found, skipping rule revocation"
        continue
    fi

    # Get all current ingress rules as JSON
    rules_json=$(aws ec2 describe-security-groups \
        --group-ids "$sg_id" \
        --query "SecurityGroups[0].IpPermissions" \
        --output json)

    if [[ "$rules_json" == "[]" || -z "$rules_json" ]]; then
        ok "$sg_name ($sg_id) — no ingress rules to revoke"
        continue
    fi

    # Revoke all ingress rules at once
    aws ec2 revoke-security-group-ingress \
        --group-id     "$sg_id" \
        --ip-permissions "$rules_json" &>/dev/null

    ok "$sg_name ($sg_id) — all ingress rules revoked"
done

# =============================================================================
# SECTION 7: DELETE SECURITY GROUPS
# Deleted in reverse dependency order:
#   - Dedicated SGs first (they reference each other)
#   - Common SSH SG last (referenced by all instances, now terminated)
# =============================================================================

log "Step 4/4 — Deleting all 12 Security Groups..."

# Delete dedicated SGs first, common SSH SG last
DELETE_ORDER=(
    roboshop-rabbitmq-sg
    roboshop-mysql-sg
    roboshop-redis-sg
    roboshop-mongodb-sg
    roboshop-dispatch-sg
    roboshop-payment-sg
    roboshop-shipping-sg
    roboshop-cart-sg
    roboshop-user-sg
    roboshop-catalogue-sg
    roboshop-frontend-sg
    roboshop-common-ssh-sg    # Last — shared by all instances
)

for sg_name in "${DELETE_ORDER[@]}"; do
    sg_id=$(get_sg_id "$sg_name")
    if [[ "$sg_id" == "None" || -z "$sg_id" ]]; then
        warn "$sg_name — not found, skipping"
        continue
    fi

    aws ec2 delete-security-group --group-id "$sg_id"
    ok "$sg_name ($sg_id) — deleted"
done

# =============================================================================
# SECTION 8: SUMMARY
# =============================================================================

echo ""
echo "════════════════════════════════════════════════════════════"
echo "         ROBOSHOP CLEANUP — COMPLETE                       "
echo "════════════════════════════════════════════════════════════"
echo " ✔  Terminated  : ${#INSTANCE_IDS[@]} EC2 instance(s)"
echo " ✔  Deleted     : Up to 12 Security Groups"
echo " ✔  VPC intact  : $VPC_ID (VPC itself was NOT deleted)"
echo "════════════════════════════════════════════════════════════"
ok "Roboshop infrastructure has been fully cleaned up."
