/**
 * @description Service for managing AI system alerts and notifications
 * @author RouteLogic Enhanced
 * @version 3.1.2
 */
public with sharing class AIAlertingService {
    
    // Alert severity constants
    public static final String SEVERITY_CRITICAL = 'Critical';
    public static final String SEVERITY_ERROR = 'Error';
    public static final String SEVERITY_WARNING = 'Warning';
    public static final String SEVERITY_INFO = 'Info';
    
    // Alert type constants
    public static final String TYPE_PROVIDER_HEALTH = 'Provider Health';
    public static final String TYPE_PERFORMANCE = 'Performance';
    public static final String TYPE_CONFIGURATION = 'Configuration';
    public static final String TYPE_SYSTEM_ERROR = 'System Error';
    public static final String TYPE_CAPACITY = 'Capacity';
    
    /**
     * @description Create a new alert
     * @param alertType Type of alert
     * @param severity Severity level
     * @param message Alert message
     * @param providerName Optional provider name
     * @return Created alert record
     */
    public static AI_System_Alert__c createAlert(String alertType, String severity, String message, String providerName) {
        // Defensive null checks and validation
        if (String.isBlank(alertType)) {
            throw new RouteLogicValidationException('Alert type is required');
        }
        if (String.isBlank(severity)) {
            throw new RouteLogicValidationException('Severity is required');
        }
        if (String.isBlank(message)) {
            throw new RouteLogicValidationException('Message is required');
        }
        
        // Validate severity value
        Set<String> validSeverities = new Set<String>{SEVERITY_LOW, SEVERITY_MEDIUM, SEVERITY_HIGH, SEVERITY_CRITICAL};
        if (!validSeverities.contains(severity)) {
            throw new RouteLogicValidationException('Invalid severity level: ' + severity);
        }
        
        // Sanitize inputs
        message = RouteLogicInputValidator.sanitizeInput(message);
        if (providerName != null) {
            providerName = RouteLogicInputValidator.sanitizeInput(providerName);
        }
        
        AI_System_Alert__c alert = new AI_System_Alert__c(
            Alert_Type__c = alertType,
            Severity__c = severity,
            Message__c = message,
            Provider_Name__c = providerName,
            Status__c = 'New',
            Alert_Time__c = DateTime.now()
        );
        
        try {
            insert SecurityUtils.stripInaccessibleRecords(
                new List<AI_System_Alert__c>{ alert }, 
                SecurityUtils.OperationType.CREATE_RECORD
            );
            
            // Send notifications for critical alerts
            if (severity == SEVERITY_CRITICAL) {
                sendCriticalAlertNotification(alert);
            }
            
            // Check if we need to trigger escalation
            checkAlertEscalation(alert);
            
        } catch (Exception e) {
            throw new AIAlertingException('Failed to create alert: ' + e.getMessage());
        }
        
        return alert;
    }
    
    /**
     * @description Check system thresholds and create alerts if needed
     */
    public static void checkSystemThresholds() {
        try {
            // Get current system diagnostics
            AISystemMonitoringService.SystemDiagnostics diagnostics = 
                AISystemMonitoringService.getSystemDiagnostics();
            
            // Check queue thresholds
            checkQueueThresholds(diagnostics.queueMetrics);
            
            // Check performance thresholds
            checkPerformanceThresholds(diagnostics.performanceMetrics);
            
            // Check system limits
            checkSystemLimits(diagnostics.systemLimits);
            
            // Check provider health
            checkProviderHealth(diagnostics.providerHealth);
            
        } catch (Exception e) {
            createAlert(TYPE_SYSTEM_ERROR, SEVERITY_ERROR, 
                'Failed to check system thresholds: ' + e.getMessage(), null);
        }
    }
    
    /**
     * @description Check queue metrics against thresholds
     * @param metrics Queue metrics to check
     */
    private static void checkQueueThresholds(AISystemMonitoringService.QueueMetrics metrics) {
        // Check for high pending count
        if (metrics.pendingCount > 100) {
            createAlert(TYPE_CAPACITY, SEVERITY_WARNING, 
                'High number of pending requests: ' + metrics.pendingCount, null);
        }
        
        // Check for critical pending count
        if (metrics.pendingCount > 500) {
            createAlert(TYPE_CAPACITY, SEVERITY_CRITICAL, 
                'Critical queue backlog: ' + metrics.pendingCount + ' pending requests', null);
        }
        
        // Check for stale pending items
        if (metrics.oldestPendingAge > 7200000) { // 2 hours
            createAlert(TYPE_PERFORMANCE, SEVERITY_WARNING, 
                'Requests pending for over 2 hours', null);
        }
        
        // Check failure rate
        Integer totalProcessed = metrics.completedCount + metrics.failedCount;
        if (totalProcessed > 0) {
            Decimal failureRate = (Decimal.valueOf(metrics.failedCount) / Decimal.valueOf(totalProcessed)) * 100;
            if (failureRate > 10) {
                createAlert(TYPE_PERFORMANCE, SEVERITY_ERROR, 
                    'High failure rate: ' + failureRate.setScale(1) + '%', null);
            }
        }
    }
    
    /**
     * @description Check performance metrics against thresholds
     * @param metrics Performance metrics to check
     */
    private static void checkPerformanceThresholds(AISystemMonitoringService.PerformanceMetrics metrics) {
        // Check success rate
        if (metrics.successRate < 90) {
            String severity = metrics.successRate < 75 ? SEVERITY_CRITICAL : SEVERITY_WARNING;
            createAlert(TYPE_PERFORMANCE, severity, 
                'Low success rate: ' + metrics.successRate.setScale(1) + '%', null);
        }
        
        // Check throughput
        if (metrics.throughputPerHour < 10 && metrics.throughputPerHour > 0) {
            createAlert(TYPE_PERFORMANCE, SEVERITY_WARNING, 
                'Low throughput: ' + metrics.throughputPerHour.setScale(0) + ' records/hour', null);
        }
    }
    
    /**
     * @description Check system limits
     * @param limits System limits to check
     */
    private static void checkSystemLimits(AISystemMonitoringService.SystemLimits limits) {
        // Check API usage
        if (limits.apiCallsPercentage > 90) {
            createAlert(TYPE_CAPACITY, SEVERITY_CRITICAL, 
                'API calls near limit: ' + limits.apiCallsPercentage.setScale(1) + '% used', null);
        } else if (limits.apiCallsPercentage > 80) {
            createAlert(TYPE_CAPACITY, SEVERITY_WARNING, 
                'High API usage: ' + limits.apiCallsPercentage.setScale(1) + '% used', null);
        }
        
        // Check storage
        if (limits.storagePercentage > 90) {
            createAlert(TYPE_CAPACITY, SEVERITY_ERROR, 
                'Storage near limit: ' + limits.storagePercentage.setScale(1) + '% used', null);
        }
        
        // Check platform events
        if (limits.platformEventsPercentage > 80) {
            createAlert(TYPE_CAPACITY, SEVERITY_WARNING, 
                'High platform event usage: ' + limits.platformEventsPercentage.setScale(1) + '% used', null);
        }
    }
    
    /**
     * @description Check provider health
     * @param providerHealth Map of provider health summaries
     */
    private static void checkProviderHealth(Map<String, AISystemMonitoringService.ProviderHealthSummary> providerHealth) {
        for (AISystemMonitoringService.ProviderHealthSummary provider : providerHealth.values()) {
            // Skip if recently checked
            if (provider.lastCheckTime != null && provider.lastCheckTime > DateTime.now().addMinutes(-5)) {
                continue;
            }
            
            // Check provider status
            if (provider.status == 'Unhealthy') {
                createAlert(TYPE_PROVIDER_HEALTH, SEVERITY_CRITICAL, 
                    'Provider unhealthy: ' + provider.message, provider.providerName);
            } else if (provider.status == 'Degraded') {
                createAlert(TYPE_PROVIDER_HEALTH, SEVERITY_WARNING, 
                    'Provider degraded: ' + provider.message, provider.providerName);
            }
            
            // Check uptime
            if (provider.uptimePercentage < 95) {
                createAlert(TYPE_PROVIDER_HEALTH, SEVERITY_WARNING, 
                    'Low provider uptime: ' + provider.uptimePercentage.setScale(1) + '%', provider.providerName);
            }
        }
    }
    
    /**
     * @description Send critical alert notification
     * @param alert The alert to notify about
     */
    private static void sendCriticalAlertNotification(AI_System_Alert__c alert) {
        try {
            // Get notification recipients
            Set<Id> recipientIds = getNotificationRecipients();
            
            if (recipientIds.isEmpty()) {
                return;
            }
            
            // Create custom notification
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle('Critical AI System Alert');
            notification.setBody(alert.Alert_Type__c + ': ' + alert.Message__c);
            notification.setTargetId(alert.Id);
            
            // Get custom notification type
            List<CustomNotificationType> notificationTypes = new List<CustomNotificationType>();
            if (RouteLogicSecurityUtils.hasReadAccess('CustomNotificationType')) {
                notificationTypes = [
                    SELECT Id 
                    FROM CustomNotificationType 
                    WHERE DeveloperName = 'AI_System_Alert'
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
            }
            
            if (!notificationTypes.isEmpty()) {
                notification.setNotificationTypeId(notificationTypes[0].Id);
                notification.setSenderId(UserInfo.getUserId());
                notification.send(recipientIds);
            }
            
        } catch (Exception e) {
        }
    }
    
    /**
     * @description Get users who should receive notifications
     * @return Set of user IDs
     */
    private static Set<Id> getNotificationRecipients() {
        Set<Id> userIds = new Set<Id>();
        
        try {
            // Get users with AI Configuration Manager permission
            List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
            if (RouteLogicSecurityUtils.hasReadAccess('PermissionSetAssignment')) {
                assignments = [
                    SELECT AssigneeId
                    FROM PermissionSetAssignment
                    WHERE PermissionSet.Name = 'AI_Configuration_Manager'
                    AND Assignee.IsActive = true
                    WITH SECURITY_ENFORCED
                ];
            }
            
            for (PermissionSetAssignment psa : assignments) {
                userIds.add(psa.AssigneeId);
            }
            
            // Also include system administrators
            List<User> admins = new List<User>();
            if (RouteLogicSecurityUtils.hasReadAccess('User')) {
                admins = [
                    SELECT Id
                    FROM User
                    WHERE Profile.Name = 'System Administrator'
                    AND IsActive = true
                    WITH SECURITY_ENFORCED
                    LIMIT 10
                ];
            }
            
            for (User admin : admins) {
                userIds.add(admin.Id);
            }
            
        } catch (Exception e) {
        }
        
        return userIds;
    }
    
    /**
     * @description Check if alert needs escalation
     * @param alert The alert to check
     */
    private static void checkAlertEscalation(AI_System_Alert__c alert) {
        if (alert.Severity__c != SEVERITY_CRITICAL) {
            return;
        }
        
        try {
            // Check for similar unresolved alerts
            Integer similarAlerts = 0;
            if (RouteLogicSecurityUtils.hasReadAccess('AI_System_Alert__c')) {
                similarAlerts = [
                    SELECT COUNT()
                    FROM AI_System_Alert__c
                    WHERE Alert_Type__c = :alert.Alert_Type__c
                    AND Provider_Name__c = :alert.Provider_Name__c
                    AND Status__c NOT IN ('Resolved', 'Ignored')
                    AND CreatedDate = LAST_N_DAYS:1
                    WITH SECURITY_ENFORCED
                ];
            }
            
            // Escalate if multiple similar critical alerts
            if (similarAlerts > 3) {
                escalateAlert(alert, 'Multiple similar critical alerts in 24 hours');
            }
            
        } catch (Exception e) {
        }
    }
    
    /**
     * @description Escalate an alert
     * @param alert The alert to escalate
     * @param reason Reason for escalation
     */
    private static void escalateAlert(AI_System_Alert__c alert, String reason) {
        // Create case for critical escalation
        Case escalationCase = new Case(
            Subject = 'Critical AI System Alert: ' + alert.Alert_Type__c,
            Description = 'Alert: ' + alert.Message__c + '\n\nEscalation Reason: ' + reason,
            Priority = 'High',
            Origin = 'AI System',
            Type = 'Problem'
        );
        
        try {
            insert SecurityUtils.stripInaccessibleRecords(
                new List<Case>{ escalationCase }, 
                SecurityUtils.OperationType.CREATE_RECORD
            );
            
            // Update alert with case reference
            alert.Resolution_Notes__c = 'Escalated to Case #' + escalationCase.CaseNumber;
            update SecurityUtils.stripInaccessibleRecords(
                new List<AI_System_Alert__c>{ alert }, 
                SecurityUtils.OperationType.UPDATE_RECORD
            );
            
        } catch (Exception e) {
        }
    }
    
    /**
     * @description Update alert status
     * @param alertId ID of the alert
     * @param newStatus New status value
     * @param notes Optional resolution notes
     */
    @AuraEnabled
    public static void updateAlertStatus(Id alertId, String newStatus, String notes) {
        try {
            AI_System_Alert__c alert = [
                SELECT Id, Status__c, Resolution_Notes__c
                FROM AI_System_Alert__c
                WHERE Id = :alertId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            
            alert.Status__c = newStatus;
            
            if (String.isNotBlank(notes)) {
                alert.Resolution_Notes__c = notes;
            }
            
            if (newStatus == 'Resolved') {
                alert.Resolved_Time__c = DateTime.now();
                alert.Resolved_By__c = UserInfo.getUserId();
            }
            
            update SecurityUtils.stripInaccessibleRecords(
                new List<AI_System_Alert__c>{ alert }, 
                SecurityUtils.OperationType.UPDATE_RECORD
            );
            
        } catch (Exception e) {
            throw new AuraHandledException('Failed to update alert: ' + e.getMessage());
        }
    }
    
    /**
     * @description Get active alerts
     * @param limitCount Number of alerts to return
     * @return List of active alerts
     */
    @AuraEnabled(cacheable=true)
    public static List<AI_System_Alert__c> getActiveAlerts(Integer limitCount) {
        try {
            return [
                SELECT Id, Name, Alert_Type__c, Severity__c, Status__c, 
                       Provider_Name__c, Message__c, Alert_Time__c, CreatedDate
                FROM AI_System_Alert__c
                WHERE Status__c NOT IN ('Resolved', 'Ignored')
                WITH SECURITY_ENFORCED
                ORDER BY Alert_Time__c DESC
                LIMIT :limitCount
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Failed to retrieve alerts: ' + e.getMessage());
        }
    }
    
    public class AIAlertingException extends Exception {}
}