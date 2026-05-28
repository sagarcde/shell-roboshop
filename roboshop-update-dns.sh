#!/bin/bash

# =============================================================================
# Roboshop - Route 53 DNS Auto-Update Script
# Purpose : Fetch EC2 instance IPs and upsert A records in Route 53
#           Frontend → Public IP | All others → Private IP
# Usage   : chmod +x roboshop-update-dns.sh && ./roboshop-update-dns.sh
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# SECTION 1: CONFIGURATION
# =============================================================================

HOSTED_ZONE_ID="Z094544866GQBYAJBQ7J"
HOSTED_ZONE_NAME="sagar90s.online"
TTL=1

# =============================================================================
# SECTION 2: COMPONENT MAP
# Format per entry: "COMPONENT|INSTANCE_ID|DNS_RECORD|IP_TYPE"
# IP_TYPE: "public" for frontend, "private" for all others
#          "skip"   for dispatch (no DNS record needed)
# =============================================================================

declare -a COMPONENTS=(
    "frontend  | i-0ed31f23618d795d2 | sagar90s.online           | public"
    "catalogue | i-06f1aa57c5db02c73 | catalog.sagar90s.online   | private"
    "user      | i-07091c149beaf5d13 | user.sagar90s.online      | private"
    "cart      | i-0a2b8abe0c25257d6 | cart.sagar90s.online      | private"
    "shipping  | i-0f0ffc01d928a952e | shipping.sagar90s.online  | private"
    "payment   | i-0b535b761e86c202b | payment.sagar90s.online   | private"
    "dispatch  | i-09cc18ef27c7d5216 | SKIP                      | skip"
    "mongodb   | i-00b16dfe59c6081f7 | mongodb.sagar90s.online   | private"
    "redis     | i-0f1d97c87af8af382 | redis.sagar90s.online     | private"
    "mysql     | i-05e252c089f0baceb | mysql.sagar90s.online     | private"
    "rabbitmq  | i-018caaf590befead5 | rabbitmq.sagar90s.online  | private"
)

# =============================================================================
# SECTION 3: HELPER FUNCTIONS
# =============================================================================

log()     { echo -e "\n\033[1;34m[INFO]\033[0m    $*"; }
ok()      { echo -e "\033[1;32m[OK]\033[0m      $*"; }
warn()    { echo -e "\033[1;33m[SKIP]\033[0m    $*"; }
err()     { echo -e "\033[1;31m[ERROR]\033[0m   $*" >&2; }
divider() { echo "──────────────────────────────────────────────────────────"; }

# Fetch the PUBLIC IP of an EC2 instance by Instance ID
get_public_ip() {
    local instance_id="$1"
    aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query        "Reservations[0].Instances[0].PublicIpAddress" \
        --output       text
}

# Fetch the PRIVATE IP of an EC2 instance by Instance ID
get_private_ip() {
    local instance_id="$1"
    aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query        "Reservations[0].Instances[0].PrivateIpAddress" \
        --output       text
}

# Upsert an A record in Route 53
# Usage: upsert_dns_record "example.sagar90s.online" "10.0.1.25"
upsert_dns_record() {
    local dns_name="$1"
    local ip_address="$2"

    # Build the JSON change batch inline
    local change_batch
    change_batch=$(cat <<EOF
{
  "Comment": "Roboshop auto-update: ${dns_name} -> ${ip_address}",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${dns_name}",
        "Type": "A",
        "TTL": ${TTL},
        "ResourceRecords": [
          { "Value": "${ip_address}" }
        ]
      }
    }
  ]
}
EOF
)

    aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch   "$change_batch" \
        --query          "ChangeInfo.[Id,Status]" \
        --output         text
}

# =============================================================================
# SECTION 4: PRE-FLIGHT CHECKS
# =============================================================================

log "Running pre-flight checks..."
command -v aws &>/dev/null              || { err "AWS CLI not found."; exit 1; }
aws sts get-caller-identity &>/dev/null || { err "AWS credentials not configured. Run: aws configure"; exit 1; }
ok "Authenticated as: $(aws sts get-caller-identity --query 'Arn' --output text)"

# Verify hosted zone exists
HZ_CHECK=$(aws route53 get-hosted-zone \
    --id "$HOSTED_ZONE_ID" \
    --query "HostedZone.Name" \
    --output text 2>/dev/null || echo "NOT_FOUND")

