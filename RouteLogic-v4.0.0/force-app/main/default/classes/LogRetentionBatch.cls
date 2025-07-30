/**
 * @description Batch class for deleting old log records
 * @author RouteLogic Team
 * @date 2025-01-20
 */
public with sharing class LogRetentionBatch implements Database.Batchable<sObject>, Database.Stateful {
    
    private String objectName;
    private DateTime cutoffDate;
    private Integer totalDeleted = 0;
    private List<String> errors = new List<String>();
    
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
     * @description Start method
     * @param bc Batch context
     * @return Query locator
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        String dateField = getDateFieldForObject(objectName);
        
        String query = 'SELECT Id FROM ' + String.escapeSingleQuotes(objectName) + 
                      ' WHERE ' + dateField + ' < :cutoffDate';
        
        // Add object-specific filters
        if (objectName == 'AI_Audit_Event__c') {
            // Never delete compliance category logs
            query += ' AND Category__c != \'COMPLIANCE\'';
        }
        
        query += ' WITH SECURITY_ENFORCED';
        
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
     * @description Get the date field to use for retention
     * @param objectName The object name
     * @return Field name
     */
    private String getDateFieldForObject(String objectName) {
        Map<String, String> dateFieldMap = new Map<String, String>{
            'Error_Log__c' => 'Timestamp__c',
            'AI_Audit_Event__c' => 'Timestamp__c',
            'AI_Processing_Status__c' => 'CreatedDate',
            'AI_Bulk_Processing_Metrics__c' => 'CreatedDate'
        };
        
        return dateFieldMap.containsKey(objectName) ? 
            dateFieldMap.get(objectName) : 'CreatedDate';
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
        CustomNotificationType notificationType = [
            SELECT Id 
            FROM CustomNotificationType 
            WHERE DeveloperName = 'Log_Retention_Notification'
            LIMIT 1
        ];
        
        if (notificationType != null) {
            notification.setNotificationTypeId(notificationType.Id);
            notification.setTitle('Log Retention Cleanup Complete');
            notification.setBody('Deleted ' + totalDeleted + ' ' + objectName + ' records. ' +
                               (errors.isEmpty() ? 'No errors.' : errors.size() + ' errors occurred.'));
            
            // Send to system admins
            Set<String> recipients = new Set<String>();
            for (User admin : [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' AND IsActive = true]) {
                recipients.add(admin.Id);
            }
            
            if (!recipients.isEmpty()) {
                notification.setTargetIds(recipients);
                notification.send();
            }
        }
    }
}