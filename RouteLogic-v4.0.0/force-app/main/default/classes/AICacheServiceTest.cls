@isTest
private class AICacheServiceTest {
    
    @isTest
    static void testBasicCacheOperations() {
        // Setup
        AICacheService.CacheConfig config = new AICacheService.CacheConfig();
        config.ttl = 300;
        config.cacheLevel = 'SESSION';
        config.enableMetrics = true;
        
        // Test put and get
        String testKey = 'test_key_1';
        String testValue = 'test_value_1';
        
        Test.startTest();
        
        // Put value in cache
        AICacheService.put(testKey, testValue, config);
        
        // Get value from cache
        Object retrievedValue = AICacheService.get(testKey, config);
        
        Test.stopTest();
        
        // Verify
        System.assertEquals(testValue, retrievedValue, 'Retrieved value should match');
    }
    
    @isTest
    static void testCacheCompression() {
        // Setup
        AICacheService.CacheConfig config = new AICacheService.CacheConfig();
        config.useCompression = true;
        config.cacheLevel = 'SESSION';
        
        // Create large data
        Map<String, Object> largeData = new Map<String, Object>();
        for (Integer i = 0; i < 100; i++) {
            largeData.put('key_' + i, 'value_' + i);
        }
        
        Test.startTest();
        
        // Cache with compression
        AICacheService.put('compressed_data', largeData, config);
        
        // Retrieve compressed data
        Map<String, Object> retrievedData = (Map<String, Object>) 
            AICacheService.get('compressed_data', config);
        
        Test.stopTest();
        
        // Verify
        System.assertNotEquals(null, retrievedData, 'Data should be retrieved');
        System.assertEquals(100, retrievedData.size(), 'All data should be preserved');
    }
    
    @isTest
    static void testCacheTTL() {
        // Setup
        AICacheService.CacheConfig config = new AICacheService.CacheConfig();
        config.ttl = 1; // 1 second TTL
        config.cacheLevel = 'SESSION';
        
        Test.startTest();
        
        // Put value with short TTL
        AICacheService.put('ttl_test', 'value', config);
        
        // Immediate retrieval should work
        Object value1 = AICacheService.get('ttl_test', config);
        System.assertNotEquals(null, value1, 'Should retrieve value immediately');
        
        // Note: In test context, we can't truly test TTL expiration
        // This would require actual time passage
        
        Test.stopTest();
    }
    
    @isTest
    static void testBulkOperations() {
        // Setup
        AICacheService.CacheConfig config = new AICacheService.CacheConfig();
        Map<String, Object> bulkData = new Map<String, Object>{
            'key1' => 'value1',
            'key2' => 'value2',
            'key3' => 'value3'
        };
        
        Test.startTest();
        
        // Put all values
        AICacheService.putAll(bulkData, config);
        
        // Get all values
        Set<String> keys = bulkData.keySet();
        Map<String, Object> retrieved = AICacheService.getAll(keys, config);
        
        Test.stopTest();
        
        // Verify
        System.assertEquals(3, retrieved.size(), 'Should retrieve all values');
        System.assertEquals('value1', retrieved.get('key1'), 'Value1 should match');
        System.assertEquals('value2', retrieved.get('key2'), 'Value2 should match');
        System.assertEquals('value3', retrieved.get('key3'), 'Value3 should match');
    }
    
    @isTest
    static void testCacheRemoval() {
        // Setup
        AICacheService.CacheConfig config = new AICacheService.CacheConfig();
        String testKey = 'remove_test';
        
        Test.startTest();
        
        // Add to cache
        AICacheService.put(testKey, 'value', config);
        
        // Verify it exists
        Object value1 = AICacheService.get(testKey, config);
        System.assertNotEquals(null, value1, 'Value should exist');
        
        // Remove from cache
        AICacheService.remove(testKey, config);
        
        // Verify it's gone
        Object value2 = AICacheService.get(testKey, config);
        
        Test.stopTest();
        
        System.assertEquals(null, value2, 'Value should be removed');
    }
    
