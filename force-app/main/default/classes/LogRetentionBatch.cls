/**
 * @description Batch class for deleting old log records with enhanced security
 * @author RouteLogic Team
 * @date 2025-01-20
 * @security Fixed SQL injection vulnerability - February 5, 2025
 */
public with sharing class LogRetentionBatch implements Database.Batchable<sObject>, Database.Stateful {
    
    private String objectName;
    private DateTime cutoffDate;
    private Integer totalDeleted = 0;
    private List<String> errors = new List<String>();
    
    // Security: Whitelist of allowed objects and their date fields
    private static final Map<String, String> ALLOWED_OBJECTS_AND_FIELDS = new Map<String, String>{
        'Error_Log__c' => 'Timestamp__c',
        'AI_Audit_Event__c' => 'Timestamp__c',
        'AI_Processing_Status__c' => 'CreatedDate',
        'AI_Bulk_Processing_Metrics__c' => 'CreatedDate'
    };
    
    /**
     * @description Constructor
     * @param objectName The object to clean up
     * @param cutoffDate Records older than this date will be deleted
     */
    public LogRetentionBatch(String objectName, DateTime cutoffDate) {
        this.objectName = objectName;
        this.cutoffDate = cutoffDate;
    }
    
    /**
     * @description Start method with SQL injection prevention
     * @param bc Batch context
     * @return Query locator
     * @throws SecurityException if object name is not whitelisted
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Security: Validate object name against whitelist
        if (!ALLOWED_OBJECTS_AND_FIELDS.containsKey(objectName)) {
            throw new SecurityException('Invalid object for log retention: ' + objectName + 
                '. Allowed objects: ' + String.join(new List<String>(ALLOWED_OBJECTS_AND_FIELDS.keySet()), ', '));
        }
        
        // Get the pre-validated date field
        String dateField = ALLOWED_OBJECTS_AND_FIELDS.get(objectName);
        
        // Security: Additional validation using Schema
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
        if (objType == null) {
            throw new SecurityException('Object does not exist in schema: ' + objectName);
        }
        
        // Verify the date field exists on the object
        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
        if (!fieldMap.containsKey(dateField.toLowerCase())) {
            throw new SecurityException('Date field does not exist on object: ' + dateField);
        }
        
        // Build query with validated components
        String query = 'SELECT Id FROM ' + objectName + ' WHERE ' + dateField + ' < :cutoffDate';
        
        // Add object-specific filters
        if (objectName == 'AI_Audit_Event__c') {
            // Never delete compliance category logs
            query += ' AND Category__c != \'COMPLIANCE\'';
        }
        
        query += ' WITH SECURITY_ENFORCED';
        
        // Log the query for audit purposes (without exposing cutoff date value)
        AuditService.logOperationalEvent(
            'LOG_RETENTION_START',
            'Starting retention batch for ' + objectName + ' using field ' + dateField,
            'Info'
        );
        
        return Database.getQueryLocator(query);
    }
    
    /**
     * @description Execute method
     * @param bc Batch context
     * @param scope Records to process
     */
    public void execute(Database.BatchableContext bc, List<sObject> scope) {
        try {
            // Apply FLS check
            List<sObject> recordsToDelete = SecurityUtils.stripInaccessibleRecords(
                AccessType.DELETABLE,
                scope
            );
            
            if (!recordsToDelete.isEmpty()) {
                // Use Database.delete for partial success
                Database.DeleteResult[] results = Database.delete(recordsToDelete, false);
                
                // Track results
                for (Database.DeleteResult result : results) {
                    if (result.isSuccess()) {
                        totalDeleted++;
                    } else {
                        for (Database.Error err : result.getErrors()) {
                            errors.add('Delete failed: ' + err.getMessage());
                        }
                    }
                }
            }
        } catch (Exception e) {
            errors.add('Batch execution error: ' + e.getMessage());
        }
    }
    
    /**
     * @description Finish method
     * @param bc Batch context
     */
    public void finish(Database.BatchableContext bc) {
        // Log completion
        String message = 'Log retention batch completed for ' + objectName + '. ' +
                        'Total deleted: ' + totalDeleted;
        
        if (!errors.isEmpty()) {
            message += '. Errors: ' + errors.size();
            
            // Log errors
            ErrorLogService.logError(
                'LogRetentionBatch',
                'Batch Errors',
                String.join(errors, '; ')
            );
        }
        
        // Audit the operation
        AuditService.logOperationalEvent(
            'LOG_RETENTION_BATCH',
            message,
            errors.isEmpty() ? 'Success' : 'Partial Success'
        );
        
        // Send notification if configured
        sendCompletionNotification();
    }
    
    /**
     * @description Send completion notification
     */
    private void sendCompletionNotification() {
        // Check if notifications are enabled
        if (!ConfigManager.isRetentionNotificationEnabled()) {
            return;
        }
        
        // Create custom notification
        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        
        // Set notification type (must be created in Setup)
        List<CustomNotificationType> notificationTypes = [
            SELECT Id 
            FROM CustomNotificationType 
            WHERE DeveloperName = 'Log_Retention_Notification'
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        
        if (!notificationTypes.isEmpty()) {
            notification.setNotificationTypeId(notificationTypes[0].Id);
            notification.setTitle('Log Retention Cleanup Complete');
            notification.setBody('Deleted ' + totalDeleted + ' ' + objectName + ' records. ' +
                               (errors.isEmpty() ? 'No errors.' : errors.size() + ' errors occurred.'));
            
            // Send to system admins with limit to prevent governor issues
            Set<String> recipients = new Set<String>();
            
            // Check access to User object
            if (RouteLogicSecurityUtils.hasReadAccess('User')) {
                for (User admin : [
                    SELECT Id 
                    FROM User 
                    WHERE Profile.Name = 'System Administrator' 
                    AND IsActive = true 
                    WITH SECURITY_ENFORCED
                    LIMIT 100
                ]) {
                    recipients.add(admin.Id);
                }
            }
            
            if (!recipients.isEmpty()) {
                notification.setTargetIds(recipients);
                notification.send();
            }
        }
    }
}