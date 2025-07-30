#!/bin/bash
# Script to connect to Salesforce sandbox

echo "========================================="
echo "Connect to Salesforce Sandbox"
echo "========================================="
echo ""
echo "This will open a browser to login to your sandbox."
echo "Make sure to use your SANDBOX credentials, not production!"
echo ""
echo "Press Enter to continue..."
read

# Login to sandbox
echo "Opening browser for sandbox login..."
sf org login web --alias mysandbox --instance-url https://test.salesforce.com

# Verify connection
echo ""
echo "Checking connection..."
sf org display --target-org mysandbox

echo ""
echo "========================================="
echo "Connection complete!"
echo "You can now run Platform Cache tests with:"
echo "./scripts/check-platform-cache.sh mysandbox"
echo "========================================="