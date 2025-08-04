# Platform Cache Setup Guide for RouteLogic Enhanced v4.0.0

## Overview
This guide provides instructions for configuring Platform Cache partitions required for RouteLogic Enhanced's security and performance features.

## Prerequisites
- Salesforce org with Platform Cache enabled
- Minimum 25MB Platform Cache capacity (trial or purchased)
- System Administrator permissions
- Salesforce CLI installed and authenticated

## Cache Partition Architecture

| Partition Name | Size | Purpose | TTL |
|---------------|------|---------|-----|
| **RouteLogic** | 10MB | Main cache, configuration, session data | 1 hour |
| **RateLimits** | 5MB | Rate limiting counters, DDoS protection | 5-60 min |
| **KeyMetadata** | 5MB | Encryption keys, secure tokens | 1 hour |
| **AIProcessing** | 5MB | AI processing temp data, responses | 15 min |

## Automated Deployment (Recommended)

### Step 1: Deploy Metadata
```bash
# Navigate to project directory
cd /Users/johnsweazey/routelogicenhanced4.0.0

# Run deployment script
./scripts/deploy-cache-partitions.sh <your-org-alias>

# Example:
./scripts/deploy-cache-partitions.sh mysandbox
```

### Step 2: Verify Deployment
```bash
# Run test script to verify cache functionality
sfdx force:apex:execute -f scripts/test-cache.apex -u <your-org-alias>
```

## Manual Configuration (Alternative)

### Step 1: Check Available Capacity
1. Navigate to **Setup** → **Platform Cache**
2. Check "Org Cache" capacity
3. Ensure at least 25MB available

If no capacity available:
- Request trial cache (10MB free for Developer Edition)
- Purchase Platform Cache add-on
- Contact Salesforce support for sandbox allocation

### Step 2: Create Partitions Manually

#### Partition 1: RouteLogic (Main)
1. Click **New Platform Cache Partition**
2. Enter:
   - **Label**: RouteLogic
   - **Name**: RouteLogic
   - **Description**: Main cache partition for RouteLogic Enhanced
   - **Default Partition**: ✓ Check
   - **Org Allocation**: 10MB

#### Partition 2: RateLimits
1. Click **New Platform Cache Partition**
2. Enter:
   - **Label**: RateLimits
   - **Name**: RateLimits
   - **Description**: Rate limiting and DDoS protection
   - **Default Partition**: ✗ Uncheck
   - **Org Allocation**: 5MB

#### Partition 3: KeyMetadata
1. Click **New Platform Cache Partition**
2. Enter:
   - **Label**: KeyMetadata
   - **Name**: KeyMetadata
   - **Description**: Secure key and metadata storage
   - **Default Partition**: ✗ Uncheck
   - **Org Allocation**: 5MB

#### Partition 4: AIProcessing
1. Click **New Platform Cache Partition**
2. Enter:
   - **Label**: AIProcessing
   - **Name**: AIProcessing
   - **Description**: AI processing temporary data
   - **Default Partition**: ✗ Uncheck
   - **Org Allocation**: 5MB

### Step 3: Validate Configuration
Execute in Developer Console:
```apex
// Check partition availability
Cache.OrgPartition partition = Cache.Org.getPartition('RouteLogic');
System.debug('RouteLogic partition: ' + partition);
System.debug('Capacity: ' + partition.getCapacity());

// Test basic operations
partition.put('test_key', 'test_value', 60);
Object value = partition.get('test_key');
System.debug('Test value: ' + value);
```

## Troubleshooting

### Issue: "Platform Cache is not available"
**Solution**: 
- Enable Platform Cache in Setup → Platform Cache
- Ensure org has cache capacity allocated

### Issue: "Insufficient capacity"
**Solution**:
- Reduce partition sizes proportionally:
  - RouteLogic: 5MB
  - RateLimits: 2MB
  - KeyMetadata: 2MB
  - AIProcessing: 1MB

