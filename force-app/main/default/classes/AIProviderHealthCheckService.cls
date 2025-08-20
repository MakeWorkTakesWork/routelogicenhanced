/**
 * @description Service class for performing health checks on AI providers
 * @author RouteLogic Enhanced
 * @version 3.1.2
 */
public with sharing class AIProviderHealthCheckService {
    
    public static final String STATUS_HEALTHY = 'Healthy';
    public static final String STATUS_DEGRADED = 'Degraded';
    public static final String STATUS_UNHEALTHY = 'Unhealthy';
    public static final String STATUS_UNKNOWN = 'Unknown';
    
    /**
     * @description Performs health check for all active AI providers
     * @return Map of provider names to their health check results
     */
    public static Map<String, HealthCheckResult> checkAllProviders() {
        Map<String, HealthCheckResult> results = new Map<String, HealthCheckResult>();
        
        try {
            // Get all active AI providers from configuration
            List<AI_Provider_Configuration__mdt> providers = [
                SELECT DeveloperName, Provider_Name__c, Endpoint_URL__c, API_Key__c,
                       Health_Check_Endpoint__c, Timeout_Ms__c, Is_Active__c
                FROM AI_Provider_Configuration__mdt
                WHERE Is_Active__c = true
                WITH SECURITY_ENFORCED
            ];
            
            for (AI_Provider_Configuration__mdt provider : providers) {
                HealthCheckResult result = checkProvider(provider);
                results.put(provider.Provider_Name__c, result);
            }
            
        } catch (Exception e) {
            throw new AIProviderHealthCheckException('Failed to check provider health: ' + e.getMessage());
        }
        
        return results;
    }
    
    /**
     * @description Performs health check for a specific provider
     * @param providerName The name of the provider to check
     * @return Health check result for the provider
     */
    public static HealthCheckResult checkProviderByName(String providerName) {
        try {
            AI_Provider_Configuration__mdt provider = [
                SELECT DeveloperName, Provider_Name__c, Endpoint_URL__c, API_Key__c,
                       Health_Check_Endpoint__c, Timeout_Ms__c, Is_Active__c
                FROM AI_Provider_Configuration__mdt
                WHERE Provider_Name__c = :providerName
                AND Is_Active__c = true
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            
            return checkProvider(provider);
            
        } catch (Exception e) {
            return new HealthCheckResult(providerName, STATUS_UNKNOWN, 'Provider not found or inactive', 0);
        }
    }
    
    /**
     * @description Internal method to check a specific provider
     * @param provider The provider configuration metadata
     * @return Health check result
     */
    private static HealthCheckResult checkProvider(AI_Provider_Configuration__mdt provider) {
        HealthCheckResult result = new HealthCheckResult(provider.Provider_Name__c);
        Long startTime = System.currentTimeMillis();
        
        try {
            // Build health check endpoint
            String healthEndpoint = String.isNotBlank(provider.Health_Check_Endpoint__c) 
                ? provider.Health_Check_Endpoint__c 
                : provider.Endpoint_URL__c + '/health';
            
            // Perform HTTP callout
            HttpRequest req = new HttpRequest();
            req.setEndpoint(healthEndpoint);
            req.setMethod('GET');
            req.setTimeout(provider.Timeout_Ms__c != null ? provider.Timeout_Ms__c.intValue() : 30000);
            
            // Add authentication if required
            if (String.isNotBlank(provider.API_Key__c)) {
                req.setHeader('Authorization', 'Bearer ' + provider.API_Key__c);
            }
            req.setHeader('Content-Type', 'application/json');
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            Long responseTime = System.currentTimeMillis() - startTime;
            result.responseTimeMs = responseTime;
            
            // Evaluate response
            if (res.getStatusCode() == 200) {
                result.status = STATUS_HEALTHY;
                result.message = 'Provider is responding normally';
                
                // Parse additional health info if available
                if (String.isNotBlank(res.getBody())) {
                    try {
                        Map<String, Object> healthData = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                        result.additionalInfo = healthData;
                    } catch (Exception e) {
                        // Not critical if parsing fails
                    }
                }
            } else if (res.getStatusCode() >= 500) {
                result.status = STATUS_UNHEALTHY;
                result.message = 'Provider returned error: ' + res.getStatusCode() + ' ' + res.getStatus();
            } else if (res.getStatusCode() >= 400) {
                result.status = STATUS_DEGRADED;
                result.message = 'Provider returned client error: ' + res.getStatusCode() + ' ' + res.getStatus();
            } else {
                result.status = STATUS_DEGRADED;
                result.message = 'Unexpected response code: ' + res.getStatusCode();
            }
            
            // Check response time thresholds
            if (responseTime > 5000 && result.status == STATUS_HEALTHY) {
                result.status = STATUS_DEGRADED;
                result.message = 'Provider is responding slowly (' + responseTime + 'ms)';
            }
            
        } catch (CalloutException e) {
            result.status = STATUS_UNHEALTHY;
            result.message = 'Failed to connect: ' + e.getMessage();
            result.responseTimeMs = System.currentTimeMillis() - startTime;
        } catch (Exception e) {
            result.status = STATUS_UNKNOWN;
            result.message = 'Unexpected error: ' + e.getMessage();
            result.responseTimeMs = System.currentTimeMillis() - startTime;
        }
        
        result.lastChecked = DateTime.now();
        return result;
    }
    
    /**
     * @description Stores health check results in custom object for tracking
     * @param results Map of provider health check results
     */
    public static void storeHealthCheckResults(Map<String, HealthCheckResult> results) {
        List<AI_Provider_Health_Check__c> records = new List<AI_Provider_Health_Check__c>();
        
        for (String providerName : results.keySet()) {
            HealthCheckResult result = results.get(providerName);
            
            AI_Provider_Health_Check__c record = new AI_Provider_Health_Check__c(
                Provider_Name__c = providerName,
                Status__c = result.status,
                Message__c = result.message,
                Response_Time_Ms__c = result.responseTimeMs,
                Check_Time__c = result.lastChecked,
                Additional_Info__c = result.additionalInfo != null ? JSON.serialize(result.additionalInfo) : null
            );
            
            records.add(record);
        }
        
        if (!records.isEmpty()) {
            try {
                insert SecurityUtils.stripInaccessibleRecords(
                    records, 
                    SecurityUtils.OperationType.CREATE_RECORD
                );
            } catch (Exception e) {
                throw new AIProviderHealthCheckException('Failed to store health check results: ' + e.getMessage());
            }
        }
    }
    
    /**
     * @description Get recent health check history for a provider
     * @param providerName The provider name
     * @param recordLimit Number of records to return
     * @return List of recent health checks
     */
    public static List<AI_Provider_Health_Check__c> getHealthHistory(String providerName, Integer recordLimit) {
        try {
            return [
                SELECT Id, Provider_Name__c, Status__c, Message__c, Response_Time_Ms__c,
                       Check_Time__c, Additional_Info__c, CreatedDate
                FROM AI_Provider_Health_Check__c
                WHERE Provider_Name__c = :providerName
                WITH SECURITY_ENFORCED
                ORDER BY Check_Time__c DESC
                LIMIT :recordLimit
            ];
        } catch (Exception e) {
            return new List<AI_Provider_Health_Check__c>();
        }
    }
    
    /**
     * @description Calculate provider uptime percentage over a period
     * @param providerName The provider name
     * @param hours Number of hours to calculate over
     * @return Uptime percentage (0-100)
     */
    public static Decimal calculateUptime(String providerName, Integer hours) {
        DateTime startTime = DateTime.now().addHours(-hours);
        
        try {
            List<AI_Provider_Health_Check__c> checks = [
                SELECT Status__c
                FROM AI_Provider_Health_Check__c
                WHERE Provider_Name__c = :providerName
                AND Check_Time__c >= :startTime
                WITH SECURITY_ENFORCED
            ];
            
            if (checks.isEmpty()) {
                return 100.0; // No data, assume healthy
            }
            
            Integer healthyCount = 0;
            for (AI_Provider_Health_Check__c check : checks) {
                if (check.Status__c == STATUS_HEALTHY) {
                    healthyCount++;
                }
            }
            
            return (Decimal.valueOf(healthyCount) / Decimal.valueOf(checks.size())) * 100.0;
            
        } catch (Exception e) {
            return 0.0;
        }
    }
    
    /**
     * @description Inner class for health check results
     */
    public class HealthCheckResult {
        @AuraEnabled public String providerName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Long responseTimeMs { get; set; }
        @AuraEnabled public DateTime lastChecked { get; set; }
        @AuraEnabled public Map<String, Object> additionalInfo { get; set; }
        
        public HealthCheckResult(String providerName) {
            this.providerName = providerName;
            this.status = STATUS_UNKNOWN;
            this.message = 'Not checked';
            this.responseTimeMs = 0;
            this.lastChecked = DateTime.now();
        }
        
        public HealthCheckResult(String providerName, String status, String message, Long responseTime) {
            this.providerName = providerName;
            this.status = status;
            this.message = message;
            this.responseTimeMs = responseTime;
            this.lastChecked = DateTime.now();
        }
    }
    
    public class AIProviderHealthCheckException extends Exception {}
}