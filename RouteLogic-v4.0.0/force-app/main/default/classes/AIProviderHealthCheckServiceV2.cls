/**
 * @description Service class for performing health checks on AI providers (V2 - BaseAIService)
 * @author RouteLogic Enhanced
 * @version 4.0.0
 * @date 2025-01-31
 * 
 * This is the migrated version using BaseAIService for enhanced security
 */
public with sharing class AIProviderHealthCheckServiceV2 extends BaseAIService {
    
    public static final String STATUS_HEALTHY = 'Healthy';
    public static final String STATUS_DEGRADED = 'Degraded';
    public static final String STATUS_UNHEALTHY = 'Unhealthy';
    public static final String STATUS_UNKNOWN = 'Unknown';
    
    // Feature flag to control rollout
    private static final String FEATURE_FLAG_KEY = 'UseHealthCheckV2';
    
    /**
     * @description Check if V2 service should be used
     * @return True if V2 is enabled
     */
    public static Boolean isV2Enabled() {
        // Check feature flag from custom settings or metadata
        AI_Feature_Flag__mdt flag = getFeatureFlag(FEATURE_FLAG_KEY);
        return flag != null && flag.Is_Enabled__c;
    }
    
    /**
     * @description Performs health check for all active AI providers
     * @return Map of provider names to their health check results
     */
    public static Map<String, HealthCheckResult> checkAllProviders() {
        // Use feature flag to determine which version to use
        if (!isV2Enabled()) {
            return AIProviderHealthCheckService.checkAllProviders();
        }
        
        AIProviderHealthCheckServiceV2 service = new AIProviderHealthCheckServiceV2();
        return (Map<String, HealthCheckResult>) service.processRequest(new HealthCheckRequest('ALL'));
    }
    
    /**
     * @description Performs health check for a specific provider
     * @param providerName The name of the provider to check
     * @return Health check result for the provider
     */
    public static HealthCheckResult checkProviderByName(String providerName) {
        // Use feature flag to determine which version to use
        if (!isV2Enabled()) {
            return AIProviderHealthCheckService.checkProviderByName(providerName);
        }
        
        AIProviderHealthCheckServiceV2 service = new AIProviderHealthCheckServiceV2();
        Map<String, HealthCheckResult> results = (Map<String, HealthCheckResult>) 
            service.processRequest(new HealthCheckRequest(providerName));
        
        return results.get(providerName);
    }
    
    /**
     * @description Process health check request with BaseAIService security
     * @param request The request object
     * @return Response object
     */
    public override Object processRequest(Object request) {
        HealthCheckRequest hcRequest = (HealthCheckRequest) request;
        
        // Validate and sanitize input using BaseAIService
        String sanitizedProvider = validateAndSanitizeInput(hcRequest.providerName, 'providerName');
        
        // Check rate limits
        if (!RateLimitService.checkRateLimit('HEALTH_CHECK', UserInfo.getUserId())) {
            throw new RateLimitException('Health check rate limit exceeded');
        }
        
        Map<String, HealthCheckResult> results = new Map<String, HealthCheckResult>();
        
        try {
            if (sanitizedProvider == 'ALL') {
                // Check all providers
                List<AI_Provider_Configuration__mdt> providers = getActiveProviders();
                
                for (AI_Provider_Configuration__mdt provider : providers) {
                    HealthCheckResult result = performHealthCheck(provider);
                    results.put(provider.Provider_Name__c, result);
                    
                    // Log the health check
                    logHealthCheck(provider.Provider_Name__c, result);
                }
            } else {
                // Check specific provider
                AI_Provider_Configuration__mdt provider = getProviderByName(sanitizedProvider);
                if (provider != null) {
                    HealthCheckResult result = performHealthCheck(provider);
                    results.put(provider.Provider_Name__c, result);
                    
                    // Log the health check
                    logHealthCheck(provider.Provider_Name__c, result);
                } else {
                    results.put(sanitizedProvider, 
                        new HealthCheckResult(sanitizedProvider, STATUS_UNKNOWN, 'Provider not found', 0));
                }
            }
            
        } catch (Exception e) {
            // Log security event
            SecurityAuditService.logSecurityException('HealthCheck', e);
            throw new AIProviderHealthCheckException('Health check failed: ' + e.getMessage());
        }
        
        return results;
    }
    
    /**
     * @description Get all active providers with security checks
     */
    private List<AI_Provider_Configuration__mdt> getActiveProviders() {
        // Check FLS
        if (!RouteLogicSecurityUtils.hasReadAccess('AI_Provider_Configuration__mdt')) {
            throw new InsufficientPrivilegesException('Insufficient access to provider configuration');
        }
        
        return [
            SELECT DeveloperName, Provider_Name__c, Endpoint_URL__c, API_Key__c,
                   Health_Check_Endpoint__c, Timeout_Ms__c, Is_Active__c
            FROM AI_Provider_Configuration__mdt
            WHERE Is_Active__c = true
            WITH SECURITY_ENFORCED
        ];
    }
    
    /**
     * @description Get provider by name with security checks
     */
    private AI_Provider_Configuration__mdt getProviderByName(String providerName) {
        // Check FLS
        if (!RouteLogicSecurityUtils.hasReadAccess('AI_Provider_Configuration__mdt')) {
            throw new InsufficientPrivilegesException('Insufficient access to provider configuration');
        }
        
        List<AI_Provider_Configuration__mdt> providers = [
            SELECT DeveloperName, Provider_Name__c, Endpoint_URL__c, API_Key__c,
                   Health_Check_Endpoint__c, Timeout_Ms__c, Is_Active__c
            FROM AI_Provider_Configuration__mdt
            WHERE Provider_Name__c = :providerName
            AND Is_Active__c = true
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        
        return providers.isEmpty() ? null : providers[0];
    }
    
    /**
     * @description Perform actual health check with enhanced security
     */
    private HealthCheckResult performHealthCheck(AI_Provider_Configuration__mdt provider) {
        HealthCheckResult result = new HealthCheckResult(provider.Provider_Name__c);
        Long startTime = System.currentTimeMillis();
        
        try {
            // Validate endpoint URL
            String healthEndpoint = String.isNotBlank(provider.Health_Check_Endpoint__c) 
                ? provider.Health_Check_Endpoint__c 
                : provider.Endpoint_URL__c + '/health';
            
            // Validate URL format
            if (!isValidUrl(healthEndpoint)) {
                throw new InvalidParameterValueException('Invalid health check endpoint URL');
            }
            
            // Build secure HTTP request
            HttpRequest req = buildSecureRequest(healthEndpoint, provider);
            
            // Perform callout
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            Long responseTime = System.currentTimeMillis() - startTime;
            result.responseTimeMs = responseTime;
            
            // Process response
            if (res.getStatusCode() == 200) {
                result.status = STATUS_HEALTHY;
                result.message = 'Provider is healthy';
                
                // Parse response for additional details
                if (String.isNotBlank(res.getBody())) {
                    try {
                        Map<String, Object> responseData = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                        if (responseData.containsKey('status')) {
                            result.additionalInfo = responseData;
                        }
                    } catch (Exception je) {
                        // Response is not JSON, that's ok
                    }
                }
            } else if (res.getStatusCode() >= 500) {
                result.status = STATUS_UNHEALTHY;
                result.message = 'Provider returned error: ' + res.getStatusCode();
            } else if (res.getStatusCode() >= 400) {
                result.status = STATUS_DEGRADED;
                result.message = 'Provider returned client error: ' + res.getStatusCode();
            } else {
                result.status = STATUS_DEGRADED;
                result.message = 'Unexpected response: ' + res.getStatusCode();
            }
            
        } catch (Exception e) {
            result.status = STATUS_UNHEALTHY;
            result.message = 'Health check failed: ' + e.getMessage();
            result.responseTimeMs = System.currentTimeMillis() - startTime;
        }
        
        return result;
    }
    
    /**
     * @description Build secure HTTP request with proper headers
     */
    private HttpRequest buildSecureRequest(String endpoint, AI_Provider_Configuration__mdt provider) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(provider.Timeout_Ms__c != null ? provider.Timeout_Ms__c.intValue() : 30000);
        
        // Add authentication if required (retrieve from secure storage)
        if (String.isNotBlank(provider.API_Key__c)) {
            // Use SecureKeyVault to retrieve the actual API key
            String masterSecret = SecureKeyVault.getMasterSecret();
            Blob apiKey = SecureKeyVault.retrieveKey('API_KEY_' + provider.DeveloperName, masterSecret);
            
            if (apiKey != null) {
                req.setHeader('Authorization', 'Bearer ' + apiKey.toString());
            }
        }
        
        // Add security headers
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-Request-ID', generateRequestId());
        req.setHeader('User-Agent', 'RouteLogic-HealthCheck/4.0.0');
        
        return req;
    }
    
    /**
     * @description Log health check event for audit
     */
    private void logHealthCheck(String providerName, HealthCheckResult result) {
        Map<String, Object> details = new Map<String, Object>{
            'provider' => providerName,
            'status' => result.status,
            'responseTime' => result.responseTimeMs,
            'message' => result.message
        };
        
        SecurityAuditService.logHealthCheck(providerName, result.status, result.responseTimeMs);
    }
    
    /**
     * @description Get feature flag configuration
     */
    private static AI_Feature_Flag__mdt getFeatureFlag(String flagName) {
        try {
            return [
                SELECT DeveloperName, Is_Enabled__c, Rollout_Percentage__c
                FROM AI_Feature_Flag__mdt
                WHERE DeveloperName = :flagName
                LIMIT 1
            ];
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * @description Generate unique request ID for tracking
     */
    private String generateRequestId() {
        return UserInfo.getUserId() + '_' + System.currentTimeMillis() + '_' + Crypto.getRandomInteger();
    }
    
    /**
     * @description Request wrapper class
     */
    public class HealthCheckRequest {
        public String providerName { get; set; }
        
        public HealthCheckRequest(String providerName) {
            this.providerName = providerName;
        }
    }
    
    /**
     * @description Health check result class
     */
    public class HealthCheckResult {
        public String providerName { get; set; }
        public String status { get; set; }
        public String message { get; set; }
        public Long responseTimeMs { get; set; }
        public Map<String, Object> additionalInfo { get; set; }
        public DateTime checkedAt { get; set; }
        
        public HealthCheckResult(String providerName) {
            this.providerName = providerName;
            this.status = STATUS_UNKNOWN;
            this.message = '';
            this.responseTimeMs = 0;
            this.checkedAt = DateTime.now();
            this.additionalInfo = new Map<String, Object>();
        }
        
        public HealthCheckResult(String providerName, String status, String message, Long responseTime) {
            this.providerName = providerName;
            this.status = status;
            this.message = message;
            this.responseTimeMs = responseTime;
            this.checkedAt = DateTime.now();
            this.additionalInfo = new Map<String, Object>();
        }
    }
    
    /**
     * @description Custom exception for health check failures
     */
    public class AIProviderHealthCheckException extends Exception {}
    
    /**
     * @description Custom exception for rate limiting
     */
    public class RateLimitException extends Exception {}
}