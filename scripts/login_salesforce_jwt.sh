#!/usr/bin/env bash
set -euo pipefail

: "${SFDX_USERNAME:?SFDX_USERNAME not set}"
: "${SFDX_CLIENT_ID:?SFDX_CLIENT_ID not set}"
: "${SFDX_JWT_KEY:?SFDX_JWT_KEY not set}"

KEY_FILE="${TMPDIR:-/tmp}/sf_jwt_key.pem"
printf "%s" "$SFDX_JWT_KEY" > "$KEY_FILE"

INSTANCE_URL=${INSTANCE_URL:-https://login.salesforce.com}

sf org login jwt \
  --client-id "$SFDX_CLIENT_ID" \
  --username "$SFDX_USERNAME" \
  --jwt-key-file "$KEY_FILE" \
  --instance-url "$INSTANCE_URL" \
  --alias ci --set-default

sf org whoami --target-org ci
echo "JWT login ok → alias=ci"


