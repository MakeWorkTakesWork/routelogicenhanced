# Platform Cache Setup Guide for RouteLogic

## Overview
Platform Cache is required for RouteLogic's secure key storage (SecureKeyVault). This guide walks through setup and validation.

## Setup Steps

### 1. Enable Platform Cache (if not already enabled)

1. Go to **Setup**
2. Search for "Platform Cache" in Quick Find
3. Click **Platform Cache**

If you see a message about Platform Cache not being enabled:
- Contact Salesforce Support to enable Platform Cache for your org
- Or enable it through a scratch org config file

### 2. Create the RouteLogic Partition

1. In **Setup → Platform Cache**
2. Click **New Platform Cache Partition**
3. Configure as follows:

   | Field | Value |
   |-------|-------|
   | **Label** | RouteLogic |
   | **Name** | RouteLogic |
   | **Description** | Secure key storage for RouteLogic Enhanced |
   | **Org Capacity Allocation** | 10 MB (minimum) |
   | **Session Capacity** | 0 MB (not needed) |
   | **Default Partition** | No |

4. Click **Save**

### 3. Verify Partition Status

After creation, verify:
- Status shows as **Active**
- Capacity shows your allocation (e.g., "10 MB of 10 MB used")

## Testing Platform Cache

### Quick Test (Developer Console)

1. Open **Developer Console**
2. Click **Debug → Open Execute Anonymous Window**
3. Run this quick test:

```apex
// Quick Platform Cache Test
try {
    Cache.OrgPartition orgPart = Cache.Org.getPartition('RouteLogic');
    if (orgPart != null) {
        // Test write
        orgPart.put('test_key', 'test_value', 300);
        
        // Test read
        String value = (String) orgPart.get('test_key');
        
        if ('test_value'.equals(value)) {
            System.debug('✅ Platform Cache is working!');
        } else {
            System.debug('❌ Cache read failed');
        }
        
        // Clean up
        orgPart.remove('test_key');
    } else {
        System.debug('❌ RouteLogic partition not found');
    }
} catch (Exception e) {
    System.debug('❌ Error: ' + e.getMessage());
}
```

### Comprehensive Test

Run the full test script:

```bash
sfdx force:apex:execute -f scripts/test-platform-cache.apex -u YOUR_ORG
```

## Expected Test Output

### ✅ Successful Configuration
```
==== PLATFORM CACHE TEST STARTING ====

--- Test 1: Platform Cache Availability ---
✓ Platform Cache is ENABLED
✓ Partition "RouteLogic" is AVAILABLE

--- Test 2: Partition Capacity ---
✓ Partition has available capacity

--- Test 3: Basic Cache Operations ---
✓ String storage: PASS

--- Test 4: Complex Object Storage ---
✓ Complex object storage: PASS

--- Test 5: TTL Testing ---
✓ Immediate retrieval: PASS

--- Test 6: Concurrent Access ---
✓ Concurrent access: PASS (final value: value_4)

--- Test 7: SecureKeyVault Key Patterns ---
✓ SecureKeyVault pattern: PASS

==== PLATFORM CACHE TEST SUMMARY ====
✅ ALL TESTS PASSED!
Platform Cache is properly configured for RouteLogic.
```

### ❌ Common Issues

#### Partition Not Found
```
✗ Partition "RouteLogic" NOT FOUND
Action: Go to Setup → Platform Cache → New Platform Cache Partition
```
**Solution**: Create the partition following step 2 above

#### Insufficient Capacity
```
✗ Partition capacity issue: Cache capacity exceeded
```
**Solution**: Increase org capacity allocation in partition settings

#### Platform Cache Not Enabled
```
✗ Platform Cache ERROR: Platform Cache is not enabled for this org
```
**Solution**: Contact Salesforce Support to enable Platform Cache

## How RouteLogic Uses Platform Cache

### 1. Secure Key Storage (SecureKeyVault)
- Stores derived encryption keys (not raw keys)
- Keys are prefixed with "SecureKey."
- Default TTL: 3600 seconds (1 hour)

### 2. Cache Structure
```apex
// Example cache entry for master encryption key
Key: "SecureKey.Security_Master_Encryption_Key"
Value: {
    "derivedKey": "base64_encoded_derived_key",
    "salt": "base64_encoded_salt",
    "cachedTime": "2025-01-28T10:30:00.000Z"
}
```

### 3. Performance Benefits
- Reduces key derivation operations
- Improves encryption/decryption speed
- Minimizes database queries

## Monitoring Platform Cache

### View Cache Usage
1. Go to **Setup → Platform Cache**
2. Click on "RouteLogic" partition
3. View usage statistics

### Debug Cache Operations
```apex
// Check what's in cache (for debugging only)
Cache.OrgPartition orgPart = Cache.Org.getPartition('RouteLogic');

// Get all keys (not available in standard API, this is pseudo-code)
// In practice, track keys in a custom object or setting
```

## Best Practices

1. **Capacity Planning**
   - Start with 10MB minimum
   - Monitor usage weekly
   - Increase before reaching 80% capacity

2. **Key Management**
   - Use consistent key naming: "SecureKey.{keyName}"
   - Set appropriate TTLs (not too short, not too long)
   - Clean up expired entries periodically

3. **Error Handling**
   - Always wrap cache operations in try-catch
   - Have fallback logic when cache is unavailable
   - Log cache misses for monitoring

4. **Security**
   - Never store raw encryption keys
   - Use derived keys with salts
   - Clear sensitive data when done

## Troubleshooting Script

Run this to diagnose issues:

```apex
// Platform Cache Diagnostic Script
System.debug('=== PLATFORM CACHE DIAGNOSTICS ===');

// Check 1: Platform Cache enabled?
try {
    Cache.Org.getPartition('test');
    System.debug('✓ Platform Cache is enabled');
} catch (Exception e) {
    System.debug('✗ Platform Cache not enabled: ' + e.getMessage());
}

// Check 2: RouteLogic partition exists?
try {
    Cache.OrgPartition rp = Cache.Org.getPartition('RouteLogic');
    System.debug('✓ RouteLogic partition ' + (rp != null ? 'exists' : 'not found'));
} catch (Exception e) {
    System.debug('✗ Error accessing RouteLogic partition: ' + e.getMessage());
}

// Check 3: Can write to cache?
try {
    Cache.OrgPartition rp = Cache.Org.getPartition('RouteLogic');
    if (rp != null) {
        rp.put('diagnostic_test', 'value', 60);
        rp.remove('diagnostic_test');
        System.debug('✓ Cache write/delete successful');
    }
} catch (Exception e) {
    System.debug('✗ Cache write failed: ' + e.getMessage());
}

System.debug('=== END DIAGNOSTICS ===');
```

## Next Steps

After Platform Cache is configured:

1. Test SecureKeyVault functionality
2. Verify encryption/decryption with cache
3. Monitor cache hit rates
4. Set up cache warming strategies

Platform Cache is now ready for RouteLogic's secure key management!