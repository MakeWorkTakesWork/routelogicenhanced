// Platform Cache Test Script
// Tests all configured partitions using CacheUtils

System.debug('======================================');
System.debug('Testing Platform Cache Partitions');
System.debug('======================================');

// Test 1: Check all partitions
System.debug('\nTest 1: Checking partition availability...');
List<Map<String, Object>> partitionInfo = CacheUtils.getAllPartitionsInfo();
for (Map<String, Object> info : partitionInfo) {
    System.debug('Partition: ' + info.get('partitionName'));
    System.debug('  - Status: ' + (info.get('error') == null ? 'Available' : 'Not Available'));
    System.debug('  - Capacity: ' + info.get('capacity'));
    System.debug('  - Keys: ' + info.get('numKeys'));
    System.debug('  - Usage: ' + info.get('percentUsed') + '%');
}

// Test 2: Test storing and retrieving from each partition
System.debug('\nTest 2: Testing store/retrieve operations...');

// Test RouteLogic partition
String testKey1 = 'test_key_' + DateTime.now().getTime();
String testValue1 = 'Test value for RouteLogic partition';
Boolean stored1 = CacheUtils.put(CacheUtils.PARTITION_ROUTE_LOGIC, testKey1, testValue1, 60);
Object retrieved1 = CacheUtils.get(CacheUtils.PARTITION_ROUTE_LOGIC, testKey1);
System.debug('RouteLogic partition:');
System.debug('  - Store result: ' + stored1);
System.debug('  - Retrieved value: ' + retrieved1);
System.debug('  - Match: ' + (testValue1.equals(retrieved1)));

// Test RateLimits partition
String testKey2 = 'rate_limit_test';
Integer testValue2 = 42;
Boolean stored2 = CacheUtils.put(CacheUtils.PARTITION_RATE_LIMITS, testKey2, testValue2, 60);
Object retrieved2 = CacheUtils.get(CacheUtils.PARTITION_RATE_LIMITS, testKey2);
System.debug('RateLimits partition:');
System.debug('  - Store result: ' + stored2);
System.debug('  - Retrieved value: ' + retrieved2);
System.debug('  - Match: ' + (testValue2 == retrieved2));

// Test KeyMetadata partition
String testKey3 = 'key_metadata_test';
Map<String, Object> testValue3 = new Map<String, Object>{'type' => 'test', 'created' => DateTime.now()};
Boolean stored3 = CacheUtils.put(CacheUtils.PARTITION_KEY_METADATA, testKey3, testValue3, 60);
Object retrieved3 = CacheUtils.get(CacheUtils.PARTITION_KEY_METADATA, testKey3);
System.debug('KeyMetadata partition:');
System.debug('  - Store result: ' + stored3);
System.debug('  - Retrieved value: ' + retrieved3);
System.debug('  - Match: ' + (retrieved3 != null));

// Test AIProcessing partition
String testKey4 = 'ai_processing_test';
List<String> testValue4 = new List<String>{'item1', 'item2', 'item3'};
Boolean stored4 = CacheUtils.put(CacheUtils.PARTITION_AI_PROCESSING, testKey4, testValue4, 60);
Object retrieved4 = CacheUtils.get(CacheUtils.PARTITION_AI_PROCESSING, testKey4);
System.debug('AIProcessing partition:');
System.debug('  - Store result: ' + stored4);
System.debug('  - Retrieved value: ' + retrieved4);
System.debug('  - Match: ' + (retrieved4 != null));

// Test 3: Test increment operation
System.debug('\nTest 3: Testing increment operation...');
String counterKey = 'test_counter';
Integer newValue = CacheUtils.increment(CacheUtils.PARTITION_RATE_LIMITS, counterKey, 1);
System.debug('Counter incremented to: ' + newValue);
newValue = CacheUtils.increment(CacheUtils.PARTITION_RATE_LIMITS, counterKey, 5);
System.debug('Counter incremented by 5 to: ' + newValue);

// Test 4: Test remove operation
System.debug('\nTest 4: Testing remove operation...');
Boolean removed = CacheUtils.remove(CacheUtils.PARTITION_ROUTE_LOGIC, testKey1);
Object afterRemove = CacheUtils.get(CacheUtils.PARTITION_ROUTE_LOGIC, testKey1);
System.debug('Remove result: ' + removed);
System.debug('Value after remove: ' + afterRemove);

// Test 5: Test namespace handling
System.debug('\nTest 5: Testing namespace handling...');
String namespace = CacheUtils.getNamespacePrefix();
System.debug('Detected namespace: ' + (String.isBlank(namespace) ? 'None' : namespace));

System.debug('\n======================================');
System.debug('Platform Cache Tests Complete!');
System.debug('======================================');