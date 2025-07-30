/**
 * @description Configuration manager for AI processing settings
 * @author RouteLogic Team
 * @date 2025-01-20
 */
@namespaceAccessible
public with sharing class ConfigManager {
    
    private static AI_Processing_Config__mdt configCache;
    
    /**
     * @description Get AI processing configuration
     * @return Configuration metadata record
     */
    public static AI_Processing_Config__mdt getConfig() {
        if (configCache == null) {
            configCache = getConfigFromMetadata();
        }
        return configCache;
    }
    
    /**
     * @description Load configuration from custom metadata
     */
    private static AI_Processing_Config__mdt getConfigFromMetadata() {
        List<AI_Processing_Config__mdt> configs = [
            SELECT Default_Batch_Size__c, Max_Concurrent_Jobs__c, 
                   Retry_Delay_Minutes__c, Max_Retry_Attempts__c,
                   Callout_Timeout_Ms__c, Enable_Request_Compression__c,
                   Rate_Limit_TTL_Seconds__c, Compression_Threshold_Bytes__c,
                   Max_Rate_Limit_Retries__c, Enable_IP_Anonymization__c,
                   Error_Log_Retention_Days__c, Audit_Log_Retention_Days__c,
                   Enable_Retention_Notifications__c, Enable_PII_Masking__c,
                   PII_Masking_Regions__c
            FROM AI_Processing_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        
        if (!configs.isEmpty()) {
            return configs[0];
        }
        
        // Return default values if no metadata record exists
        return createDefaultConfig();
    }
    
    /**
     * @description Create default configuration
     */
    private static AI_Processing_Config__mdt createDefaultConfig() {
        AI_Processing_Config__mdt config = new AI_Processing_Config__mdt();
        config.Default_Batch_Size__c = Constants.DEFAULT_BATCH_SIZE;
        config.Max_Concurrent_Jobs__c = Constants.MAX_CONCURRENT_JOBS;
        config.Retry_Delay_Minutes__c = Constants.RETRY_DELAY_MINUTES;
        config.Max_Retry_Attempts__c = Constants.RETRY_ATTEMPTS;
        config.Callout_Timeout_Ms__c = Constants.MAX_CALLOUT_TIME;
        config.Enable_Request_Compression__c = true;
        config.Rate_Limit_TTL_Seconds__c = Constants.DEFAULT_TTL;
        config.Enable_IP_Anonymization__c = false;
        return config;
    }
    
    /**
     * @description Get default batch size
     */
    public static Integer getDefaultBatchSize() {
        AI_Processing_Config__mdt config = getConfig();
        return config.Default_Batch_Size__c != null ? 
            Integer.valueOf(config.Default_Batch_Size__c) : Constants.DEFAULT_BATCH_SIZE;
    }
    
    /**
     * @description Get max concurrent jobs
     */
    public static Integer getMaxConcurrentJobs() {
        AI_Processing_Config__mdt config = getConfig();
        return config.Max_Concurrent_Jobs__c != null ? 
            Integer.valueOf(config.Max_Concurrent_Jobs__c) : Constants.MAX_CONCURRENT_JOBS;
    }
    
    /**
     * @description Get retry delay in minutes
     */
    public static Integer getRetryDelayMinutes() {
        AI_Processing_Config__mdt config = getConfig();
        return config.Retry_Delay_Minutes__c != null ? 
            Integer.valueOf(config.Retry_Delay_Minutes__c) : Constants.RETRY_DELAY_MINUTES;
    }
    
    /**
     * @description Get max retry attempts
     */
    public static Integer getMaxRetryAttempts() {
        AI_Processing_Config__mdt config = getConfig();
        return config.Max_Retry_Attempts__c != null ? 
            Integer.valueOf(config.Max_Retry_Attempts__c) : Constants.RETRY_ATTEMPTS;
    }
    
    /**
     * @description Get callout timeout in milliseconds
     */
    public static Integer getCalloutTimeoutMs() {
        AI_Processing_Config__mdt config = getConfig();
        return config.Callout_Timeout_Ms__c != null ? 
            Integer.valueOf(config.Callout_Timeout_Ms__c) : Constants.MAX_CALLOUT_TIME;
    }
    
    /**
     * @description Check if request compression is enabled
     */
    public static Boolean isCompressionEnabled() {
        AI_Processing_Config__mdt config = getConfig();
        return config.Enable_Request_Compression__c != null ? 
            config.Enable_Request_Compression__c : true;
    }
    
    /**
     * @description Get rate limit TTL in seconds
     */
    public static Integer getRateLimitTTL() {
        AI_Processing_Config__mdt config = getConfig();
        return config.Rate_Limit_TTL_Seconds__c != null ? 
            Integer.valueOf(config.Rate_Limit_TTL_Seconds__c) : Constants.DEFAULT_TTL;
    }
    
    /**
     * @description Get compression threshold in bytes
     */
    public static Integer getCompressionThreshold() {
        AI_Processing_Config__mdt config = getConfig();
        return config.Compression_Threshold_Bytes__c != null ? 
            Integer.valueOf(config.Compression_Threshold_Bytes__c) : 5120; // Default 5KB
    }
    
    /**
     * @description Get max rate limit retries
     */
    public static Integer getMaxRateLimitRetries() {
        AI_Processing_Config__mdt config = getConfig();
        return config.Max_Rate_Limit_Retries__c != null ? 
            Integer.valueOf(config.Max_Rate_Limit_Retries__c) : 3;
    }
    
    /**
     * @description Check if IP anonymization is enabled
     */
    public static Boolean isIPAnonymizationEnabled() {
        AI_Processing_Config__mdt config = getConfig();
        return config.Enable_IP_Anonymization__c != null ? 
            config.Enable_IP_Anonymization__c : false;
    }
    
    /**
     * @description Get error log retention days
     */
    public static Integer getErrorLogRetentionDays() {
        AI_Processing_Config__mdt config = getConfig();
        return config.Error_Log_Retention_Days__c != null ? 
            Integer.valueOf(config.Error_Log_Retention_Days__c) : 30;
    }
    
    /**
     * @description Get audit log retention days
     */
    public static Integer getAuditLogRetentionDays() {
        AI_Processing_Config__mdt config = getConfig();
        return config.Audit_Log_Retention_Days__c != null ? 
            Integer.valueOf(config.Audit_Log_Retention_Days__c) : 365;
    }
    
    /**
     * @description Check if retention notifications are enabled
     */
    public static Boolean isRetentionNotificationEnabled() {
        AI_Processing_Config__mdt config = getConfig();
        return config.Enable_Retention_Notifications__c != null ? 
            config.Enable_Retention_Notifications__c : true;
    }
    
    /**
     * @description Check if PII masking is enabled
     */
    public static Boolean isPIIMaskingEnabled() {
        AI_Processing_Config__mdt config = getConfig();
        return config.Enable_PII_Masking__c != null ? 
            config.Enable_PII_Masking__c : false;
    }
    
    /**
     * @description Get PII masking regions
     */
    public static Set<String> getPIIMaskingRegions() {
        AI_Processing_Config__mdt config = getConfig();
        Set<String> regions = new Set<String>();
        
        if (String.isNotBlank(config.PII_Masking_Regions__c)) {
            for (String region : config.PII_Masking_Regions__c.split(',')) {
                regions.add(region.trim().toUpperCase());
            }
        }
        
        return regions;
    }
    
    /**
     * @description Clear configuration cache
     */
    @TestVisible
    private static void clearCache() {
        configCache = null;
    }
}