[[ "$HZ_CHECK" == "NOT_FOUND" ]] && { err "Hosted Zone $HOSTED_ZONE_ID not found. Check your config."; exit 1; }
ok "Hosted Zone verified: $HZ_CHECK (ID: $HOSTED_ZONE_ID)"

# =============================================================================
# SECTION 5: MAIN LOOP — FETCH IPs AND UPDATE ROUTE 53
# =============================================================================

log "Starting DNS update for Roboshop components..."
divider

SUCCESS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0

for entry in "${COMPONENTS[@]}"; do

    # Parse the pipe-delimited fields (trim whitespace)
    COMPONENT=$(echo "$entry" | awk -F'|' '{gsub(/ /,"",$1); print $1}')
    INSTANCE_ID=$(echo "$entry" | awk -F'|' '{gsub(/ /,"",$2); print $2}')
    DNS_RECORD=$(echo "$entry" | awk -F'|' '{gsub(/ /,"",$3); print $3}')
    IP_TYPE=$(echo "$entry" | awk -F'|' '{gsub(/ /,"",$4); print $4}')

    echo ""
    echo "  Component  : $COMPONENT"
    echo "  Instance   : $INSTANCE_ID"

    # ── SKIP: dispatch has no DNS record ──────────────────────────────────────
    if [[ "$IP_TYPE" == "skip" ]]; then
        # Still fetch and log the private IP for operational visibility
        DISPATCH_IP=$(get_private_ip "$INSTANCE_ID")
        if [[ -n "$DISPATCH_IP" && "$DISPATCH_IP" != "None" ]]; then
            warn "$COMPONENT — DNS update skipped (Private IP for reference: $DISPATCH_IP)"
        else
            warn "$COMPONENT — DNS update skipped (could not fetch IP either)"
        fi
        (( SKIP_COUNT++ )) || true
        divider
        continue
    fi

    # ── FETCH IP based on type ─────────────────────────────────────────────────
    if [[ "$IP_TYPE" == "public" ]]; then
        IP=$(get_public_ip "$INSTANCE_ID")
        IP_LABEL="Public IP"
    else
        IP=$(get_private_ip "$INSTANCE_ID")
        IP_LABEL="Private IP"
    fi

    # ── VALIDATE retrieved IP ──────────────────────────────────────────────────
    if [[ -z "$IP" || "$IP" == "None" ]]; then
        err "$COMPONENT ($INSTANCE_ID) — Failed to retrieve $IP_LABEL. Instance may be stopped or terminated. Skipping."
        (( FAIL_COUNT++ )) || true
        divider
        continue
    fi

    echo "  DNS Record : $DNS_RECORD"
    echo "  $IP_LABEL  : $IP"
    echo "  TTL        : ${TTL}s"

    # ── UPSERT Route 53 A record ───────────────────────────────────────────────
    echo -n "  Updating Route 53... "
    CHANGE_RESULT=$(upsert_dns_record "$DNS_RECORD" "$IP")

    if [[ -n "$CHANGE_RESULT" ]]; then
        CHANGE_ID=$(echo "$CHANGE_RESULT" | awk '{print $1}')
        CHANGE_STATUS=$(echo "$CHANGE_RESULT" | awk '{print $2}')
        ok "Done  →  Change ID: $CHANGE_ID  |  Status: $CHANGE_STATUS"
        (( SUCCESS_COUNT++ )) || true
    else
        err "$COMPONENT — Route 53 update returned empty response."
        (( FAIL_COUNT++ )) || true
    fi

    divider
done

# =============================================================================
# SECTION 6: SUMMARY
# =============================================================================

echo ""
echo "════════════════════════════════════════════════════════════"
echo "         ROBOSHOP DNS UPDATE — SUMMARY                     "
echo "════════════════════════════════════════════════════════════"
echo "  Hosted Zone  : $HOSTED_ZONE_NAME ($HOSTED_ZONE_ID)"
echo "  TTL          : ${TTL}s"
echo "────────────────────────────────────────────────────────────"
echo "  ✅  Updated  : $SUCCESS_COUNT record(s)"
echo "  ⏭️   Skipped  : $SKIP_COUNT component(s)  (dispatch)"
echo "  ❌  Failed   : $FAIL_COUNT record(s)"
echo "════════════════════════════════════════════════════════════"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    err "One or more DNS updates failed. Check logs above."
    exit 1
fi

ok "All DNS records updated successfully!"
