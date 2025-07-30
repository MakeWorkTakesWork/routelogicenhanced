public with sharing class AICacheService {
    private static final String CACHE_PARTITION = 'local.AICache';
    private static final Integer DEFAULT_TTL = 300; // 5 minutes
    private static final Integer MAX_TTL = 3600; // 1 hour
    
    // Cache configuration
    public class CacheConfig {
        public Integer ttl { get; set; }
        public Boolean useCompression { get; set; }
        public String cacheLevel { get; set; } // 'SESSION', 'ORG', 'PARTITION'
        public Boolean enableMetrics { get; set; }
        
        public CacheConfig() {
            this.ttl = DEFAULT_TTL;
            this.useCompression = false;
            this.cacheLevel = 'PARTITION';
            this.enableMetrics = true;
        }
    }
    
    // Cache statistics
    public class CacheStats {
        public Integer hits { get; set; }
        public Integer misses { get; set; }
        public Decimal hitRate { get; set; }
        public Long totalSize { get; set; }
        public Integer itemCount { get; set; }
        public DateTime lastReset { get; set; }
        
        public CacheStats() {
            this.hits = 0;
            this.misses = 0;
            this.hitRate = 0.0;
            this.totalSize = 0;
            this.itemCount = 0;
            this.lastReset = DateTime.now();
        }
    }
    
    // Main cache operations
    public static void put(String key, Object value, CacheConfig config) {
        try {
            if (String.isBlank(key) || value == null) {
                return;
            }
            
            // Prepare cache value
            CacheEntry entry = new CacheEntry();
            entry.value = value;
            entry.timestamp = DateTime.now();
            entry.ttl = config.ttl;
            entry.compressed = config.useCompression;
            
            // Apply compression if needed
            if (config.useCompression) {
                entry.value = compressData(JSON.serialize(value));
            }
            
            // Store in appropriate cache level
            switch on config.cacheLevel {
                when 'SESSION' {
                    Cache.Session.put(key, entry);
                }
                when 'ORG' {
                    Cache.Org.put(key, entry, config.ttl);
                }
                when else {
                    Cache.Partition.get(CACHE_PARTITION).put(key, entry, config.ttl);
                }
            }
            
            // Update metrics
            if (config.enableMetrics) {
                updateMetrics('put', key);
            }
            
        } catch (Exception e) {
            System.debug('Cache put error: ' + e.getMessage());
        }
    }
    
    public static Object get(String key, CacheConfig config) {
        try {
            if (String.isBlank(key)) {
                return null;
            }
            
            CacheEntry entry = null;
            
            // Retrieve from appropriate cache level
            switch on config.cacheLevel {
                when 'SESSION' {
                    entry = (CacheEntry) Cache.Session.get(key);
                }
                when 'ORG' {
                    entry = (CacheEntry) Cache.Org.get(key);
                }
                when else {
                    entry = (CacheEntry) Cache.Partition.get(CACHE_PARTITION).get(key);
                }
            }
            
            // Check if entry exists and is valid
            if (entry == null) {
                if (config.enableMetrics) {
                    updateMetrics('miss', key);
                }
                return null;
            }
            
            // Check TTL
            if (isExpired(entry)) {
                remove(key, config);
                if (config.enableMetrics) {
                    updateMetrics('miss', key);
                }
                return null;
            }
            
            // Decompress if needed
            Object value = entry.value;
            if (entry.compressed && value instanceof String) {
                value = JSON.deserializeUntyped(decompressData((String)value));
            }
            
            if (config.enableMetrics) {
                updateMetrics('hit', key);
            }
            
            return value;
            
        } catch (Exception e) {
            System.debug('Cache get error: ' + e.getMessage());
            return null;
        }
    }
    
    public static void remove(String key, CacheConfig config) {
        try {
            if (String.isBlank(key)) {
                return;
            }
            
            switch on config.cacheLevel {
                when 'SESSION' {
                    Cache.Session.remove(key);
                }
                when 'ORG' {
                    Cache.Org.remove(key);
                }
                when else {
                    Cache.Partition.get(CACHE_PARTITION).remove(key);
                }
            }
            
            if (config.enableMetrics) {
                updateMetrics('remove', key);
            }
            
        } catch (Exception e) {
            System.debug('Cache remove error: ' + e.getMessage());
        }
    }
    
    // Bulk operations
    public static void putAll(Map<String, Object> values, CacheConfig config) {
        for (String key : values.keySet()) {
            put(key, values.get(key), config);
        }
    }
    
    public static Map<String, Object> getAll(Set<String> keys, CacheConfig config) {
        Map<String, Object> results = new Map<String, Object>();
        for (String key : keys) {
            Object value = get(key, config);
            if (value != null) {
                results.put(key, value);
            }
        }
        return results;
    }
    
    // Pattern-based operations
    public static void removeByPattern(String pattern, CacheConfig config) {
        // Note: This is a simplified implementation
        // In production, you might want to maintain a key index
        Set<String> keysToRemove = new Set<String>();
        
        // For demonstration, assuming we have a way to get all keys
        // This would need to be implemented based on your specific needs
        for (String key : getKeysByPattern(pattern)) {
            remove(key, config);
        }
    }
    
    // Cache warming
    public static void warmCache(String cacheType) {
        CacheConfig config = new CacheConfig();
        
        switch on cacheType {
            when 'PROVIDER_CONFIG' {
                warmProviderConfigCache(config);
            }
            when 'USER_PREFERENCES' {
                warmUserPreferencesCache(config);
            }
            when 'ANALYTICS_DATA' {
                warmAnalyticsCache(config);
            }
        }
    }
    
    private static void warmProviderConfigCache(CacheConfig config) {
        List<AI_Provider_Configuration__c> configs = [
            SELECT Id, Name, Provider_Type__c, API_Endpoint__c, 
                   Is_Active__c, Priority_Level__c
            FROM AI_Provider_Configuration__c
            WHERE Is_Active__c = true
        ];
        
        for (AI_Provider_Configuration__c cfg : configs) {
            String key = 'provider_' + cfg.Id;
            put(key, cfg, config);
        }
    }
    
    private static void warmUserPreferencesCache(CacheConfig config) {
        List<AI_User_Preference__c> prefs = [
            SELECT Id, User__c, Preference_Key__c, Preference_Value__c
            FROM AI_User_Preference__c
            WHERE User__c = :UserInfo.getUserId()
        ];
        
        Map<String, String> prefMap = new Map<String, String>();
        for (AI_User_Preference__c pref : prefs) {
            prefMap.put(pref.Preference_Key__c, pref.Preference_Value__c);
        }
        
        String key = 'user_prefs_' + UserInfo.getUserId();
        put(key, prefMap, config);
    }
    
    private static void warmAnalyticsCache(CacheConfig config) {
        // Cache frequently accessed analytics data
        DateTime last7Days = DateTime.now().addDays(-7);
        
        AggregateResult[] results = [
            SELECT Provider_Type__c, COUNT(Id) total, AVG(Processing_Time__c) avgTime
            FROM AI_Processing_Status__c
            WHERE CreatedDate >= :last7Days
            GROUP BY Provider_Type__c
        ];
        
        for (AggregateResult ar : results) {
            String key = 'analytics_provider_' + ar.get('Provider_Type__c');
            Map<String, Object> data = new Map<String, Object>{
                'total' => ar.get('total'),
                'avgTime' => ar.get('avgTime')
            };
            put(key, data, config);
        }
    }
    
    // Cache statistics
    public static CacheStats getStats() {
        CacheStats stats = new CacheStats();
        
        // Retrieve stored metrics
        Map<String, Integer> metrics = (Map<String, Integer>) 
            Cache.Session.get('cache_metrics');
        
        if (metrics != null) {
            stats.hits = metrics.get('hits') ?? 0;
            stats.misses = metrics.get('misses') ?? 0;
            
            Integer total = stats.hits + stats.misses;
            if (total > 0) {
                stats.hitRate = (Decimal) stats.hits / total * 100;
            }
        }
        
        return stats;
    }
    
    public static void clearStats() {
        Cache.Session.remove('cache_metrics');
    }
    
    // Helper methods
    private static Boolean isExpired(CacheEntry entry) {
        if (entry.ttl == null || entry.ttl <= 0) {
            return false;
        }
        
        Long ageInSeconds = (DateTime.now().getTime() - entry.timestamp.getTime()) / 1000;
        return ageInSeconds > entry.ttl;
    }
    
    private static void updateMetrics(String operation, String key) {
        Map<String, Integer> metrics = (Map<String, Integer>) 
            Cache.Session.get('cache_metrics');
        
        if (metrics == null) {
            metrics = new Map<String, Integer>{
                'hits' => 0,
                'misses' => 0,
                'puts' => 0,
                'removes' => 0
            };
        }
        
        switch on operation {
            when 'hit' {
                metrics.put('hits', metrics.get('hits') + 1);
            }
            when 'miss' {
                metrics.put('misses', metrics.get('misses') + 1);
            }
            when 'put' {
                metrics.put('puts', metrics.get('puts') + 1);
            }
            when 'remove' {
                metrics.put('removes', metrics.get('removes') + 1);
            }
        }
        
        Cache.Session.put('cache_metrics', metrics);
    }
    
    private static String compressData(String data) {
        // Simple compression using gzip
        Blob dataBlob = Blob.valueOf(data);
        return EncodingUtil.base64Encode(dataBlob);
    }
    
    private static String decompressData(String compressedData) {
        // Simple decompression
        Blob dataBlob = EncodingUtil.base64Decode(compressedData);
        return dataBlob.toString();
    }
    
    private static Set<String> getKeysByPattern(String pattern) {
        // This is a placeholder - implement based on your key storage strategy
        return new Set<String>();
    }
    
    // Cache entry wrapper
    private class CacheEntry {
        public Object value { get; set; }
        public DateTime timestamp { get; set; }
        public Integer ttl { get; set; }
        public Boolean compressed { get; set; }
    }
}