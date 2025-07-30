#!/bin/bash
# Platform Cache Check Script

echo "========================================="
echo "Platform Cache Configuration Check"
echo "========================================="

if [ -z "$1" ]; then
    echo "Error: Please provide your org alias"
    echo "Usage: ./check-platform-cache.sh <org-alias>"
    exit 1
fi

ORG_ALIAS=$1

echo ""
echo "Running Platform Cache diagnostics for org: $ORG_ALIAS"
echo ""

# Create a simple check script
cat > /tmp/cache-check.apex << 'EOF'
System.debug('Checking Platform Cache configuration...\n');

Boolean cacheEnabled = false;
Boolean partitionFound = false;
Boolean cacheWorking = false;

// Check if Platform Cache is enabled
try {
    Cache.Org.getPartition('test');
    cacheEnabled = true;
} catch (Exception e) {
    if (e.getMessage().contains('not enabled')) {
        System.debug('❌ Platform Cache is NOT enabled in this org');
        System.debug('   Action: Contact Salesforce Support to enable Platform Cache\n');
    }
}

// Check if RouteLogic partition exists
if (cacheEnabled) {
    try {
        Cache.OrgPartition partition = Cache.Org.getPartition('RouteLogic');
        if (partition != null) {
            partitionFound = true;
            System.debug('✅ Platform Cache is enabled');
            System.debug('✅ RouteLogic partition exists\n');
            
            // Test cache operations
            try {
                partition.put('quick_test', 'working', 60);
                String value = (String) partition.get('quick_test');
                partition.remove('quick_test');
                
                if ('working'.equals(value)) {
                    cacheWorking = true;
                    System.debug('✅ Cache operations are working\n');
                }
            } catch (Exception e) {
                System.debug('❌ Cache operations failed: ' + e.getMessage() + '\n');
            }
        }
    } catch (Exception e) {
        System.debug('❌ RouteLogic partition NOT found');
        System.debug('   Action: Setup → Platform Cache → New Platform Cache Partition');
        System.debug('   - Name: RouteLogic');
        System.debug('   - Capacity: 10MB minimum\n');
    }
}

// Summary
System.debug('SUMMARY:');
System.debug('--------');
System.debug('Platform Cache Enabled: ' + (cacheEnabled ? '✅ Yes' : '❌ No'));
System.debug('RouteLogic Partition: ' + (partitionFound ? '✅ Found' : '❌ Not Found'));
System.debug('Cache Operations: ' + (cacheWorking ? '✅ Working' : '❌ Not Working'));

if (cacheEnabled && partitionFound && cacheWorking) {
    System.debug('\n🎉 Platform Cache is fully configured and ready!');
} else {
    System.debug('\n⚠️  Platform Cache needs configuration. See actions above.');
}
EOF

# Run the check
sfdx force:apex:execute -f /tmp/cache-check.apex -u $ORG_ALIAS

# Cleanup
rm /tmp/cache-check.apex

echo ""
echo "========================================="
echo "Check complete! See results above."
echo ""
echo "Next steps if configuration needed:"
echo "1. Go to Setup → Platform Cache"
echo "2. Click 'New Platform Cache Partition'"
echo "3. Create 'RouteLogic' partition with 10MB"
echo "========================================="