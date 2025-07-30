/**
 * @description Handles rate limit responses and retry logic
 * @author RouteLogic Team
 * @date 2025-01-20
 */
@namespaceAccessible
public with sharing class RateLimitHandler {
    
    /**
     * @description Handle rate limit response
     * @param provider The AI provider name
     * @param response The HTTP response
     * @param attemptNumber Current retry attempt number
     * @return True if should retry, false if max retries exceeded
     */
    public static Boolean handleRateLimitResponse(String provider, HttpResponse response, Integer attemptNumber) {
        // Check if we've exceeded max retries
        Integer maxRetries = ConfigManager.getMaxRateLimitRetries();
        if (attemptNumber >= maxRetries) {
            return false;
        }
        
        // Extract retry delay
        Integer retryAfterSeconds = extractRetryAfter(response);
        
        // Store rate limit info in cache for other processes
        storeRateLimitInfo(provider, retryAfterSeconds);
        
        // Log the rate limit event
        logRateLimitEvent(provider, retryAfterSeconds, attemptNumber);
        
        return true;
    }
    
    /**
     * @description Extract retry-after value from response headers
     * @param response The HTTP response
     * @return Retry delay in seconds
     */
    public static Integer extractRetryAfter(HttpResponse response) {
        // Check standard Retry-After header
        String retryAfterHeader = response.getHeader('Retry-After');
        if (String.isNotBlank(retryAfterHeader)) {
            try {
                return Integer.valueOf(retryAfterHeader);
            } catch (Exception e) {
                // May be HTTP date format, use default
            }
        }
        
        // Check provider-specific headers
        Map<String, String> rateLimitHeaders = new Map<String, String>{
            'X-RateLimit-Reset' => response.getHeader('X-RateLimit-Reset'),
            'X-RateLimit-Reset-After' => response.getHeader('X-RateLimit-Reset-After'),
            'X-Rate-Limit-Reset' => response.getHeader('X-Rate-Limit-Reset')
        };
        
        for (String header : rateLimitHeaders.keySet()) {
            String value = rateLimitHeaders.get(header);
            if (String.isNotBlank(value)) {
                try {
                    // Could be unix timestamp or seconds
                    Long resetValue = Long.valueOf(value);
                    
                    // If value is large, assume it's a timestamp
                    if (resetValue > 10000) {
                        Long currentTime = DateTime.now().getTime() / 1000L;
                        return Math.max(1, Integer.valueOf(resetValue - currentTime));
                    } else {
                        return Integer.valueOf(resetValue);
                    }
                } catch (Exception e) {
                    // Continue to next header
                }
            }
        }
        
        // Default retry after 60 seconds
        return 60;
    }
    
    /**
     * @description Check if provider is currently rate limited
     * @param provider The AI provider name
     * @return True if rate limited
     */
    public static Boolean isRateLimited(String provider) {
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(Constants.CACHE_PARTITION);
            String cacheKey = 'RateLimit_' + provider;
            
            RateLimitInfo info = (RateLimitInfo) partition.get(cacheKey);
            if (info != null && info.resetTime > DateTime.now()) {
                return true;
            }
        } catch (Exception e) {
            // Cache not available
        }
        
        return false;
    }
    
    /**
     * @description Get remaining wait time for rate limited provider
     * @param provider The AI provider name
     * @return Seconds to wait, or 0 if not rate limited
     */
    public static Integer getRemainingWaitTime(String provider) {
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(Constants.CACHE_PARTITION);
            String cacheKey = 'RateLimit_' + provider;
            
            RateLimitInfo info = (RateLimitInfo) partition.get(cacheKey);
            if (info != null && info.resetTime > DateTime.now()) {
                Long remainingMs = info.resetTime.getTime() - DateTime.now().getTime();
                return Math.max(0, Integer.valueOf(remainingMs / 1000L));
            }
        } catch (Exception e) {
            // Cache not available
        }
        
        return 0;
    }
    
    /**
     * @description Store rate limit info in cache
     */
    private static void storeRateLimitInfo(String provider, Integer retryAfterSeconds) {
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(Constants.CACHE_PARTITION);
            String cacheKey = 'RateLimit_' + provider;
            
            RateLimitInfo info = new RateLimitInfo();
            info.provider = provider;
            info.resetTime = DateTime.now().addSeconds(retryAfterSeconds);
            info.hitTime = DateTime.now();
            
            // Store with TTL matching the retry time
            partition.put(cacheKey, info, retryAfterSeconds);
        } catch (Exception e) {
            // Cache not available, continue without caching
            System.debug('Unable to cache rate limit info: ' + e.getMessage());
        }
    }
    
    /**
     * @description Log rate limit event
     */
    private static void logRateLimitEvent(String provider, Integer retryAfterSeconds, Integer attemptNumber) {
        // Publish platform event for monitoring
        EventBus.publish(new AI_Processing_Metric__e(
            Provider__c = provider,
            Request_Status__c = 'Rate_Limited',
            Retry_Count__c = attemptNumber,
            Processing_Time_Ms__c = retryAfterSeconds * 1000
        ));
        
        // Log to debug
        System.debug(LoggingLevel.WARN, String.format(
            'Rate limit hit for provider {0}. Retry after {1} seconds. Attempt {2}',
            new String[]{provider, String.valueOf(retryAfterSeconds), String.valueOf(attemptNumber)}
        ));
    }
    
    /**
     * @description Rate limit info cache object
     */
    public class RateLimitInfo {
        public String provider;
        public DateTime resetTime;
        public DateTime hitTime;
    }
}