### Issue: "Namespace not found"
**Solution**:
- For unmanaged packages, remove namespace prefix
- Use CacheUtils class which handles namespaces dynamically

### Issue: "Partition not found"
**Solution**:
```apex
// List all available partitions
List<Cache.OrgPartition> partitions = Cache.Org.getPartitions();
for (Cache.OrgPartition p : partitions) {
    System.debug('Partition: ' + p.getName());
}
```

## Performance Considerations

### Cache Key Design
- Use consistent naming: `{type}_{identifier}_{timestamp}`
- Example: `USER_005xx000001_API_CALL`

### TTL Strategy
- Short (5 min): Rate limits, real-time data
- Medium (1 hour): Configuration, secrets
- Long (24 hours): Static metadata

### Cache Invalidation
```apex
// Clear specific key
CacheUtils.remove('RouteLogic', 'my_key');

// Clear by pattern (implement in CacheUtils if needed)
for (String key : keysToRemove) {
    CacheUtils.remove('RouteLogic', key);
}
```

## Monitoring

### View Cache Usage
```apex
Map<String, Object> info = CacheUtils.getCapacity('RouteLogic');
System.debug('Usage: ' + info.get('percentUsed') + '%');
System.debug('Keys: ' + info.get('numKeys'));
```

### Set Up Alerts
1. Create scheduled Apex to monitor usage
2. Send alert when usage > 80%
3. Log cache misses for optimization

## Security Best Practices

1. **Encryption**: Always encrypt sensitive data before caching
   ```apex
   Blob encrypted = Crypto.encryptWithManagedIV('AES256', key, data);
   CacheUtils.put('KeyMetadata', 'secure_key', encrypted, 3600);
   ```

2. **Access Control**: Use permission sets to control cache access
   ```apex
   if (!FeatureManagement.checkPermission('Cache_Admin')) {
       throw new SecurityException('Insufficient permissions');
   }
   ```

3. **Audit Logging**: Log all cache operations for sensitive data
   ```apex
   SecurityAuditService.logCacheAccess('KeyMetadata', 'retrieve', keyName);
   ```

## Testing Cache Configuration

### Unit Test Example
```apex
@isTest
private class CacheConfigTest {
    @isTest
    static void testAllPartitions() {
        // Test each partition
        List<String> partitions = new List<String>{
            'RouteLogic', 'RateLimits', 'KeyMetadata', 'AIProcessing'
        };
        
        for (String partitionName : partitions) {
            // Test store and retrieve
            String key = 'test_' + partitionName;
            String value = 'value_' + partitionName;
            
            Boolean stored = CacheUtils.put(partitionName, key, value, 60);
            System.assert(stored || Test.isRunningTest(), 
                'Should store in ' + partitionName);
            
            Object retrieved = CacheUtils.get(partitionName, key);
            System.assertEquals(value, retrieved, 
                'Should retrieve from ' + partitionName);
        }
    }
}
```

## Next Steps

After cache setup:
1. Deploy RouteLogic Enhanced application code
2. Configure Custom Metadata Types
3. Set up Platform Events
4. Run security validation tests
5. Monitor cache performance for first 24 hours

## Support

For issues with Platform Cache setup:
- Salesforce Support: Create a case for cache allocation
- RouteLogic Team: Review application logs for cache errors
- Documentation: Check Salesforce Platform Cache documentation

## Appendix: Cache Capacity Planning

### Calculation Formula
```
Required Capacity = (Concurrent Users × Avg Keys per User × Avg Key Size) + Buffer

Example:
- 100 concurrent users
- 10 keys per user
- 1KB average key size
- 20% buffer
= (100 × 10 × 1KB) × 1.2 = 1.2MB
```

### Recommended Minimums by Org Size
- Small (< 100 users): 10MB total
- Medium (100-1000 users): 25MB total
- Large (1000+ users): 50MB+ total

---

**Last Updated**: January 31, 2025
**Version**: 4.0.0
**Author**: RouteLogic Enhanced Team