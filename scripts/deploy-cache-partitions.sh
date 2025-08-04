#!/bin/bash

# RouteLogic Enhanced - Platform Cache Partition Deployment Script
# Version: 4.0.0
# Date: 2025-01-31

echo "========================================"
echo "Platform Cache Partition Deployment"
echo "========================================"

# Check if org alias is provided
if [ -z "$1" ]; then
    echo "Usage: ./deploy-cache-partitions.sh <org-alias>"
    echo "Example: ./deploy-cache-partitions.sh mysandbox"
    exit 1
fi

ORG_ALIAS=$1

echo "Deploying to org: $ORG_ALIAS"
echo ""

# Step 1: Check Platform Cache allocation
echo "Step 1: Checking Platform Cache allocation..."
echo "----------------------------------------"
sf data query \
    -q "SELECT SystemModstamp, CacheType, Capacity FROM PlatformCachePartition" \
    -o $ORG_ALIAS \
    --json 2>/dev/null | jq '.result.records' 2>/dev/null || echo "No existing partitions found"

echo ""

# Step 2: Deploy Platform Cache partitions
echo "Step 2: Deploying Platform Cache partitions..."
echo "----------------------------------------"
cd RouteLogic-v4.0.0
sf project deploy start \
    --source-dir force-app/main/default/cachePartitions \
    --target-org $ORG_ALIAS \
    --wait 10
cd ..

if [ $? -ne 0 ]; then
    echo "❌ Deployment failed!"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Ensure Platform Cache is enabled in your org"
    echo "2. Check available cache capacity in Setup > Platform Cache"
    echo "3. If capacity is 0MB, request trial cache or purchase cache"
    exit 1
fi

echo ""
echo "✅ Platform Cache partitions deployed successfully!"
echo ""

# Step 3: Verify deployment
echo "Step 3: Verifying deployment..."
echo "----------------------------------------"
sf data query \
    -q "SELECT MasterLabel, Description, IsDefaultPartition FROM PlatformCachePartition WHERE MasterLabel IN ('RouteLogic', 'RateLimits', 'KeyMetadata', 'AIProcessing')" \
    -o $ORG_ALIAS \
    --json | jq '.result.records'

echo ""
echo "========================================"
echo "Deployment Complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "1. Go to Setup > Platform Cache in your Salesforce org"
echo "2. Verify the partitions are created with correct allocations:"
echo "   - RouteLogic: 10MB (default)"
echo "   - RateLimits: 5MB"
echo "   - KeyMetadata: 5MB"
echo "   - AIProcessing: 5MB"
echo "3. If needed, adjust allocations based on available capacity"
echo ""
echo "To test cache functionality:"
echo "   sf apex run -f scripts/test-cache.apex -u $ORG_ALIAS"