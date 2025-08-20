/**
 * @description Enhanced rate limiter using Platform Cache with database fallback
 * @author RouteLogic Team
 * @date 2025-01-17
 */
public with sharing class AIRateLimiter {
    private static final String CACHE_PARTITION = 'AIRateLimit';
    private static final Integer DEFAULT_TTL = 3600; // 1 hour default
    private static final String RATE_LIMIT_OBJECT = 'AI_Rate_Limit__c';
    
    /**
     * @description Check if the rate limit has been exceeded for a given identifier
     * @param identifier Unique identifier for rate limiting (e.g., user ID, API key)
     * @param limit Maximum number of requests allowed
     * @param windowSeconds Time window in seconds
     * @return Boolean indicating if the request is allowed (true) or rate limited (false)
     */
    public static Boolean checkRateLimit(String identifier, Integer limit, Integer windowSeconds) {
        try {
            // Validate inputs
            if (String.isBlank(identifier) || limit <= 0 || windowSeconds <= 0) {
                throw new AIException('Invalid rate limit parameters');
            }
            
            // Try Platform Cache first
            Cache.OrgPartition orgPart = Cache.Org.getPartition(CACHE_PARTITION);
            return checkRateLimitWithCache(orgPart, identifier, limit, windowSeconds);
            
        } catch (Cache.CacheException e) {
            // Platform Cache unavailable, fall back to database
            
            return checkRateLimitWithDatabase(identifier, limit, windowSeconds);
        } catch (Exception e) {
            // Log error and allow request (fail open)
            ErrorLogService.logError('AIRateLimiter.checkRateLimit', e, identifier);
            return true;
        }
    }
    
    /**
     * @description Check rate limit using Platform Cache
     */
    private static Boolean checkRateLimitWithCache(Cache.OrgPartition orgPart, 
                                                   String identifier, 
                                                   Integer limit, 
                                                   Integer windowSeconds) {
        String cacheKey = generateCacheKey(identifier);
        RateLimitData data = (RateLimitData) orgPart.get(cacheKey);
        
        if (data == null) {
            data = new RateLimitData();
        }
        
        // Clean expired timestamps
        Long currentTime = System.currentTimeMillis();
        data.cleanExpiredTimestamps(currentTime, windowSeconds);
        
        // Check if limit exceeded
        if (data.timestamps.size() >= limit) {
            logRateLimitViolation(identifier, limit, data.timestamps.size());
            return false;
        }
        
        // Add new timestamp and update cache
        data.timestamps.add(currentTime);
        data.lastAccessed = currentTime;
        
        // Store in cache with TTL
        orgPart.put(cacheKey, data, windowSeconds);
        
        return true;
    }
    
    /**
     * @description Check rate limit using database (fallback mechanism)
     */
    private static Boolean checkRateLimitWithDatabase(String identifier, 
                                                     Integer limit, 
                                                     Integer windowSeconds) {
        DateTime cutoffTime = DateTime.now().addSeconds(-windowSeconds);
        
        // Query recent requests
        List<AI_Rate_Limit__c> recentRequests = [
            SELECT Id, Timestamp__c 
            FROM AI_Rate_Limit__c 
            WHERE Identifier__c = :identifier 
            AND Timestamp__c >= :cutoffTime
            WITH SECURITY_ENFORCED
            ORDER BY Timestamp__c DESC
            LIMIT :limit
        ];
        
        // Check if limit exceeded
        if (recentRequests.size() >= limit) {
            logRateLimitViolation(identifier, limit, recentRequests.size());
            return false;
        }
        
        // Create new rate limit record
        AI_Rate_Limit__c newRequest = new AI_Rate_Limit__c(
            Identifier__c = identifier,
            Timestamp__c = DateTime.now(),
            Window_Seconds__c = windowSeconds
        );
        
        // Insert with security checks
        List<AI_Rate_Limit__c> recordsToInsert = new List<AI_Rate_Limit__c>{newRequest};
        recordsToInsert = SecurityUtils.stripInaccessibleRecords(
            AccessType.CREATABLE, 
            recordsToInsert
        );
        
        if (!recordsToInsert.isEmpty()) {
            Database.SaveResult result = Database.insert(recordsToInsert[0], false);
        }
        
        // Clean up old records asynchronously
        if (Math.random() < 0.1) { // 10% chance to trigger cleanup
            cleanupOldRateLimitRecords(identifier, cutoffTime);
        }
        
        return true;
    }
    
    /**
     * @description Generate cache key for identifier
     */
    private static String generateCacheKey(String identifier) {
        return 'rate_' + EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-512', Blob.valueOf(identifier))
        ).substring(0, 16);
    }
    
    /**
     * @description Log rate limit violation
     */
    private static void logRateLimitViolation(String identifier, Integer limit, Integer attempts) {
        AI_Security_Event__c securityEvent = new AI_Security_Event__c(
            Event_Type__c = 'RATE_LIMIT_EXCEEDED',
            Identifier__c = identifier,
            Details__c = String.format(
                'Rate limit exceeded: {0} attempts (limit: {1})',
                new String[]{String.valueOf(attempts), String.valueOf(limit)}
            ),
            Severity__c = 'Medium',
            Timestamp__c = DateTime.now()
        );
        
        // Insert security event with sharing rules
        insert SecurityUtils.stripInaccessibleRecords(
            AccessType.CREATABLE,
            new List<AI_Security_Event__c>{securityEvent}
        )[0];
    }
    
    /**
     * @description Clean up old rate limit records
     */
    @future
    private static void cleanupOldRateLimitRecords(String identifier, DateTime cutoffTime) {
        List<AI_Rate_Limit__c> oldRecords = [
            SELECT Id
            FROM AI_Rate_Limit__c
            WHERE Identifier__c = :identifier
            AND Timestamp__c < :cutoffTime
            WITH SECURITY_ENFORCED
            LIMIT 1000
        ];
        
        if (!oldRecords.isEmpty()) {
            delete SecurityUtils.stripInaccessibleRecords(
                AccessType.DELETABLE,
                oldRecords
            );
        }
    }
    
    /**
     * @description Reset rate limit for an identifier (admin function)
     */
    public static void resetRateLimit(String identifier) {
        // Check admin permissions
        if (!FeatureManagement.checkPermission('AI_Admin_Permission')) {
            throw new InsufficientPrivilegesException('Admin permission required');
        }
        
        try {
            // Clear from cache
            Cache.OrgPartition orgPart = Cache.Org.getPartition(CACHE_PARTITION);
            String cacheKey = generateCacheKey(identifier);
            orgPart.remove(cacheKey);
        } catch (Cache.CacheException e) {
            // Cache not available, continue with database cleanup
        }
        
        // Clear from database
        List<AI_Rate_Limit__c> records = [
            SELECT Id
            FROM AI_Rate_Limit__c
            WHERE Identifier__c = :identifier
            WITH SECURITY_ENFORCED
        ];
        
        if (!records.isEmpty()) {
            delete SecurityUtils.stripInaccessibleRecords(
                AccessType.DELETABLE,
                records
            );
        }
        
        // Log the reset
        AuditService.logAdminAction('RATE_LIMIT_RESET', identifier);
    }
    
    /**
     * @description Inner class to store rate limit data in cache
     */
    public class RateLimitData {
        public List<Long> timestamps { get; set; }
        public Long lastAccessed { get; set; }
        
        public RateLimitData() {
            this.timestamps = new List<Long>();
            this.lastAccessed = System.currentTimeMillis();
        }
        
        /**
         * @description Remove timestamps outside the time window
         */
        public void cleanExpiredTimestamps(Long currentTime, Integer windowSeconds) {
            Long cutoffTime = currentTime - (windowSeconds * 1000);
            List<Long> validTimestamps = new List<Long>();
            
            for (Long timestamp : timestamps) {
                if (timestamp > cutoffTime) {
                    validTimestamps.add(timestamp);
                }
            }
            
            this.timestamps = validTimestamps;
        }
    }
    
    /**
     * @description Get current rate limit status for monitoring
     */
    public static RateLimitStatus getRateLimitStatus(String identifier, Integer limit, Integer windowSeconds) {
        RateLimitStatus status = new RateLimitStatus();
        status.identifier = identifier;
        status.limit = limit;
        status.windowSeconds = windowSeconds;
        
        try {
            Cache.OrgPartition orgPart = Cache.Org.getPartition(CACHE_PARTITION);
            String cacheKey = generateCacheKey(identifier);
            RateLimitData data = (RateLimitData) orgPart.get(cacheKey);
            
            if (data != null) {
                Long currentTime = System.currentTimeMillis();
                data.cleanExpiredTimestamps(currentTime, windowSeconds);
                status.currentCount = data.timestamps.size();
                status.isUsingCache = true;
            }
        } catch (Exception e) {
            // Fall back to database count
            DateTime cutoffTime = DateTime.now().addSeconds(-windowSeconds);
            status.currentCount = [
                SELECT COUNT()
                FROM AI_Rate_Limit__c
                WHERE Identifier__c = :identifier
                AND Timestamp__c >= :cutoffTime
            ];
            status.isUsingCache = false;
        }
        
        status.remaining = Math.max(0, limit - status.currentCount);
        status.percentUsed = (status.currentCount * 100.0) / limit;
        
        return status;
    }
    
    /**
     * @description Rate limit status class for monitoring
     */
    public class RateLimitStatus {
        @AuraEnabled public String identifier { get; set; }
        @AuraEnabled public Integer limit { get; set; }
        @AuraEnabled public Integer windowSeconds { get; set; }
        @AuraEnabled public Integer currentCount { get; set; }
        @AuraEnabled public Integer remaining { get; set; }
        @AuraEnabled public Decimal percentUsed { get; set; }
        @AuraEnabled public Boolean isUsingCache { get; set; }
    }
}