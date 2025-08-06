/**
 * @description Enterprise rate limiting and resource management service
 * @author RouteLogic Team
 * @date 2025-02-05
 * @enterprise Implements comprehensive rate limiting, throttling, and resource management
 */
public with sharing class AIRateLimitingService {
    
    // Rate limiting configuration
    private static final Integer DEFAULT_REQUESTS_PER_MINUTE = 60;
    private static final Integer DEFAULT_REQUESTS_PER_HOUR = 1000;
    private static final Integer DEFAULT_REQUESTS_PER_DAY = 10000;
    
    // Resource limits
    private static final Integer MAX_HEAP_SIZE_MB = 6;
    private static final Integer MAX_CPU_TIME_MS = 10000;
    private static final Integer MAX_DML_STATEMENTS = 150;
    private static final Integer MAX_SOQL_QUERIES = 100;
    
    // Cache keys for rate limiting
    private static final String CACHE_PREFIX = 'AIRateLimit_';
    private static final String MINUTE_SUFFIX = '_minute';
    private static final String HOUR_SUFFIX = '_hour';
    private static final String DAY_SUFFIX = '_day';
    
    /**
     * @description Rate limit configuration
     */
    public class RateLimitConfig {
        public Integer requestsPerMinute { get; set; }
        public Integer requestsPerHour { get; set; }
        public Integer requestsPerDay { get; set; }
        public String identifier { get; set; }
        
        public RateLimitConfig(String id) {
            this.identifier = id;
            this.requestsPerMinute = DEFAULT_REQUESTS_PER_MINUTE;
            this.requestsPerHour = DEFAULT_REQUESTS_PER_HOUR;
            this.requestsPerDay = DEFAULT_REQUESTS_PER_DAY;
        }
    }
    
    /**
     * @description Rate limit result
     */
    public class RateLimitResult {
        public Boolean allowed { get; set; }
        public String reason { get; set; }
        public Integer remainingRequests { get; set; }
        public DateTime resetTime { get; set; }
        public String limitType { get; set; }
        
        public RateLimitResult() {
            this.allowed = true;
            this.remainingRequests = 0;
        }
    }
    
    /**
     * @description Resource usage tracking
     */
    public class ResourceUsage {
        public Integer heapUsedMB { get; set; }
        public Integer cpuTimeUsed { get; set; }
        public Integer dmlStatementsUsed { get; set; }
        public Integer soqlQueriesUsed { get; set; }
        public Decimal heapUsagePercent { get; set; }
        public Decimal cpuUsagePercent { get; set; }
        public Boolean withinLimits { get; set; }
        
        public ResourceUsage() {
            this.heapUsedMB = Limits.getHeapSize() / (1024 * 1024);
            this.cpuTimeUsed = Limits.getCpuTime();
            this.dmlStatementsUsed = Limits.getDmlStatements();
            this.soqlQueriesUsed = Limits.getQueries();
            
            this.heapUsagePercent = (Decimal.valueOf(this.heapUsedMB) / MAX_HEAP_SIZE_MB) * 100;
            this.cpuUsagePercent = (Decimal.valueOf(this.cpuTimeUsed) / MAX_CPU_TIME_MS) * 100;
            
            this.withinLimits = this.heapUsedMB < MAX_HEAP_SIZE_MB && 
                               this.cpuTimeUsed < MAX_CPU_TIME_MS &&
                               this.dmlStatementsUsed < MAX_DML_STATEMENTS &&
                               this.soqlQueriesUsed < MAX_SOQL_QUERIES;
        }
    }
    
    /**
     * @description Check if request is allowed based on rate limits
     * @param config Rate limit configuration
     * @return RateLimitResult
     */
    public static RateLimitResult checkRateLimit(RateLimitConfig config) {
        RateLimitResult result = new RateLimitResult();
        
        try {
            // Check minute limit
            RateLimitResult minuteCheck = checkTimeBasedLimit(
                config.identifier, 
                config.requestsPerMinute, 
                MINUTE_SUFFIX, 
                60
            );
            
            if (!minuteCheck.allowed) {
                return minuteCheck;
            }
            
            // Check hour limit
            RateLimitResult hourCheck = checkTimeBasedLimit(
                config.identifier, 
                config.requestsPerHour, 
                HOUR_SUFFIX, 
                3600
            );
            
            if (!hourCheck.allowed) {
                return hourCheck;
            }
            
            // Check day limit
            RateLimitResult dayCheck = checkTimeBasedLimit(
                config.identifier, 
                config.requestsPerDay, 
                DAY_SUFFIX, 
                86400
            );
            
            if (!dayCheck.allowed) {
                return dayCheck;
            }
            
            // All checks passed - increment counters
            incrementCounter(config.identifier, MINUTE_SUFFIX, 60);
            incrementCounter(config.identifier, HOUR_SUFFIX, 3600);
            incrementCounter(config.identifier, DAY_SUFFIX, 86400);
            
            result.allowed = true;
            result.remainingRequests = Math.min(
                Math.min(minuteCheck.remainingRequests, hourCheck.remainingRequests),
                dayCheck.remainingRequests
            );
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Rate limit check failed: ' + e.getMessage());
            // Fail open - allow request if rate limiting fails
            result.allowed = true;
            result.reason = 'Rate limiting service unavailable';
        }
        
        return result;
    }
    
    /**
     * @description Check time-based rate limit
     * @param identifier Unique identifier for rate limiting
     * @param requestLimit Request limit for time period
     * @param suffix Time period suffix
     * @param seconds Time period in seconds
     * @return RateLimitResult
     */
    private static RateLimitResult checkTimeBasedLimit(String identifier, Integer requestLimit, String suffix, Integer seconds) {
        RateLimitResult result = new RateLimitResult();
        String cacheKey = CACHE_PREFIX + identifier + suffix;
        
        try {
            // Get current count from platform cache
            Integer currentCount = getCurrentCount(cacheKey);
            
            if (currentCount >= requestLimit) {
                result.allowed = false;
                result.reason = 'Rate limit exceeded for ' + suffix.replace('_', '');
                result.remainingRequests = 0;
                result.resetTime = DateTime.now().addSeconds(seconds);
                result.limitType = suffix.replace('_', '');
            } else {
                result.allowed = true;
                result.remainingRequests = requestLimit - currentCount;
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Failed to check rate limit for ' + cacheKey + ': ' + e.getMessage());
            // Fail open
            result.allowed = true;
        }
        
        return result;
    }
    
    /**
     * @description Get current count from cache
     * @param cacheKey Cache key
     * @return Current count
     */
    private static Integer getCurrentCount(String cacheKey) {
        try {
            Object cachedValue = Cache.Org.get(cacheKey);
            return cachedValue != null ? (Integer) cachedValue : 0;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Failed to get cache value for ' + cacheKey + ': ' + e.getMessage());
            return 0;
        }
    }
    
    /**
     * @description Increment counter in cache
     * @param identifier Unique identifier
     * @param suffix Time period suffix
     * @param ttlSeconds TTL in seconds
     */
    private static void incrementCounter(String identifier, String suffix, Integer ttlSeconds) {
        String cacheKey = CACHE_PREFIX + identifier + suffix;
        
        try {
            Integer currentCount = getCurrentCount(cacheKey);
            Cache.Org.put(cacheKey, currentCount + 1, ttlSeconds);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Failed to increment counter for ' + cacheKey + ': ' + e.getMessage());
        }
    }
    
    /**
     * @description Check resource usage and limits
     * @return ResourceUsage
     */
    public static ResourceUsage checkResourceUsage() {
        return new ResourceUsage();
    }
    
    /**
     * @description Check if operation can proceed based on resource limits
     * @param estimatedHeapMB Estimated heap usage in MB
     * @param estimatedCpuMs Estimated CPU time in milliseconds
     * @return Boolean indicating if operation can proceed
     */
    public static Boolean canProceedWithOperation(Integer estimatedHeapMB, Integer estimatedCpuMs) {
        ResourceUsage current = checkResourceUsage();
        
        Integer projectedHeap = current.heapUsedMB + estimatedHeapMB;
        Integer projectedCpu = current.cpuTimeUsed + estimatedCpuMs;
        
        return projectedHeap < MAX_HEAP_SIZE_MB && 
               projectedCpu < MAX_CPU_TIME_MS &&
               current.dmlStatementsUsed < (MAX_DML_STATEMENTS * 0.8) &&
               current.soqlQueriesUsed < (MAX_SOQL_QUERIES * 0.8);
    }
    
    /**
     * @description Get rate limit configuration for user/org
     * @param userId User ID
     * @param orgId Organization ID
     * @return RateLimitConfig
     */
    public static RateLimitConfig getRateLimitConfig(String userId, String orgId) {
        // Create identifier combining user and org
        String identifier = userId + '_' + orgId;
        RateLimitConfig config = new RateLimitConfig(identifier);
        
        try {
            // Try to get custom configuration from custom metadata
            List<AI_Processing_Config__mdt> configs = [
                SELECT DeveloperName, MasterLabel
                FROM AI_Processing_Config__mdt 
                WHERE DeveloperName = 'Default_Rate_Limits'
                LIMIT 1
            ];
            
            if (!configs.isEmpty()) {
                // Use default configuration for now
                // In a real implementation, you would add custom fields for rate limits
                System.debug(LoggingLevel.INFO, 'Using default rate limit configuration');
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Failed to get custom rate limit config: ' + e.getMessage());
            // Use defaults
        }
        
        return config;
    }
    
    /**
     * @description Get rate limit configuration for current user
     * @return RateLimitConfig
     */
    public static RateLimitConfig getCurrentUserRateLimitConfig() {
        return getRateLimitConfig(UserInfo.getUserId(), UserInfo.getOrganizationId());
    }
    
    /**
     * @description Check if current user can make request
     * @return RateLimitResult
     */
    public static RateLimitResult checkCurrentUserRateLimit() {
        RateLimitConfig config = getCurrentUserRateLimitConfig();
        return checkRateLimit(config);
    }
    
    /**
     * @description Throttle execution based on current load
     * @param operationType Type of operation for throttling
     * @return Boolean indicating if operation should be throttled
     */
    public static Boolean shouldThrottle(String operationType) {
        ResourceUsage usage = checkResourceUsage();
        
        // Throttle if resource usage is high
        if (usage.heapUsagePercent > 80 || usage.cpuUsagePercent > 80) {
            System.debug(LoggingLevel.INFO, 'Throttling ' + operationType + 
                        ' due to high resource usage. Heap: ' + usage.heapUsagePercent + 
                        '%, CPU: ' + usage.cpuUsagePercent + '%');
            return true;
        }
        
        // Check rate limits
        RateLimitResult rateLimitResult = checkCurrentUserRateLimit();
        if (!rateLimitResult.allowed) {
            System.debug(LoggingLevel.INFO, 'Throttling ' + operationType + 
                        ' due to rate limit: ' + rateLimitResult.reason);
            return true;
        }
        
        return false;
    }
    
    /**
     * @description Get throttling delay in milliseconds
     * @param operationType Type of operation
     * @return Integer delay in milliseconds
     */
    public static Integer getThrottlingDelay(String operationType) {
        ResourceUsage usage = checkResourceUsage();
        
        // Base delay of 100ms
        Integer delay = 100;
        
        // Increase delay based on resource usage
        if (usage.heapUsagePercent > 80) {
            delay += Integer.valueOf(usage.heapUsagePercent * 10);
        }
        
        if (usage.cpuUsagePercent > 80) {
            delay += Integer.valueOf(usage.cpuUsagePercent * 5);
        }
        
        // Cap at 5 seconds
        return Math.min(delay, 5000);
    }
    
    /**
     * @description Reset rate limits for identifier (admin function)
     * @param identifier Rate limit identifier
     */
    public static void resetRateLimits(String identifier) {
        try {
            Cache.Org.remove(CACHE_PREFIX + identifier + MINUTE_SUFFIX);
            Cache.Org.remove(CACHE_PREFIX + identifier + HOUR_SUFFIX);
            Cache.Org.remove(CACHE_PREFIX + identifier + DAY_SUFFIX);
            
            System.debug(LoggingLevel.INFO, 'Rate limits reset for identifier: ' + identifier);
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to reset rate limits for ' + identifier + ': ' + e.getMessage());
        }
    }
    
    /**
     * @description Get rate limit status for monitoring
     * @param identifier Rate limit identifier
     * @return Map of current usage
     */
    public static Map<String, Object> getRateLimitStatus(String identifier) {
        Map<String, Object> status = new Map<String, Object>();
        
        try {
            status.put('minuteCount', getCurrentCount(CACHE_PREFIX + identifier + MINUTE_SUFFIX));
            status.put('hourCount', getCurrentCount(CACHE_PREFIX + identifier + HOUR_SUFFIX));
            status.put('dayCount', getCurrentCount(CACHE_PREFIX + identifier + DAY_SUFFIX));
            status.put('timestamp', DateTime.now());
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to get rate limit status: ' + e.getMessage());
            status.put('error', e.getMessage());
        }
        
        return status;
    }
}

