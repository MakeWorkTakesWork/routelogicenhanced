#!/usr/bin/env bash
set -euo pipefail

: "${SFDX_AUTH_URL:?SFDX_AUTH_URL not set}"

FILE="${TMPDIR:-/tmp}/sfdx_auth_url.txt"
printf "%s" "$SFDX_AUTH_URL" > "$FILE"

sf org login sfdx-url --sfdx-url-file "$FILE" --alias ci --set-default
sf org whoami --target-org ci
echo "SFDX_AUTH_URL login ok → alias=ci"


