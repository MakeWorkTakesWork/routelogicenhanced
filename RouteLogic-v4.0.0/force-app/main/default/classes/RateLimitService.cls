/**
 * @description Enhanced rate limiting service for RouteLogic Enhanced
 * @author RouteLogic Security Team
 * @date 2025-01-30
 * @version 4.0.0
 * 
 * Implements multi-tier rate limiting: user-level, IP-level, and operation-specific
 * with DDoS protection and adaptive throttling.
 */
public with sharing class RateLimitService {
    
    // Rate limit configurations
    private static final Map<String, RateLimitConfig> RATE_LIMITS = new Map<String, RateLimitConfig>{
        'API_CALL' => new RateLimitConfig(100, 60), // 100 calls per minute
        'BULK_OPERATION' => new RateLimitConfig(10, 300), // 10 bulk ops per 5 minutes
        'AUTH_ATTEMPT' => new RateLimitConfig(5, 300), // 5 auth attempts per 5 minutes
        'DATA_EXPORT' => new RateLimitConfig(20, 3600), // 20 exports per hour
        'WEBHOOK_RECEIVE' => new RateLimitConfig(1000, 60), // 1000 webhooks per minute
        'ENCRYPTION_OP' => new RateLimitConfig(50, 60) // 50 encryption ops per minute
    };
    
    // DDoS protection thresholds
    private static final Integer DDOS_THRESHOLD_PER_IP = 5000; // Per hour
    private static final Integer DDOS_THRESHOLD_GLOBAL = 50000; // Per hour
    
    /**
     * @description Check if operation is allowed under rate limits
     * @param operation Operation type
     * @param identifier User ID or IP address
     * @return True if operation is allowed
     */
    public static Boolean checkRateLimit(String operation, String identifier) {
        return checkRateLimit(operation, identifier, 1);
    }
    
    /**
     * @description Check if operation is allowed under rate limits with count
     * @param operation Operation type
     * @param identifier User ID or IP address
     * @param count Number of operations
     * @return True if operation is allowed
     */
    public static Boolean checkRateLimit(String operation, String identifier, Integer count) {
        try {
            // Get rate limit config
            RateLimitConfig config = RATE_LIMITS.get(operation);
            if (config == null) {
                // No rate limit defined for this operation
                return true;
            }
            
            // Check user-level limit
            String userKey = 'USER_' + identifier + '_' + operation;
            if (!checkLimit(userKey, config, count)) {
                logRateLimitExceeded(operation, identifier, 'USER');
                return false;
            }
            
            // Check IP-level limit if available
            String ipAddress = getCurrentIPAddress();
            if (String.isNotBlank(ipAddress)) {
                String ipKey = 'IP_' + ipAddress + '_' + operation;
                if (!checkLimit(ipKey, config, count)) {
                    logRateLimitExceeded(operation, ipAddress, 'IP');
                    return false;
                }
                
                // Check DDoS protection
                if (!checkDDoSProtection(ipAddress)) {
                    logDDoSAttempt(ipAddress);
                    return false;
                }
            }
            
            // Check operation-specific global limit
            String globalKey = 'GLOBAL_' + operation;
            RateLimitConfig globalConfig = new RateLimitConfig(
                config.limit * 100, // 100x individual limit
                config.windowSeconds
            );
            if (!checkLimit(globalKey, globalConfig, count)) {
                logRateLimitExceeded(operation, 'GLOBAL', 'GLOBAL');
                return false;
            }
            
            return true;
            
        } catch (Exception e) {
            // Don't let rate limiting errors break the flow
            System.debug(LoggingLevel.ERROR, 'Rate limit check failed: ' + e.getMessage());
            return true; // Fail open
        }
    }
    
    /**
     * @description Check limit for a specific key
     * @param key Cache key
     * @param config Rate limit configuration
     * @param count Number of operations
     * @return True if within limit
     */
    private static Boolean checkLimit(String key, RateLimitConfig config, Integer count) {
        // Get current counter from Platform Cache using CacheUtils
        Object cachedValue = CacheUtils.get(CacheUtils.PARTITION_RATE_LIMITS, key);
        
        if (cachedValue == null && !CacheUtils.contains(CacheUtils.PARTITION_RATE_LIMITS, key)) {
            // Cache partition not available, use in-memory tracking
            Cache.OrgPartition testPartition = CacheUtils.getPartition(CacheUtils.PARTITION_RATE_LIMITS);
            if (testPartition == null) {
                return checkLimitInMemory(key, config, count);
            }
        }
        
        // Get current count
        Integer currentCount = cachedValue != null ? (Integer) cachedValue : 0;
        
        // Check if adding count would exceed limit
        if (currentCount + count > config.limit) {
            return false;
        }
        
        // Increment counter using CacheUtils
        CacheUtils.put(CacheUtils.PARTITION_RATE_LIMITS, key, currentCount + count, config.windowSeconds);
        
        return true;
    }
    
    /**
     * @description In-memory rate limit tracking (fallback)
     */
    private static Map<String, RateLimitEntry> inMemoryLimits = new Map<String, RateLimitEntry>();
    
    private static Boolean checkLimitInMemory(String key, RateLimitConfig config, Integer count) {
        RateLimitEntry entry = inMemoryLimits.get(key);
        DateTime now = DateTime.now();
        
        if (entry == null || entry.windowStart.addSeconds(config.windowSeconds) < now) {
            // New window
            entry = new RateLimitEntry();
            entry.windowStart = now;
            entry.count = count;
            inMemoryLimits.put(key, entry);
            return true;
        }
        
        // Check if adding count would exceed limit
        if (entry.count + count > config.limit) {
            return false;
        }
        
        entry.count += count;
        return true;
    }
    
    /**
     * @description Check DDoS protection
     * @param ipAddress IP address to check
     * @return True if not under DDoS attack
     */
    private static Boolean checkDDoSProtection(String ipAddress) {
        // Check IP-level DDoS
        String ipDDoSKey = 'DDOS_IP_' + ipAddress;
        RateLimitConfig ddosConfig = new RateLimitConfig(DDOS_THRESHOLD_PER_IP, 3600);
        
        if (!checkLimit(ipDDoSKey, ddosConfig, 1)) {
            return false;
        }
        
        // Check global DDoS
        String globalDDoSKey = 'DDOS_GLOBAL';
        RateLimitConfig globalDDoSConfig = new RateLimitConfig(DDOS_THRESHOLD_GLOBAL, 3600);
        
        return checkLimit(globalDDoSKey, globalDDoSConfig, 1);
    }
    
    /**
     * @description Reset rate limit for identifier
     * @param operation Operation type
     * @param identifier User ID or IP address
     */
    public static void resetRateLimit(String operation, String identifier) {
        try {
            // Remove user key using CacheUtils
            String userKey = 'USER_' + identifier + '_' + operation;
            CacheUtils.remove(CacheUtils.PARTITION_RATE_LIMITS, userKey);
            
            // Remove IP key if available
            String ipAddress = getCurrentIPAddress();
            if (String.isNotBlank(ipAddress)) {
                String ipKey = 'IP_' + ipAddress + '_' + operation;
                CacheUtils.remove(CacheUtils.PARTITION_RATE_LIMITS, ipKey);
            }
            
            // Also clear in-memory
            inMemoryLimits.clear();
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to reset rate limit: ' + e.getMessage());
        }
    }
    
    /**
     * @description Get current usage for an operation
     * @param operation Operation type
     * @param identifier User ID or IP address
     * @return Current usage count
     */
    public static Integer getCurrentUsage(String operation, String identifier) {
        try {
            String userKey = 'USER_' + identifier + '_' + operation;
            
            // Get count using CacheUtils
            Object cachedValue = CacheUtils.get(CacheUtils.PARTITION_RATE_LIMITS, userKey);
            if (cachedValue != null) {
                return (Integer) cachedValue;
            }
            
            // Check in-memory
            RateLimitEntry entry = inMemoryLimits.get(userKey);
            if (entry != null) {
                RateLimitConfig config = RATE_LIMITS.get(operation);
                if (config != null && entry.windowStart.addSeconds(config.windowSeconds) >= DateTime.now()) {
                    return entry.count;
                }
            }
            
            return 0;
            
        } catch (Exception e) {
            return 0;
        }
    }
    
    /**
     * @description Get rate limit info for an operation
     * @param operation Operation type
     * @return Rate limit configuration
     */
    public static RateLimitConfig getRateLimitConfig(String operation) {
        return RATE_LIMITS.get(operation);
    }
    
    /**
     * @description Apply adaptive throttling based on system load
     * @param operation Operation type
     * @param systemLoad Current system load (0-100)
     */
    public static void applyAdaptiveThrottling(String operation, Integer systemLoad) {
        RateLimitConfig config = RATE_LIMITS.get(operation);
        if (config != null) {
            // Reduce limits when system is under load
            if (systemLoad > 80) {
                config.limit = (Integer)(config.limit * 0.5); // 50% reduction
            } else if (systemLoad > 60) {
                config.limit = (Integer)(config.limit * 0.75); // 25% reduction
            }
            
            // Store adjusted config in cache using CacheUtils
            CacheUtils.put(
                CacheUtils.PARTITION_RATE_LIMITS,
                'CONFIG_' + operation,
                config,
                300 // 5 minute TTL
            );
        }
    }
    
    /**
     * @description Get current IP address
     * @return IP address or null
     */
    private static String getCurrentIPAddress() {
        try {
            if (ApexPages.currentPage() != null) {
                Map<String, String> headers = ApexPages.currentPage().getHeaders();
                String ip = headers.get('X-Forwarded-For');
                if (String.isBlank(ip)) {
                    ip = headers.get('X-Real-IP');
                }
                return ip;
            }
            return null;
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * @description Log rate limit exceeded event
     */
    private static void logRateLimitExceeded(String operation, String identifier, String level) {
        SecurityAuditService.logRateLimitExceeded(
            operation + '_' + level,
            getCurrentUsage(operation, identifier),
            RATE_LIMITS.get(operation).limit
        );
    }
    
    /**
     * @description Log DDoS attempt
     */
    private static void logDDoSAttempt(String ipAddress) {
        Map<String, Object> details = new Map<String, Object>{
            'ipAddress' => ipAddress,
            'threshold' => DDOS_THRESHOLD_PER_IP,
            'timestamp' => DateTime.now()
        };
        
        SecurityAuditService.logSecurityViolation('DDoS_Attempt', details);
    }
    
    /**
     * @description Rate limit configuration
     */
    public class RateLimitConfig {
        public Integer limit { get; set; }
        public Integer windowSeconds { get; set; }
        
        public RateLimitConfig(Integer limit, Integer windowSeconds) {
            this.limit = limit;
            this.windowSeconds = windowSeconds;
        }
    }
    
    /**
     * @description In-memory rate limit entry
     */
    private class RateLimitEntry {
        public DateTime windowStart;
        public Integer count;
    }
    
    /**
     * @description Scheduled job to clean up expired rate limit entries
     */
    public static void cleanupExpiredEntries() {
        // Clean up in-memory entries
        DateTime now = DateTime.now();
        Set<String> keysToRemove = new Set<String>();
        
        for (String key : inMemoryLimits.keySet()) {
            RateLimitEntry entry = inMemoryLimits.get(key);
            
            // Find the appropriate config based on key
            for (String operation : RATE_LIMITS.keySet()) {
                if (key.contains(operation)) {
                    RateLimitConfig config = RATE_LIMITS.get(operation);
                    if (entry.windowStart.addSeconds(config.windowSeconds) < now) {
                        keysToRemove.add(key);
                    }
                    break;
                }
            }
        }
        
        for (String key : keysToRemove) {
            inMemoryLimits.remove(key);
        }
    }
}