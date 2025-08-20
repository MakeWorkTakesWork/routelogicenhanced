/**
 * @description Schedulable class to perform regular health checks on AI providers
 * @author RouteLogic Enhanced
 * @version 3.1.2
 */
public with sharing class AIHealthCheckScheduler implements Schedulable {
    
    /**
     * @description Execute method called by the scheduler
     * @param context The schedulable context
     */
    public void execute(SchedulableContext context) {
        try {
            // Check if we should run based on configuration
            if (!shouldRunHealthCheck()) {
                // Health check skipped based on configuration
                return;
            }
            
            // Execute health check in future method to allow callouts
            performHealthCheckAsync();
            
        } catch (Exception e) {
            ErrorLogService.logError('AIHealthCheckScheduler.execute', e, 'Error in health check scheduler');
            
            // Log the error for monitoring
            logSchedulerError(e);
        }
    }
    
    /**
     * @description Check if health check should run based on configuration
     * @return Boolean indicating if health check should proceed
     */
    private Boolean shouldRunHealthCheck() {
        try {
            // Check custom metadata for health check configuration
            // Note: Custom metadata types don't require CRUD checks as they're system-level
            List<AI_Processing_Config__mdt> configs = [
                SELECT Enable_Health_Checks__c, Health_Check_Business_Hours__c
                FROM AI_Processing_Config__mdt
                WHERE DeveloperName = 'Default'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            
            if (configs.isEmpty() || !configs[0].Enable_Health_Checks__c) {
                return false;
            }
            
            // Check if we're within business hours if configured
            if (String.isNotBlank(configs[0].Health_Check_Business_Hours__c)) {
                // Validate access to BusinessHours
                if (!RouteLogicSecurityUtils.hasReadAccess('BusinessHours')) {
                    // Insufficient permissions to read BusinessHours
                    return true; // Default to running if can't check business hours
                }
                
                BusinessHours bh = [
                    SELECT Id 
                    FROM BusinessHours 
                    WHERE Name = :configs[0].Health_Check_Business_Hours__c
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
                
                if (bh != null && !BusinessHours.isWithin(bh.Id, DateTime.now())) {
                    return false;
                }
            }
            
            return true;
            
        } catch (Exception e) {
            ErrorLogService.logError('AIHealthCheckScheduler.shouldRunHealthCheck', e, 'Error checking configuration');
            return true; // Default to running if config check fails
        }
    }
    
    /**
     * @description Perform health check asynchronously to allow callouts
     */
    @future(callout=true)
    private static void performHealthCheckAsync() {
        try {
            // Perform health checks on all providers
            Map<String, AIProviderHealthCheckService.HealthCheckResult> results = 
                AIProviderHealthCheckService.checkAllProviders();
            
            // Store results for tracking and history
            AIProviderHealthCheckService.storeHealthCheckResults(results);
            
            // Check for issues and create alerts if needed
            checkForHealthIssues(results);
            
            // Update metrics
            updateHealthMetrics(results);
            
        } catch (Exception e) {
            ErrorLogService.logError('AIHealthCheckScheduler.performHealthCheck', e, 'Error performing health check');
            
            // Create alert for health check failure
            createHealthCheckFailureAlert(e);
        }
    }
    
    /**
     * @description Check health results for issues and create alerts
     * @param results Map of provider health check results
     */
    private static void checkForHealthIssues(Map<String, AIProviderHealthCheckService.HealthCheckResult> results) {
        List<AI_System_Alert__c> alerts = new List<AI_System_Alert__c>();
        
        for (String providerName : results.keySet()) {
            AIProviderHealthCheckService.HealthCheckResult result = results.get(providerName);
            
            // Create alert for unhealthy providers
            if (result.status == AIProviderHealthCheckService.STATUS_UNHEALTHY) {
                AI_System_Alert__c alert = new AI_System_Alert__c(
                    Alert_Type__c = 'Provider Health',
                    Severity__c = 'Critical',
                    Provider_Name__c = providerName,
                    Message__c = 'Provider ' + providerName + ' is unhealthy: ' + result.message,
                    Status__c = 'New',
                    Alert_Time__c = DateTime.now()
                );
                alerts.add(alert);
            }
            // Create warning for degraded providers
            else if (result.status == AIProviderHealthCheckService.STATUS_DEGRADED) {
                AI_System_Alert__c alert = new AI_System_Alert__c(
                    Alert_Type__c = 'Provider Health',
                    Severity__c = 'Warning',
                    Provider_Name__c = providerName,
                    Message__c = 'Provider ' + providerName + ' is degraded: ' + result.message,
                    Status__c = 'New',
                    Alert_Time__c = DateTime.now()
                );
                alerts.add(alert);
            }
            
            // Check for slow response times
            if (result.responseTimeMs > 5000 && result.status == AIProviderHealthCheckService.STATUS_HEALTHY) {
                AI_System_Alert__c alert = new AI_System_Alert__c(
                    Alert_Type__c = 'Performance',
                    Severity__c = 'Warning',
                    Provider_Name__c = providerName,
                    Message__c = 'Provider ' + providerName + ' is responding slowly: ' + result.responseTimeMs + 'ms',
                    Status__c = 'New',
                    Alert_Time__c = DateTime.now()
                );
                alerts.add(alert);
            }
        }
        
        // Insert alerts
        if (!alerts.isEmpty()) {
            try {
                insert SecurityUtils.stripInaccessibleRecords(
                    alerts, 
                    SecurityUtils.OperationType.CREATE_RECORD
                );
                
                // Send notifications for critical alerts
                notifyCriticalAlerts(alerts);
                
            } catch (Exception e) {
                ErrorLogService.logError('AIHealthCheckScheduler.createAlerts', e, 'Failed to create alerts');
            }
        }
    }
    
    /**
     * @description Update health metrics based on check results
     * @param results Map of provider health check results
     */
    private static void updateHealthMetrics(Map<String, AIProviderHealthCheckService.HealthCheckResult> results) {
        try {
            // Calculate overall health metrics
            Integer totalProviders = results.size();
            Integer healthyProviders = 0;
            Decimal totalResponseTime = 0;
            
            for (AIProviderHealthCheckService.HealthCheckResult result : results.values()) {
                if (result.status == AIProviderHealthCheckService.STATUS_HEALTHY) {
                    healthyProviders++;
                }
                totalResponseTime += result.responseTimeMs;
            }
            
            // Create system health metric record
            AI_System_Metric__c metric = new AI_System_Metric__c(
                Metric_Type__c = 'System Health',
                Metric_Name__c = 'Overall Health Check',
                Metric_Value__c = (totalProviders > 0) ? 
                    (Decimal.valueOf(healthyProviders) / Decimal.valueOf(totalProviders)) * 100 : 0,
                Additional_Data__c = JSON.serialize(new Map<String, Object>{
                    'totalProviders' => totalProviders,
                    'healthyProviders' => healthyProviders,
                    'averageResponseTime' => (totalProviders > 0) ? 
                        totalResponseTime / totalProviders : 0
                }),
                Recorded_At__c = DateTime.now()
            );
            
            insert SecurityUtils.stripInaccessibleRecords(
                new List<AI_System_Metric__c>{ metric }, 
                SecurityUtils.OperationType.CREATE_RECORD
            );
            
        } catch (Exception e) {
            ErrorLogService.logError('AIHealthCheckScheduler.updateMetrics', e, 'Failed to update metrics');
        }
    }
    
    /**
     * @description Send notifications for critical alerts
     * @param alerts List of alerts to notify about
     */
    private static void notifyCriticalAlerts(List<AI_System_Alert__c> alerts) {
        // Get users to notify
        Set<Id> userIds = new Set<Id>();
        
        try {
            // Validate access to PermissionSetAssignment
            if (!RouteLogicSecurityUtils.hasReadAccess('PermissionSetAssignment')) {
                // Insufficient permissions to read PermissionSetAssignment
                return;
            }
            
            // Find users with AI Configuration Manager permission
            List<PermissionSetAssignment> assignments = [
                SELECT AssigneeId
                FROM PermissionSetAssignment
                WHERE PermissionSet.Name = 'AI_Configuration_Manager'
                AND Assignee.IsActive = true
                WITH SECURITY_ENFORCED
            ];
            
            for (PermissionSetAssignment psa : assignments) {
                userIds.add(psa.AssigneeId);
            }
            
            // Create custom notifications for critical alerts
            List<Messaging.CustomNotification> notifications = new List<Messaging.CustomNotification>();
            
            for (AI_System_Alert__c alert : alerts) {
                if (alert.Severity__c == 'Critical' && !userIds.isEmpty()) {
                    Messaging.CustomNotification notification = new Messaging.CustomNotification();
                    notification.setTitle('Critical AI System Alert');
                    notification.setBody(alert.Message__c);
                    notification.setTargetId(alert.Id);
                    
                    // Get custom notification type
                    // Validate access to CustomNotificationType
                    if (!RouteLogicSecurityUtils.hasReadAccess('CustomNotificationType')) {
                        // Insufficient permissions to read CustomNotificationType
                        continue;
                    }
                    
                    CustomNotificationType notificationType = [
                        SELECT Id 
                        FROM CustomNotificationType 
                        WHERE DeveloperName = 'AI_System_Alert'
                        WITH SECURITY_ENFORCED
                        LIMIT 1
                    ];
                    
                    notification.setNotificationTypeId(notificationType.Id);
                    notification.setSenderId(UserInfo.getUserId());
                    
                    notifications.add(notification);
                }
            }
            
            // Send notifications
            if (!notifications.isEmpty() && !userIds.isEmpty()) {
                for (Messaging.CustomNotification notification : notifications) {
                    notification.send(userIds);
                }
            }
            
        } catch (Exception e) {
            ErrorLogService.logError('AIHealthCheckScheduler.sendNotifications', e, 'Failed to send notifications');
        }
    }
    
    /**
     * @description Create alert for health check failure
     * @param e The exception that caused the failure
     */
    private static void createHealthCheckFailureAlert(Exception e) {
        try {
            AI_System_Alert__c alert = new AI_System_Alert__c(
                Alert_Type__c = 'System Error',
                Severity__c = 'Critical',
                Message__c = 'Health check process failed: ' + e.getMessage(),
                Status__c = 'New',
                Alert_Time__c = DateTime.now(),
                Stack_Trace__c = e.getStackTraceString()
            );
            
            insert SecurityUtils.stripInaccessibleRecords(
                new List<AI_System_Alert__c>{ alert }, 
                SecurityUtils.OperationType.CREATE_RECORD
            );
            
        } catch (Exception ex) {
            ErrorLogService.logError('AIHealthCheckScheduler.createFailureAlert', ex, 'Failed to create failure alert');
        }
    }
    
    /**
     * @description Log scheduler errors
     * @param e The exception to log
     */
    private void logSchedulerError(Exception e) {
        try {
            AI_System_Alert__c alert = new AI_System_Alert__c(
                Alert_Type__c = 'Scheduler Error',
                Severity__c = 'Error',
                Message__c = 'Health check scheduler error: ' + e.getMessage(),
                Status__c = 'New',
                Alert_Time__c = DateTime.now(),
                Stack_Trace__c = e.getStackTraceString()
            );
            
            insert SecurityUtils.stripInaccessibleRecords(
                new List<AI_System_Alert__c>{ alert }, 
                SecurityUtils.OperationType.CREATE_RECORD
            );
            
        } catch (Exception ex) {
            ErrorLogService.logError('AIHealthCheckScheduler.logSchedulerError', ex, 'Failed to log scheduler error');
        }
    }
    
    /**
     * @description Schedule the health check job
     * @param cronExpression CRON expression for scheduling
     * @return The scheduled job ID
     */
    public static String scheduleHealthCheck(String cronExpression) {
        AIHealthCheckScheduler scheduler = new AIHealthCheckScheduler();
        return System.schedule('AI Provider Health Check', cronExpression, scheduler);
    }
    
    /**
     * @description Get default CRON expression for health checks (every 15 minutes)
     * @return CRON expression string
     */
    public static String getDefaultCronExpression() {
        return '0 0,15,30,45 * * * ?'; // Every 15 minutes
    }
}