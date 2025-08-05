/**
 * @description Minimal batch class for deleting old log records with enhanced security
 * @author RouteLogic Team
 * @date 2025-02-05
 * @security Fixed SQL injection vulnerability - AppExchange compliance
 */
public with sharing class LogRetentionBatchMinimal implements Database.Batchable<sObject>, Database.Stateful {
    
    private String objectName;
    private DateTime cutoffDate;
    private Integer totalDeleted = 0;
    private List<String> errors = new List<String>();
    
    // Security: Whitelist of allowed objects and their date fields
    private static final Map<String, String> ALLOWED_OBJECTS_AND_FIELDS = new Map<String, String>{
        'Error_Log__c' => 'CreatedDate',
        'AI_Processing_Status__c' => 'CreatedDate'
    };
    
    /**
     * @description Constructor
     * @param objectName The object to clean up
     * @param cutoffDate Records older than this date will be deleted
     */
    public LogRetentionBatchMinimal(String objectName, DateTime cutoffDate) {
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
            throw new SecurityException('Object type not found: ' + objectName);
        }
        
        // Security: Validate field exists and is accessible
        Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
        Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();
        
        if (!fieldMap.containsKey(dateField)) {
            throw new SecurityException('Date field not found: ' + dateField + ' on object: ' + objectName);
        }
        
        Schema.DescribeFieldResult fieldDescribe = fieldMap.get(dateField).getDescribe();
        if (!fieldDescribe.isAccessible()) {
            throw new SecurityException('No read access to field: ' + dateField + ' on object: ' + objectName);
        }
        
        // Security: Build query with validated components only
        String query = 'SELECT Id FROM ' + String.escapeSingleQuotes(objectName) + 
                      ' WHERE ' + String.escapeSingleQuotes(dateField) + ' < :cutoffDate' +
                      ' WITH SECURITY_ENFORCED';
        
        System.debug(LoggingLevel.INFO, 'LogRetentionBatch query: ' + query);
        
        return Database.getQueryLocator(query);
    }
    
    /**
     * @description Execute method - delete records in batches
     * @param bc Batch context
     * @param scope Records to process
     */
    public void execute(Database.BatchableContext bc, List<sObject> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }
        
        try {
            // Security: Verify delete access before attempting deletion
            Schema.SObjectType objType = scope[0].getSObjectType();
            Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
            
            if (!objDescribe.isDeletable()) {
                String error = 'No delete access to object: ' + objDescribe.getName();
                errors.add(error);
                System.debug(LoggingLevel.ERROR, error);
                return;
            }
            
            // Perform deletion with proper error handling
            Database.DeleteResult[] results = Database.delete(scope, false);
            
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    totalDeleted++;
                } else {
                    String error = 'Failed to delete record ' + scope[i].Id + ': ';
                    for (Database.Error err : results[i].getErrors()) {
                        error += err.getMessage() + '; ';
                    }
                    errors.add(error);
                    System.debug(LoggingLevel.ERROR, error);
                }
            }
            
        } catch (Exception e) {
            String error = 'Batch execution error: ' + e.getMessage();
            errors.add(error);
            System.debug(LoggingLevel.ERROR, error);
        }
    }
    
    /**
     * @description Finish method - log completion status
     * @param bc Batch context
     */
    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, 'LogRetentionBatch completed. Total deleted: ' + totalDeleted);
        
        if (!errors.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'LogRetentionBatch errors: ' + String.join(errors, '\n'));
        }
        
        // Simple completion notification
        System.debug(LoggingLevel.INFO, 'Log retention batch job completed for object: ' + objectName);
    }
}

