/**
 * @description Centralized constants for RouteLogic Enhanced application
 * @author RouteLogic Team
 * @date 2025-01-20
 */
@namespaceAccessible
public with sharing class Constants {
    
    // Batch Processing Constants
    public static final Integer DEFAULT_BATCH_SIZE = 200;
    public static final Integer OPTIMAL_BATCH_SIZE = 200;
    public static final Integer MAX_BATCH_SIZE = 2000;
    public static final Integer QUERY_CHUNK_SIZE = 2000;
    public static final Integer PLATFORM_EVENT_BATCH_SIZE = 1000;
    public static final Integer BATCH_THRESHOLD = 50;
    
    // Concurrent Processing Constants
    public static final Integer MAX_CONCURRENT_JOBS = 5;
    
    // Retry Configuration
    public static final Integer RETRY_ATTEMPTS = 3;
    public static final Integer RETRY_DELAY_MINUTES = 5;
    
    // Timeout Configuration
    public static final Integer MAX_CALLOUT_TIME = 30000; // 30 seconds
    public static final Integer SESSION_TIMEOUT_MINUTES = 30;
    
    // Rate Limiting Configuration
    public static final String CACHE_PARTITION = 'AIRateLimit';
    public static final Integer DEFAULT_TTL = 3600; // 1 hour
    public static final Integer CACHE_PARTITION_SIZE_MB = 10;
    
    // Security Configuration
    public static final Integer KEY_SIZE = 256;
    public static final Integer KEY_ROTATION_DAYS = 90;
    public static final Integer KEY_RETENTION_DAYS = 365;
    
    // String Length Limits
    public static final Integer MAX_MESSAGE_LENGTH = 255;
    public static final Integer MAX_STACK_TRACE_LENGTH = 32768;
    
    // Orphaned Case Detection
    public static final Integer ORPHANED_THRESHOLD_HOURS = 24;
    public static final String ORPHANED_STATUS = 'AI Processing Orphaned';
    
    // Conversation Service
    public static final Integer MAX_ENTRIES_PER_SESSION = 1000;
    
    // Trigger Control
    public static final Integer MAX_TRIGGER_EXECUTIONS = 5;
    
    // Package Configuration
    public static final String PACKAGE_NAMESPACE = 'routelogic';
    
    // Provider Names
    public static final String PROVIDER_ADA = 'Ada';
    public static final String PROVIDER_INTERCOM = 'Intercom';
    public static final String PROVIDER_OPENAI = 'OpenAI';
    public static final String PROVIDER_AZURE = 'Azure_Cognitive';
    public static final String PROVIDER_AWS = 'AWS_Comprehend';
    
    // Provider Rate Limits
    public static final Map<String, RateLimitConfig> PROVIDER_RATE_LIMITS = new Map<String, RateLimitConfig>{
        PROVIDER_ADA => new RateLimitConfig(100, 3600), // 100 requests per hour
        PROVIDER_INTERCOM => new RateLimitConfig(83, 10), // 83 requests per 10 seconds
        PROVIDER_OPENAI => new RateLimitConfig(60, 60), // 60 requests per minute
        PROVIDER_AZURE => new RateLimitConfig(100, 60), // 100 requests per minute
        PROVIDER_AWS => new RateLimitConfig(50, 60) // 50 requests per minute
    };
    
    // Audit Event Types
    public static final String EVENT_KEY_ROTATION = 'KEY_ROTATION';
    public static final String EVENT_EMERGENCY_KEY_ROTATION = 'EMERGENCY_KEY_ROTATION';
    public static final String EVENT_KEY_CLEANUP = 'KEY_CLEANUP';
    public static final String EVENT_ACCESS_VIOLATION = 'ACCESS_VIOLATION';
    public static final String EVENT_DATA_EXPORT = 'DATA_EXPORT';
    public static final String EVENT_PERMISSION_CHANGE = 'PERMISSION_CHANGE';
    public static final String EVENT_FAILED_LOGIN = 'FAILED_LOGIN';
    public static final String EVENT_API_ACCESS = 'API_ACCESS';
    
    // Error Codes
    public static final String RATE_LIMIT_ERROR = 'AI_RATE_LIMIT';
    public static final String AUTHENTICATION_ERROR = 'AI_AUTH_ERROR';
    public static final String VALIDATION_ERROR = 'AI_VALIDATION_ERROR';
    public static final String PROVIDER_ERROR = 'AI_PROVIDER_ERROR';
    public static final String CONFIGURATION_ERROR = 'AI_CONFIG_ERROR';
    public static final String SECURITY_ERROR = 'AI_SECURITY_ERROR';
    public static final String PROCESSING_ERROR = 'AI_PROCESSING_ERROR';
    public static final String TIMEOUT_ERROR = 'AI_TIMEOUT_ERROR';
    
    // HTTP Status Codes
    public static final Integer HTTP_OK = 200;
    public static final Integer HTTP_CREATED = 201;
    public static final Integer HTTP_ACCEPTED = 202;
    public static final Integer HTTP_BAD_REQUEST = 400;
    public static final Integer HTTP_UNAUTHORIZED = 401;
    public static final Integer HTTP_FORBIDDEN = 403;
    public static final Integer HTTP_NOT_FOUND = 404;
    public static final Integer HTTP_TOO_MANY_REQUESTS = 429;
    public static final Integer HTTP_INTERNAL_ERROR = 500;
    public static final Integer HTTP_SERVICE_UNAVAILABLE = 503;
    
    // Retry Status Codes
    public static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{
        HTTP_TOO_MANY_REQUESTS,
        HTTP_INTERNAL_ERROR,
        HTTP_SERVICE_UNAVAILABLE,
        408, // Request Timeout
        502, // Bad Gateway
        504  // Gateway Timeout
    };
    
    /**
     * @description Rate limit configuration for providers
     */
    public class RateLimitConfig {
        public Integer requests { get; private set; }
        public Integer windowSeconds { get; private set; }
        
        public RateLimitConfig(Integer requests, Integer windowSeconds) {
            this.requests = requests;
            this.windowSeconds = windowSeconds;
        }
    }
}