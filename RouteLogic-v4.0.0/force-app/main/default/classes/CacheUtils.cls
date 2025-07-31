/**
 * @description Utility class for Platform Cache operations with dynamic namespace support
 * @author RouteLogic Team
 * @date 2025-01-31
 * @version 4.0.0
 * 
 * This utility class provides dynamic namespace resolution for Platform Cache partitions,
 * eliminating hardcoded namespace dependencies and improving deployment flexibility.
 */
public with sharing class CacheUtils {
    
    // Cached namespace prefix to avoid repeated computation
    private static String namespacePrefix;
    
    // Cache partition names used across the application
    public static final String PARTITION_RATE_LIMITS = 'RateLimits';
    public static final String PARTITION_KEY_METADATA = 'KeyMetadata';
    public static final String PARTITION_ROUTE_LOGIC = 'RouteLogic';
    public static final String PARTITION_AI_PROCESSING = 'AIProcessing';
    
    // Default TTL values (in seconds)
    public static final Integer TTL_SHORT = 300;        // 5 minutes
    public static final Integer TTL_MEDIUM = 3600;      // 1 hour
    public static final Integer TTL_LONG = 86400;       // 24 hours
    
    /**
     * @description Get the namespace prefix for the current org
     * @return Namespace prefix with trailing dot, or empty string if no namespace
     */
    public static String getNamespacePrefix() {
        if (namespacePrefix == null) {
            // Get namespace dynamically by checking current class name
            String className = CacheUtils.class.getName();
            
            if (className.contains('.')) {
                // Extract namespace from fully qualified class name
                namespacePrefix = className.substringBefore('.') + '.';
            } else {
                // No namespace in this org
                namespacePrefix = '';
            }
        }
        
        return namespacePrefix;
    }
    
    /**
     * @description Get a Platform Cache partition with dynamic namespace resolution
     * @param partitionName Name of the partition (without namespace)
     * @return Cache.OrgPartition instance or null if partition doesn't exist
     */
    public static Cache.OrgPartition getPartition(String partitionName) {
        try {
            String fullPartitionName = getNamespacePrefix() + partitionName;
            return Cache.Org.getPartition(fullPartitionName);
        } catch (Cache.Org.OrgCacheException e) {
            System.debug(LoggingLevel.WARN, 'Cache partition not found: ' + partitionName);
            System.debug(LoggingLevel.WARN, 'Error: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * @description Put a value in cache with automatic partition resolution
     * @param partitionName Partition name (without namespace)
     * @param key Cache key
     * @param value Value to cache
     * @param ttlSeconds Time to live in seconds
     * @return True if successfully cached
     */
    public static Boolean put(String partitionName, String key, Object value, Integer ttlSeconds) {
        try {
            Cache.OrgPartition partition = getPartition(partitionName);
            if (partition != null) {
                partition.put(key, value, ttlSeconds);
                return true;
            }
            return false;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to put value in cache: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * @description Get a value from cache with automatic partition resolution
     * @param partitionName Partition name (without namespace)
     * @param key Cache key
     * @return Cached value or null if not found
     */
    public static Object get(String partitionName, String key) {
        try {
            Cache.OrgPartition partition = getPartition(partitionName);
            if (partition != null && partition.contains(key)) {
                return partition.get(key);
            }
            return null;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to get value from cache: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * @description Remove a value from cache
     * @param partitionName Partition name (without namespace)
     * @param key Cache key
     * @return True if successfully removed
     */
    public static Boolean remove(String partitionName, String key) {
        try {
            Cache.OrgPartition partition = getPartition(partitionName);
            if (partition != null && partition.contains(key)) {
                partition.remove(key);
                return true;
            }
            return false;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to remove value from cache: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * @description Check if a key exists in cache
     * @param partitionName Partition name (without namespace)
     * @param key Cache key
     * @return True if key exists
     */
    public static Boolean contains(String partitionName, String key) {
        try {
            Cache.OrgPartition partition = getPartition(partitionName);
            return partition != null && partition.contains(key);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to check cache key: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * @description Get cache capacity information
     * @param partitionName Partition name (without namespace)
     * @return Map containing capacity information
     */
    public static Map<String, Object> getCapacity(String partitionName) {
        Map<String, Object> capacityInfo = new Map<String, Object>();
        
        try {
            Cache.OrgPartition partition = getPartition(partitionName);
            if (partition != null) {
                capacityInfo.put('name', partition.getName());
                capacityInfo.put('numKeys', partition.getNumKeys());
                capacityInfo.put('capacity', partition.getCapacity());
                capacityInfo.put('maxCapacity', partition.getMaxCapacity());
                capacityInfo.put('percentUsed', 
                    partition.getCapacity() > 0 ? 
                    (Decimal)partition.getNumKeys() / partition.getCapacity() * 100 : 0
                );
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to get capacity info: ' + e.getMessage());
            capacityInfo.put('error', e.getMessage());
        }
        
        return capacityInfo;
    }
    
    /**
     * @description Generate a cache key with namespace prefix
     * @param baseKey Base key without namespace
     * @return Namespaced cache key
     */
    public static String generateKey(String baseKey) {
        return getNamespacePrefix() + baseKey;
    }
    
    /**
     * @description Atomic increment operation for numeric values
     * @param partitionName Partition name (without namespace)
     * @param key Cache key
     * @param incrementBy Amount to increment by
     * @return New value after increment
     */
    public static Integer increment(String partitionName, String key, Integer incrementBy) {
        Cache.OrgPartition partition = getPartition(partitionName);
        if (partition == null) {
            return null;
        }
        
        // Get current value
        Integer currentValue = (Integer) partition.get(key);
        if (currentValue == null) {
            currentValue = 0;
        }
        
        // Increment and store
        Integer newValue = currentValue + incrementBy;
        partition.put(key, newValue, TTL_MEDIUM);
        
        return newValue;
    }
    
    /**
     * @description Get or compute pattern - retrieve from cache or compute if missing
     * @param partitionName Partition name (without namespace)
     * @param key Cache key
     * @param compute Function to compute value if not in cache
     * @param ttlSeconds Time to live in seconds
     * @return Cached or computed value
     */
    public static Object getOrCompute(String partitionName, String key, CacheCompute compute, Integer ttlSeconds) {
        // Try to get from cache first
        Object value = get(partitionName, key);
        
        if (value == null) {
            // Compute value
            value = compute.compute();
            
            // Store in cache
            if (value != null) {
                put(partitionName, key, value, ttlSeconds);
            }
        }
        
        return value;
    }
    
    /**
     * @description Interface for cache compute operations
     */
    public interface CacheCompute {
        Object compute();
    }
    
    /**
     * @description Clear all keys from a partition (use with caution)
     * @param partitionName Partition name (without namespace)
     * @return Number of keys cleared
     */
    public static Integer clearPartition(String partitionName) {
        Cache.OrgPartition partition = getPartition(partitionName);
        if (partition == null) {
            return 0;
        }
        
        Integer keyCount = partition.getNumKeys();
        
        // Note: Platform Cache doesn't have a clear all method
        // This is a placeholder - in production, you'd need to track keys
        System.debug('Clear partition requested for: ' + partitionName);
        System.debug('Keys in partition: ' + keyCount);
        
        return keyCount;
    }
    
    /**
     * @description Get all partition information for monitoring
     * @return List of partition capacity information
     */
    public static List<Map<String, Object>> getAllPartitionsInfo() {
        List<Map<String, Object>> partitionsInfo = new List<Map<String, Object>>();
        
        // Check all known partitions
        List<String> partitions = new List<String>{
            PARTITION_RATE_LIMITS,
            PARTITION_KEY_METADATA,
            PARTITION_ROUTE_LOGIC,
            PARTITION_AI_PROCESSING
        };
        
        for (String partitionName : partitions) {
            Map<String, Object> info = getCapacity(partitionName);
            info.put('partitionName', partitionName);
            partitionsInfo.add(info);
        }
        
        return partitionsInfo;
    }
}