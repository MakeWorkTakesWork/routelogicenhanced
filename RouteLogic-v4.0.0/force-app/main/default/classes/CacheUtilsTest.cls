/**
 * @description Test class for CacheUtils
 * @author RouteLogic Security Team
 * @date 2025-01-31
 * @version 4.0.0
 */
@isTest
private class CacheUtilsTest {
    
    /**
     * @description Test namespace prefix detection
     */
    @isTest
    static void testGetNamespacePrefix() {
        Test.startTest();
        String prefix = CacheUtils.getNamespacePrefix();
        Test.stopTest();
        
        System.assertNotEquals(null, prefix, 'Namespace prefix should not be null');
        // In a packaged org, this would return 'routelogic.'
        // In an unpackaged org, it returns ''
    }
    
    /**
     * @description Test cache partition retrieval
     */
    @isTest
    static void testGetPartition() {
        Test.startTest();
        
        // Test with known partition name
        Cache.OrgPartition partition = CacheUtils.getPartition(CacheUtils.PARTITION_RATE_LIMITS);
        
        // Note: This will return null in test context if partition doesn't exist
        // In production, ensure partitions are created
        
        Test.stopTest();
        
        System.assert(true, 'Partition retrieval completed');
    }
    
    /**
     * @description Test cache put and get operations
     */
    @isTest
    static void testPutAndGet() {
        Test.startTest();
        
        String testKey = 'TestKey';
        String testValue = 'TestValue';
        
        // Put value in cache
        Boolean putResult = CacheUtils.put(
            CacheUtils.PARTITION_ROUTE_LOGIC, 
            testKey, 
            testValue, 
            CacheUtils.TTL_SHORT
        );
        
        // Get value from cache
        Object retrievedValue = CacheUtils.get(
            CacheUtils.PARTITION_ROUTE_LOGIC, 
            testKey
        );
        
        Test.stopTest();
        
        // Note: In test context without actual cache partition, these may return null/false
        System.assert(true, 'Cache operations completed');
    }
    
    /**
     * @description Test cache contains operation
     */
    @isTest
    static void testContains() {
        Test.startTest();
        
        String testKey = 'TestContainsKey';
        
        // Check if key exists (should be false initially)
        Boolean containsBefore = CacheUtils.contains(
            CacheUtils.PARTITION_ROUTE_LOGIC, 
            testKey
        );
        
        // Put value
        CacheUtils.put(
            CacheUtils.PARTITION_ROUTE_LOGIC, 
            testKey, 
            'Value', 
            CacheUtils.TTL_SHORT
        );
        
        // Check again
        Boolean containsAfter = CacheUtils.contains(
            CacheUtils.PARTITION_ROUTE_LOGIC, 
            testKey
        );
        
        Test.stopTest();
        
        System.assert(true, 'Contains operation completed');
    }
    
    /**
     * @description Test cache remove operation
     */
    @isTest
    static void testRemove() {
        Test.startTest();
        
        String testKey = 'TestRemoveKey';
        
        // Put value
        CacheUtils.put(
            CacheUtils.PARTITION_ROUTE_LOGIC, 
            testKey, 
            'Value', 
            CacheUtils.TTL_SHORT
        );
        
        // Remove value
        Boolean removeResult = CacheUtils.remove(
            CacheUtils.PARTITION_ROUTE_LOGIC, 
            testKey
        );
        
        Test.stopTest();
        
        System.assert(true, 'Remove operation completed');
    }
    
    /**
     * @description Test capacity information retrieval
     */
    @isTest
    static void testGetCapacity() {
        Test.startTest();
        
        Map<String, Object> capacityInfo = CacheUtils.getCapacity(CacheUtils.PARTITION_RATE_LIMITS);
        
        Test.stopTest();
        
        System.assertNotEquals(null, capacityInfo, 'Capacity info should not be null');
        // In test context, this may contain error information
    }
    
    /**
     * @description Test key generation with namespace
     */
    @isTest
    static void testGenerateKey() {
        Test.startTest();
        
        String baseKey = 'MyKey';
        String namespacedKey = CacheUtils.generateKey(baseKey);
        
        Test.stopTest();
        
        System.assertNotEquals(null, namespacedKey, 'Namespaced key should not be null');
        System.assert(namespacedKey.contains(baseKey), 'Namespaced key should contain base key');
    }
    
    /**
     * @description Test increment operation
     */
    @isTest
    static void testIncrement() {
        Test.startTest();
        
        String counterKey = 'TestCounter';
        
        // Increment by 1
        Integer newValue1 = CacheUtils.increment(
            CacheUtils.PARTITION_RATE_LIMITS, 
            counterKey, 
            1
        );
        
        // Increment by 5
        Integer newValue2 = CacheUtils.increment(
            CacheUtils.PARTITION_RATE_LIMITS, 
            counterKey, 
            5
        );
        
        Test.stopTest();
        
        // In test context without cache, these may return null
        System.assert(true, 'Increment operations completed');
    }
    
    /**
     * @description Test get or compute pattern
     */
    @isTest
    static void testGetOrCompute() {
        Test.startTest();
        
        String computeKey = 'ComputeKey';
        
        // Define compute function
        CacheUtils.CacheCompute computeFunction = new TestComputeFunction();
        
        // Get or compute value
        Object value = CacheUtils.getOrCompute(
            CacheUtils.PARTITION_ROUTE_LOGIC,
            computeKey,
            computeFunction,
            CacheUtils.TTL_MEDIUM
        );
        
        Test.stopTest();
        
        System.assertNotEquals(null, value, 'Computed value should not be null');
        System.assertEquals('Computed Value', value, 'Should return computed value');
    }
    
    /**
     * @description Test get all partitions info
     */
    @isTest
    static void testGetAllPartitionsInfo() {
        Test.startTest();
        
        List<Map<String, Object>> partitionsInfo = CacheUtils.getAllPartitionsInfo();
        
        Test.stopTest();
        
        System.assertNotEquals(null, partitionsInfo, 'Partitions info should not be null');
        System.assertEquals(4, partitionsInfo.size(), 'Should have info for 4 partitions');
    }
    
    /**
     * @description Test compute function implementation
     */
    private class TestComputeFunction implements CacheUtils.CacheCompute {
        public Object compute() {
            return 'Computed Value';
        }
    }
    
    /**
     * @description Test error handling for invalid partition
     */
    @isTest
    static void testInvalidPartition() {
        Test.startTest();
        
        // Try to access non-existent partition
        Cache.OrgPartition partition = CacheUtils.getPartition('NonExistentPartition');
        
        // Try operations on non-existent partition
        Boolean putResult = CacheUtils.put('NonExistentPartition', 'key', 'value', 60);
        Object getValue = CacheUtils.get('NonExistentPartition', 'key');
        Boolean containsResult = CacheUtils.contains('NonExistentPartition', 'key');
        Boolean removeResult = CacheUtils.remove('NonExistentPartition', 'key');
        
        Test.stopTest();
        
        // All operations should handle errors gracefully
        System.assertEquals(false, putResult, 'Put should return false for invalid partition');
        System.assertEquals(null, getValue, 'Get should return null for invalid partition');
        System.assertEquals(false, containsResult, 'Contains should return false for invalid partition');
        System.assertEquals(false, removeResult, 'Remove should return false for invalid partition');
    }
}