    @isTest
    static void testCacheStats() {
        // Setup
        AICacheService.CacheConfig config = new AICacheService.CacheConfig();
        config.enableMetrics = true;
        
        // Clear stats first
        AICacheService.clearStats();
        
        Test.startTest();
        
        // Perform cache operations
        AICacheService.put('stats_test1', 'value1', config);
        AICacheService.get('stats_test1', config); // Hit
        AICacheService.get('non_existent', config); // Miss
        
        // Get stats
        AICacheService.CacheStats stats = AICacheService.getStats();
        
        Test.stopTest();
        
        // Verify
        System.assertNotEquals(null, stats, 'Stats should be available');
        System.assertEquals(1, stats.hits, 'Should have 1 hit');
        System.assertEquals(1, stats.misses, 'Should have 1 miss');
        System.assertEquals(50.0, stats.hitRate, 'Hit rate should be 50%');
    }
    
    @isTest
    static void testCacheWarming() {
        Test.startTest();
        
        // Warm provider config cache
        AICacheService.warmCache('PROVIDER_CONFIG');
        
        // Warm user preferences cache
        AICacheService.warmCache('USER_PREFERENCES');
        
        // Warm analytics cache
        AICacheService.warmCache('ANALYTICS_DATA');
        
        Test.stopTest();
        
        // Verify no exceptions thrown
        System.assert(true, 'Cache warming should complete without errors');
    }
    
    @isTest
    static void testDifferentCacheLevels() {
        // Test SESSION cache
        AICacheService.CacheConfig sessionConfig = new AICacheService.CacheConfig();
        sessionConfig.cacheLevel = 'SESSION';
        
        AICacheService.put('session_key', 'session_value', sessionConfig);
        Object sessionValue = AICacheService.get('session_key', sessionConfig);
        System.assertEquals('session_value', sessionValue, 'Session cache should work');
        
        // Test ORG cache
        AICacheService.CacheConfig orgConfig = new AICacheService.CacheConfig();
        orgConfig.cacheLevel = 'ORG';
        
        AICacheService.put('org_key', 'org_value', orgConfig);
        Object orgValue = AICacheService.get('org_key', orgConfig);
        System.assertEquals('org_value', orgValue, 'Org cache should work');
        
        // Test PARTITION cache
        AICacheService.CacheConfig partitionConfig = new AICacheService.CacheConfig();
        partitionConfig.cacheLevel = 'PARTITION';
        
        AICacheService.put('partition_key', 'partition_value', partitionConfig);
        Object partitionValue = AICacheService.get('partition_key', partitionConfig);
        System.assertEquals('partition_value', partitionValue, 'Partition cache should work');
    }
    
    @isTest
    static void testNullAndEmptyHandling() {
        AICacheService.CacheConfig config = new AICacheService.CacheConfig();
        
        Test.startTest();
        
        // Test null key
        AICacheService.put(null, 'value', config);
        Object nullKeyResult = AICacheService.get(null, config);
        System.assertEquals(null, nullKeyResult, 'Null key should return null');
        
        // Test empty key
        AICacheService.put('', 'value', config);
        Object emptyKeyResult = AICacheService.get('', config);
        System.assertEquals(null, emptyKeyResult, 'Empty key should return null');
        
        // Test null value
        AICacheService.put('null_value_key', null, config);
        Object nullValueResult = AICacheService.get('null_value_key', config);
        System.assertEquals(null, nullValueResult, 'Null value should not be cached');
        
        Test.stopTest();
    }
    
    @isTest
    static void testExceptionHandling() {
        // Test with invalid cache partition
        AICacheService.CacheConfig config = new AICacheService.CacheConfig();
        config.cacheLevel = 'INVALID';
        
        Test.startTest();
        
        // Should not throw exception
        try {
            AICacheService.put('test_key', 'test_value', config);
            AICacheService.get('test_key', config);
            AICacheService.remove('test_key', config);
        } catch (Exception e) {
            System.assert(false, 'Should handle exceptions gracefully');
        }
        
        Test.stopTest();
        
        System.assert(true, 'Exception handling worked correctly');
    }
}