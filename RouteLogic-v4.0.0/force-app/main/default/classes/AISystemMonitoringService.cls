/**
 * @description Service class for monitoring AI system health and performance metrics
 * @author RouteLogic Enhanced
 * @version 3.1.2
 */
public with sharing class AISystemMonitoringService {
    
    /**
     * @description Get comprehensive system diagnostics
     * @return SystemDiagnostics object with all health metrics
     */
    @AuraEnabled(cacheable=true)
    public static SystemDiagnostics getSystemDiagnostics() {
        SystemDiagnostics diagnostics = new SystemDiagnostics();
        
        try {
            // Check user permissions
            if (!FeatureManagement.checkPermission('AI_Configuration_Manager')) {
                throw new InsufficientPrivilegesException('User does not have AI Configuration Manager permission');
            }
            
            // Get processing queue metrics
            diagnostics.queueMetrics = getQueueMetrics();
            
            // Get provider health status
            diagnostics.providerHealth = getProviderHealthSummary();
            
            // Get system performance metrics
            diagnostics.performanceMetrics = getPerformanceMetrics();
            
            // Get configuration validation status
            diagnostics.configurationStatus = getConfigurationStatus();
            
            // Get recent errors
            diagnostics.recentErrors = getRecentErrors();
            
            // Get system limits
            diagnostics.systemLimits = getSystemLimits();
            
            // Calculate overall system health
            diagnostics.overallHealth = calculateOverallHealth(diagnostics);
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting system diagnostics: ' + e.getMessage());
            diagnostics.errorMessage = 'Failed to retrieve diagnostics: ' + e.getMessage();
        }
        
        return diagnostics;
    }
    
    /**
     * @description Get queue metrics for AI processing
     * @return Queue metrics including pending, processing, and failed counts
     */
    private static QueueMetrics getQueueMetrics() {
        QueueMetrics metrics = new QueueMetrics();
        
        try {
            // Get counts by status
            AggregateResult[] results = [
                SELECT Status__c, Priority__c, COUNT(Id) recordCount
                FROM AI_Processing_Status__c
                WHERE CreatedDate = LAST_N_DAYS:7
                WITH SECURITY_ENFORCED
                GROUP BY Status__c, Priority__c
            ];
            
            // Process results
            for (AggregateResult ar : results) {
                String status = (String) ar.get('Status__c');
                String priority = (String) ar.get('Priority__c');
                Integer count = (Integer) ar.get('recordCount');
                
                if (status == 'Pending') {
                    metrics.pendingCount += count;
                    if (priority == 'High') metrics.highPriorityPending += count;
                } else if (status == 'Processing') {
                    metrics.processingCount += count;
                } else if (status == 'Failed') {
                    metrics.failedCount += count;
                } else if (status == 'Completed') {
                    metrics.completedCount += count;
                }
            }
            
            // Get average processing time
            AggregateResult[] timeResults = [
                SELECT AVG(Processing_Duration_Ms__c) avgTime
                FROM AI_Processing_Status__c
                WHERE Status__c = 'Completed'
                AND CreatedDate = LAST_N_DAYS:1
                WITH SECURITY_ENFORCED
            ];
            
            if (!timeResults.isEmpty() && timeResults[0].get('avgTime') != null) {
                metrics.averageProcessingTime = ((Decimal) timeResults[0].get('avgTime')).longValue();
            }
            
            // Get oldest pending item
            List<AI_Processing_Status__c> oldestPending = [
                SELECT CreatedDate
                FROM AI_Processing_Status__c
                WHERE Status__c = 'Pending'
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];
            
            if (!oldestPending.isEmpty()) {
                metrics.oldestPendingAge = DateTime.now().getTime() - oldestPending[0].CreatedDate.getTime();
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting queue metrics: ' + e.getMessage());
        }
        
        return metrics;
    }
    
    /**
     * @description Get provider health summary
     * @return Map of provider names to their current health status
     */
    private static Map<String, ProviderHealthSummary> getProviderHealthSummary() {
        Map<String, ProviderHealthSummary> healthMap = new Map<String, ProviderHealthSummary>();
        
        try {
            // Get latest health check for each provider
            AggregateResult[] results = [
                SELECT Provider_Name__c, MAX(Check_Time__c) latestCheck
                FROM AI_Provider_Health_Check__c
                WHERE Check_Time__c = LAST_N_HOURS:24
                WITH SECURITY_ENFORCED
                GROUP BY Provider_Name__c
            ];
            
            Set<String> providerNames = new Set<String>();
            Map<String, DateTime> latestCheckTimes = new Map<String, DateTime>();
            
            for (AggregateResult ar : results) {
                String providerName = (String) ar.get('Provider_Name__c');
                DateTime checkTime = (DateTime) ar.get('latestCheck');
                providerNames.add(providerName);
                latestCheckTimes.put(providerName, checkTime);
            }
            
            // Get the actual health records
            if (!providerNames.isEmpty()) {
                List<AI_Provider_Health_Check__c> healthChecks = [
                    SELECT Provider_Name__c, Status__c, Response_Time_Ms__c, Check_Time__c, Message__c
                    FROM AI_Provider_Health_Check__c
                    WHERE Provider_Name__c IN :providerNames
                    AND Check_Time__c = LAST_N_HOURS:24
                    WITH SECURITY_ENFORCED
                    ORDER BY Check_Time__c DESC
                ];
                
                // Build health summaries
                for (AI_Provider_Health_Check__c check : healthChecks) {
                    if (check.Check_Time__c == latestCheckTimes.get(check.Provider_Name__c)) {
                        ProviderHealthSummary summary = new ProviderHealthSummary();
                        summary.providerName = check.Provider_Name__c;
                        summary.status = check.Status__c;
                        summary.lastCheckTime = check.Check_Time__c;
                        summary.responseTime = check.Response_Time_Ms__c;
                        summary.message = check.Message__c;
                        
                        // Calculate uptime
                        summary.uptimePercentage = AIProviderHealthCheckService.calculateUptime(check.Provider_Name__c, 24);
                        
                        healthMap.put(check.Provider_Name__c, summary);
                    }
                }
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting provider health: ' + e.getMessage());
        }
        
        return healthMap;
    }
    
    /**
     * @description Get system performance metrics
     * @return Performance metrics for the AI system
     */
    private static PerformanceMetrics getPerformanceMetrics() {
        PerformanceMetrics metrics = new PerformanceMetrics();
        
        try {
            DateTime last24Hours = DateTime.now().addHours(-24);
            
            // Get success rate
            AggregateResult[] successResults = [
                SELECT Status__c, COUNT(Id) recordCount
                FROM AI_Processing_Status__c
                WHERE LastModifiedDate >= :last24Hours
                AND Status__c IN ('Completed', 'Failed')
                WITH SECURITY_ENFORCED
                GROUP BY Status__c
            ];
            
            Integer completed = 0;
            Integer failed = 0;
            
            for (AggregateResult ar : successResults) {
                String status = (String) ar.get('Status__c');
                Integer count = (Integer) ar.get('recordCount');
                
                if (status == 'Completed') {
                    completed = count;
                } else if (status == 'Failed') {
                    failed = count;
                }
            }
            
            if (completed + failed > 0) {
                metrics.successRate = (Decimal.valueOf(completed) / Decimal.valueOf(completed + failed)) * 100;
            }
            
            // Get throughput (records per hour)
            AggregateResult[] throughputResults = [
                SELECT HOUR_IN_DAY(LastModifiedDate) hour, COUNT(Id) recordCount
                FROM AI_Processing_Status__c
                WHERE LastModifiedDate >= :last24Hours
                AND Status__c = 'Completed'
                WITH SECURITY_ENFORCED
                GROUP BY HOUR_IN_DAY(LastModifiedDate)
            ];
            
            Integer totalRecords = 0;
            Integer hoursWithData = 0;
            
            for (AggregateResult ar : throughputResults) {
                totalRecords += (Integer) ar.get('recordCount');
                hoursWithData++;
            }
            
            if (hoursWithData > 0) {
                metrics.throughputPerHour = Decimal.valueOf(totalRecords) / Decimal.valueOf(hoursWithData);
            }
            
            // Get average response times by provider
            AggregateResult[] responseResults = [
                SELECT Provider_Name__c, AVG(Response_Time_Ms__c) avgTime
                FROM AI_Provider_Health_Check__c
                WHERE Check_Time__c >= :last24Hours
                WITH SECURITY_ENFORCED
                GROUP BY Provider_Name__c
            ];
            
            metrics.averageResponseTimeByProvider = new Map<String, Decimal>();
            
            for (AggregateResult ar : responseResults) {
                String provider = (String) ar.get('Provider_Name__c');
                Decimal avgTime = (Decimal) ar.get('avgTime');
                metrics.averageResponseTimeByProvider.put(provider, avgTime);
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting performance metrics: ' + e.getMessage());
        }
        
        return metrics;
    }
    
    /**
     * @description Get configuration validation status
     * @return Current configuration validation results
     */
    private static ConfigurationStatus getConfigurationStatus() {
        ConfigurationStatus status = new ConfigurationStatus();
        
        try {
            // Run validation service
            AIConfigurationValidationService.ValidationResult validationResult = 
                AIConfigurationValidationService.validateConfiguration();
            
            status.isValid = validationResult.isValid;
            status.errorCount = 0;
            status.warningCount = 0;
            
            // Count errors and warnings
            for (AIConfigurationValidationService.ValidationError error : validationResult.errors) {
                if (error.severity == 'Error') {
                    status.errorCount++;
                } else if (error.severity == 'Warning') {
                    status.warningCount++;
                }
            }
            
            status.lastValidated = DateTime.now();
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting configuration status: ' + e.getMessage());
            status.isValid = false;
            status.errorCount = 1;
            status.lastValidated = DateTime.now();
        }
        
        return status;
    }
    
    /**
     * @description Get recent system errors
     * @return List of recent error events
     */
    private static List<ErrorEvent> getRecentErrors() {
        List<ErrorEvent> errors = new List<ErrorEvent>();
        
        try {
            // Get recent failed processing records
            List<AI_Processing_Status__c> failedRecords = [
                SELECT Id, Case__c, Error_Message__c, LastModifiedDate, Provider__c
                FROM AI_Processing_Status__c
                WHERE Status__c = 'Failed'
                AND LastModifiedDate = LAST_N_DAYS:1
                WITH SECURITY_ENFORCED
                ORDER BY LastModifiedDate DESC
                LIMIT 10
            ];
            
            for (AI_Processing_Status__c record : failedRecords) {
                ErrorEvent error = new ErrorEvent();
                error.timestamp = record.LastModifiedDate;
                error.errorType = 'Processing Failed';
                error.message = record.Error_Message__c;
                error.context = 'Case: ' + record.Case__c + ', Provider: ' + record.Provider__c;
                errors.add(error);
            }
            
            // Get provider health check failures
            List<AI_Provider_Health_Check__c> failedHealthChecks = [
                SELECT Provider_Name__c, Message__c, Check_Time__c
                FROM AI_Provider_Health_Check__c
                WHERE Status__c IN ('Unhealthy', 'Unknown')
                AND Check_Time__c = LAST_N_DAYS:1
                WITH SECURITY_ENFORCED
                ORDER BY Check_Time__c DESC
                LIMIT 5
            ];
            
            for (AI_Provider_Health_Check__c check : failedHealthChecks) {
                ErrorEvent error = new ErrorEvent();
                error.timestamp = check.Check_Time__c;
                error.errorType = 'Health Check Failed';
                error.message = check.Message__c;
                error.context = 'Provider: ' + check.Provider_Name__c;
                errors.add(error);
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting recent errors: ' + e.getMessage());
        }
        
        return errors;
    }
    
    /**
     * @description Get current system limits usage
     * @return System limits information
     */
    private static SystemLimits getSystemLimits() {
        SystemLimits limits = new SystemLimits();
        
        try {
            // Get org limits
            Map<String, System.OrgLimit> orgLimits = OrgLimits.getMap();
            
            // API calls
            System.OrgLimit apiLimit = orgLimits.get('DailyApiRequests');
            limits.apiCallsUsed = apiLimit.getValue();
            limits.apiCallsLimit = apiLimit.getLimit();
            limits.apiCallsPercentage = (limits.apiCallsLimit > 0) ? 
                (Decimal.valueOf(limits.apiCallsUsed) / Decimal.valueOf(limits.apiCallsLimit)) * 100 : 0;
            
            // Storage
            System.OrgLimit storageLimit = orgLimits.get('DataStorageMB');
            limits.storageUsedMB = storageLimit.getValue();
            limits.storageLimitMB = storageLimit.getLimit();
            limits.storagePercentage = (limits.storageLimitMB > 0) ? 
                (Decimal.valueOf(limits.storageUsedMB) / Decimal.valueOf(limits.storageLimitMB)) * 100 : 0;
            
            // Platform Events
            System.OrgLimit eventLimit = orgLimits.get('DailyStandardVolumePlatformEvents');
            limits.platformEventsUsed = eventLimit.getValue();
            limits.platformEventsLimit = eventLimit.getLimit();
            limits.platformEventsPercentage = (limits.platformEventsLimit > 0) ? 
                (Decimal.valueOf(limits.platformEventsUsed) / Decimal.valueOf(limits.platformEventsLimit)) * 100 : 0;
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting system limits: ' + e.getMessage());
        }
        
        return limits;
    }
    
    /**
     * @description Calculate overall system health score
     * @param diagnostics Current system diagnostics
     * @return Overall health score (0-100)
     */
    private static Decimal calculateOverallHealth(SystemDiagnostics diagnostics) {
        Decimal healthScore = 100.0;
        
        // Deduct points for queue issues
        if (diagnostics.queueMetrics.failedCount > 10) {
            healthScore -= 10;
        }
        if (diagnostics.queueMetrics.oldestPendingAge > 3600000) { // 1 hour
            healthScore -= 15;
        }
        
        // Deduct points for unhealthy providers
        Integer unhealthyProviders = 0;
        for (ProviderHealthSummary provider : diagnostics.providerHealth.values()) {
            if (provider.status != 'Healthy') {
                unhealthyProviders++;
            }
        }
        if (unhealthyProviders > 0) {
            healthScore -= (unhealthyProviders * 10);
        }
        
        // Deduct points for poor performance
        if (diagnostics.performanceMetrics.successRate < 90) {
            healthScore -= 20;
        } else if (diagnostics.performanceMetrics.successRate < 95) {
            healthScore -= 10;
        }
        
        // Deduct points for configuration issues
        if (!diagnostics.configurationStatus.isValid) {
            healthScore -= 25;
        }
        
        // Deduct points for system limit usage
        if (diagnostics.systemLimits.apiCallsPercentage > 80) {
            healthScore -= 10;
        }
        if (diagnostics.systemLimits.storagePercentage > 80) {
            healthScore -= 5;
        }
        
        return Math.max(0, healthScore);
    }
    
    // Inner classes for data structures
    public class SystemDiagnostics {
        @AuraEnabled public QueueMetrics queueMetrics { get; set; }
        @AuraEnabled public Map<String, ProviderHealthSummary> providerHealth { get; set; }
        @AuraEnabled public PerformanceMetrics performanceMetrics { get; set; }
        @AuraEnabled public ConfigurationStatus configurationStatus { get; set; }
        @AuraEnabled public List<ErrorEvent> recentErrors { get; set; }
        @AuraEnabled public SystemLimits systemLimits { get; set; }
        @AuraEnabled public Decimal overallHealth { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
    }
    
    public class QueueMetrics {
        @AuraEnabled public Integer pendingCount { get; set; }
        @AuraEnabled public Integer processingCount { get; set; }
        @AuraEnabled public Integer failedCount { get; set; }
        @AuraEnabled public Integer completedCount { get; set; }
        @AuraEnabled public Integer highPriorityPending { get; set; }
        @AuraEnabled public Long averageProcessingTime { get; set; }
        @AuraEnabled public Long oldestPendingAge { get; set; }
        
        public QueueMetrics() {
            this.pendingCount = 0;
            this.processingCount = 0;
            this.failedCount = 0;
            this.completedCount = 0;
            this.highPriorityPending = 0;
            this.averageProcessingTime = 0;
            this.oldestPendingAge = 0;
        }
    }
    
    public class ProviderHealthSummary {
        @AuraEnabled public String providerName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public DateTime lastCheckTime { get; set; }
        @AuraEnabled public Decimal responseTime { get; set; }
        @AuraEnabled public Decimal uptimePercentage { get; set; }
        @AuraEnabled public String message { get; set; }
    }
    
    public class PerformanceMetrics {
        @AuraEnabled public Decimal successRate { get; set; }
        @AuraEnabled public Decimal throughputPerHour { get; set; }
        @AuraEnabled public Map<String, Decimal> averageResponseTimeByProvider { get; set; }
        
        public PerformanceMetrics() {
            this.successRate = 100.0;
            this.throughputPerHour = 0.0;
            this.averageResponseTimeByProvider = new Map<String, Decimal>();
        }
    }
    
    public class ConfigurationStatus {
        @AuraEnabled public Boolean isValid { get; set; }
        @AuraEnabled public Integer errorCount { get; set; }
        @AuraEnabled public Integer warningCount { get; set; }
        @AuraEnabled public DateTime lastValidated { get; set; }
    }
    
    public class ErrorEvent {
        @AuraEnabled public DateTime timestamp { get; set; }
        @AuraEnabled public String errorType { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String context { get; set; }
    }
    
    public class SystemLimits {
        @AuraEnabled public Integer apiCallsUsed { get; set; }
        @AuraEnabled public Integer apiCallsLimit { get; set; }
        @AuraEnabled public Decimal apiCallsPercentage { get; set; }
        @AuraEnabled public Integer storageUsedMB { get; set; }
        @AuraEnabled public Integer storageLimitMB { get; set; }
        @AuraEnabled public Decimal storagePercentage { get; set; }
        @AuraEnabled public Integer platformEventsUsed { get; set; }
        @AuraEnabled public Integer platformEventsLimit { get; set; }
        @AuraEnabled public Decimal platformEventsPercentage { get; set; }
    }
}