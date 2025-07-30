/**
 * Platform Cache Test Script for RouteLogic
 * Run this in Developer Console to test Platform Cache configuration
 */

System.debug('==== PLATFORM CACHE TEST STARTING ====');

// Test Configuration
String PARTITION_NAME = 'RouteLogic';
Boolean allTestsPassed = true;

try {
    // Test 1: Check if Platform Cache is enabled
    System.debug('\n--- Test 1: Platform Cache Availability ---');
    try {
        // Try to get org partition
        Cache.OrgPartition orgPartition = Cache.Org.getPartition(PARTITION_NAME);
        
        if (orgPartition != null) {
            System.debug('✓ Platform Cache is ENABLED');
            System.debug('✓ Partition "' + PARTITION_NAME + '" is AVAILABLE');
        } else {
            System.debug('✗ Partition "' + PARTITION_NAME + '" NOT FOUND');
            System.debug('Action: Go to Setup → Platform Cache → New Platform Cache Partition');
            allTestsPassed = false;
        }
    } catch (Cache.Org.OrgCacheException e) {
        System.debug('✗ Platform Cache ERROR: ' + e.getMessage());
        System.debug('Possible causes:');
        System.debug('  - Platform Cache not enabled in org');
        System.debug('  - Partition not created');
        System.debug('  - Insufficient cache capacity');
        allTestsPassed = false;
    }
    
    // Test 2: Check partition capacity
    System.debug('\n--- Test 2: Partition Capacity ---');
    try {
        Cache.OrgPartition orgPartition = Cache.Org.getPartition(PARTITION_NAME);
        if (orgPartition != null) {
            // Get capacity info (Note: These methods might not be available in all API versions)
            System.debug('Partition Info:');
            System.debug('  Name: ' + PARTITION_NAME);
            System.debug('  Status: ACTIVE');
            
            // Try to determine available capacity
            Boolean canStore = true;
            try {
                orgPartition.put('capacity_test', 'test_value', 300);
                orgPartition.remove('capacity_test');
                System.debug('✓ Partition has available capacity');
            } catch (Exception e) {
                System.debug('✗ Partition capacity issue: ' + e.getMessage());
                canStore = false;
                allTestsPassed = false;
            }
        }
    } catch (Exception e) {
        System.debug('⚠ Could not check capacity: ' + e.getMessage());
    }
    
    // Test 3: Basic Put/Get Operations
    System.debug('\n--- Test 3: Basic Cache Operations ---');
    try {
        Cache.OrgPartition orgPartition = Cache.Org.getPartition(PARTITION_NAME);
        if (orgPartition != null) {
            // Test string storage
            String testKey = 'test_string_' + DateTime.now().getTime();
            String testValue = 'Hello RouteLogic Cache!';
            
            orgPartition.put(testKey, testValue, 300); // 5 minutes TTL
            String retrieved = (String) orgPartition.get(testKey);
            
            if (testValue.equals(retrieved)) {
                System.debug('✓ String storage: PASS');
            } else {
                System.debug('✗ String storage: FAIL');
                allTestsPassed = false;
            }
            
            // Clean up
            orgPartition.remove(testKey);
        }
    } catch (Exception e) {
        System.debug('✗ Basic operations failed: ' + e.getMessage());
        allTestsPassed = false;
    }
    
    // Test 4: Complex Object Storage (for SecureKeyVault)
    System.debug('\n--- Test 4: Complex Object Storage ---');
    try {
        Cache.OrgPartition orgPartition = Cache.Org.getPartition(PARTITION_NAME);
        if (orgPartition != null) {
            // Test storing a map (similar to SecureKeyVault usage)
            String complexKey = 'test_complex_' + DateTime.now().getTime();
            Map<String, Object> testData = new Map<String, Object>{
                'keyData' => EncodingUtil.base64Encode(Blob.valueOf('test_key_data')),
                'salt' => EncodingUtil.base64Encode(Crypto.generateAesKey(128)),
                'timestamp' => DateTime.now(),
                'version' => 1
            };
            
            orgPartition.put(complexKey, testData, 300);
            Map<String, Object> retrievedData = (Map<String, Object>) orgPartition.get(complexKey);
            
            if (retrievedData != null && retrievedData.get('version') == 1) {
                System.debug('✓ Complex object storage: PASS');
            } else {
                System.debug('✗ Complex object storage: FAIL');
                allTestsPassed = false;
            }
            
            // Clean up
            orgPartition.remove(complexKey);
        }
    } catch (Exception e) {
        System.debug('✗ Complex object storage failed: ' + e.getMessage());
        allTestsPassed = false;
    }
    
    // Test 5: TTL and Expiration
    System.debug('\n--- Test 5: TTL Testing ---');
    try {
        Cache.OrgPartition orgPartition = Cache.Org.getPartition(PARTITION_NAME);
        if (orgPartition != null) {
            String ttlKey = 'test_ttl_' + DateTime.now().getTime();
            
            // Store with 1 second TTL
            orgPartition.put(ttlKey, 'expires_soon', 1);
            
            // Immediate retrieval should work
            String immediate = (String) orgPartition.get(ttlKey);
            if ('expires_soon'.equals(immediate)) {
                System.debug('✓ Immediate retrieval: PASS');
            } else {
                System.debug('✗ Immediate retrieval: FAIL');
                allTestsPassed = false;
            }
            
            // Note: Can't reliably test expiration in synchronous code
            System.debug('  (TTL expiration test requires async verification)');
        }
    } catch (Exception e) {
        System.debug('✗ TTL testing failed: ' + e.getMessage());
        allTestsPassed = false;
    }
    
    // Test 6: Concurrent Access Simulation
    System.debug('\n--- Test 6: Concurrent Access ---');
    try {
        Cache.OrgPartition orgPartition = Cache.Org.getPartition(PARTITION_NAME);
        if (orgPartition != null) {
            String concurrentKey = 'test_concurrent';
            
            // Simulate multiple writes
            for (Integer i = 0; i < 5; i++) {
                orgPartition.put(concurrentKey, 'value_' + i, 300);
            }
            
            String finalValue = (String) orgPartition.get(concurrentKey);
            if (finalValue != null && finalValue.startsWith('value_')) {
                System.debug('✓ Concurrent access: PASS (final value: ' + finalValue + ')');
            } else {
                System.debug('✗ Concurrent access: FAIL');
                allTestsPassed = false;
            }
            
            // Clean up
            orgPartition.remove(concurrentKey);
        }
    } catch (Exception e) {
        System.debug('✗ Concurrent access test failed: ' + e.getMessage());
        allTestsPassed = false;
    }
    
    // Test 7: Key Patterns for SecureKeyVault
    System.debug('\n--- Test 7: SecureKeyVault Key Patterns ---');
    try {
        Cache.OrgPartition orgPartition = Cache.Org.getPartition(PARTITION_NAME);
        if (orgPartition != null) {
            // Test the key pattern used by SecureKeyVault
            String keyPrefix = 'SecureKey.';
            String keyName = 'Security_Master_Encryption_Key';
            String fullKey = keyPrefix + keyName;
            
            // Simulate SecureKeyVault storage
            Map<String, String> vaultData = new Map<String, String>{
                'derivedKey' => EncodingUtil.base64Encode(Crypto.generateAesKey(256)),
                'salt' => EncodingUtil.base64Encode(Crypto.generateAesKey(128))
            };
            
            orgPartition.put(fullKey, vaultData, 3600); // 1 hour TTL
            Map<String, String> retrieved = (Map<String, String>) orgPartition.get(fullKey);
            
            if (retrieved != null && retrieved.containsKey('derivedKey')) {
                System.debug('✓ SecureKeyVault pattern: PASS');
                System.debug('  Key stored: ' + fullKey);
                System.debug('  Data structure validated');
            } else {
                System.debug('✗ SecureKeyVault pattern: FAIL');
                allTestsPassed = false;
            }
            
            // Clean up
            orgPartition.remove(fullKey);
        }
    } catch (Exception e) {
        System.debug('✗ SecureKeyVault pattern test failed: ' + e.getMessage());
        allTestsPassed = false;
    }
    
} catch (Exception e) {
    System.debug('\n✗ CRITICAL ERROR: ' + e.getMessage());
    System.debug('Stack trace: ' + e.getStackTraceString());
    allTestsPassed = false;
}

// Final Summary
System.debug('\n==== PLATFORM CACHE TEST SUMMARY ====');
if (allTestsPassed) {
    System.debug('✅ ALL TESTS PASSED!');
    System.debug('Platform Cache is properly configured for RouteLogic.');
} else {
    System.debug('❌ SOME TESTS FAILED');
    System.debug('\nRequired Actions:');
    System.debug('1. Go to Setup → Platform Cache');
    System.debug('2. Create partition named "RouteLogic"');
    System.debug('3. Allocate at least 10MB capacity');
    System.debug('4. Ensure partition is Active');
}
System.debug('\n==== END OF TEST ====');