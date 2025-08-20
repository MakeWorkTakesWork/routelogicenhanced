public with sharing class AIBulkOperationService {
    private static final Integer DEFAULT_BATCH_SIZE = 200;
    private static final Integer MAX_BATCH_SIZE = 2000;
    
    // Bulk operation result
    public class BulkOperationResult {
        public Integer totalRecords { get; set; }
        public Integer successCount { get; set; }
        public Integer errorCount { get; set; }
        public List<ErrorDetail> errors { get; set; }
        public Long executionTime { get; set; }
        public String operationId { get; set; }
        
        public BulkOperationResult() {
            this.totalRecords = 0;
            this.successCount = 0;
            this.errorCount = 0;
            this.errors = new List<ErrorDetail>();
            this.executionTime = 0;
            this.operationId = generateOperationId();
        }
        
        private String generateOperationId() {
            return 'BULK_' + DateTime.now().getTime() + '_' + 
                   Math.round(Math.random() * 10000);
        }
    }
    
    // Error detail for bulk operations
    public class ErrorDetail {
        public String recordId { get; set; }
        public String errorMessage { get; set; }
        public String fieldName { get; set; }
        
        public ErrorDetail(String recordId, String errorMessage) {
            this.recordId = recordId;
            this.errorMessage = errorMessage;
        }
    }
    
    // Bulk configuration
    public class BulkConfig {
        public Integer batchSize { get; set; }
        public Boolean allOrNone { get; set; }
        public Boolean enableParallelProcessing { get; set; }
        public Boolean trackProgress { get; set; }
        public String notificationEmail { get; set; }
        
        public BulkConfig() {
            this.batchSize = DEFAULT_BATCH_SIZE;
            this.allOrNone = false;
            this.enableParallelProcessing = false;
            this.trackProgress = true;
            this.notificationEmail = null;
        }
    }
    
    // Bulk route processing
    public static BulkOperationResult processRoutesBulk(
        List<Id> routeIds,
        String providerType,
        BulkConfig config
    ) {
        BulkOperationResult result = new BulkOperationResult();
        Long startTime = DateTime.now().getTime();
        
        try {
            // Validate inputs
            if (routeIds.isEmpty()) {
                return result;
            }
            
            result.totalRecords = routeIds.size();
            
            // Process in batches
            List<List<Id>> batches = createBatches(routeIds, config.batchSize);
            
            for (List<Id> batch : batches) {
                processBatch(batch, providerType, result, config);
                
                // Check governor limits
                if (shouldDeferProcessing()) {
                    queueRemainingBatches(batches, result.operationId);
                    break;
                }
            }
            
            result.executionTime = DateTime.now().getTime() - startTime;
            
            // Send notification if configured
            if (String.isNotBlank(config.notificationEmail)) {
                sendCompletionNotification(result, config.notificationEmail);
            }
            
            return result;
            
        } catch (Exception e) {
            result.errors.add(new ErrorDetail('SYSTEM', e.getMessage()));
            result.executionTime = DateTime.now().getTime() - startTime;
            return result;
        }
    }
    
    // Bulk status update
    public static BulkOperationResult updateStatusBulk(
        Map<Id, String> statusUpdates,
        BulkConfig config
    ) {
        BulkOperationResult result = new BulkOperationResult();
        Long startTime = DateTime.now().getTime();
        
        try {
            result.totalRecords = statusUpdates.size();
            
            // Prepare records for update
            List<AI_Processing_Status__c> recordsToUpdate = 
                new List<AI_Processing_Status__c>();
            
            for (Id recordId : statusUpdates.keySet()) {
                AI_Processing_Status__c status = new AI_Processing_Status__c(
                    Id = recordId,
                    Status__c = statusUpdates.get(recordId),
                    Last_Modified__c = DateTime.now()
                );
                recordsToUpdate.add(status);
            }
            
            // Process in batches
            List<List<AI_Processing_Status__c>> batches = 
                createSObjectBatches(recordsToUpdate, config.batchSize);
            
            for (List<AI_Processing_Status__c> batch : batches) {
                Database.SaveResult[] saveResults = Database.update(
                    batch, 
                    config.allOrNone
                );
                
                processSaveResults(saveResults, batch, result);
            }
            
            result.executionTime = DateTime.now().getTime() - startTime;
            return result;
            
        } catch (Exception e) {
            result.errors.add(new ErrorDetail('SYSTEM', e.getMessage()));
            result.executionTime = DateTime.now().getTime() - startTime;
            return result;
        }
    }
    
    // Bulk data import
    public static BulkOperationResult importDataBulk(
        List<Map<String, Object>> dataRows,
        String objectType,
        Map<String, String> fieldMapping,
        BulkConfig config
    ) {
        BulkOperationResult result = new BulkOperationResult();
        Long startTime = DateTime.now().getTime();
        
        try {
            result.totalRecords = dataRows.size();
            
            // Validate object access
            Schema.SObjectType targetType = Schema.getGlobalDescribe().get(objectType);
            if (targetType == null) {
                throw new SecurityException('Invalid object type: ' + objectType);
            }
            
            // Check create access
            if (!targetType.getDescribe().isCreateable()) {
                throw new SecurityException('No create access to object: ' + objectType);
            }
            
            // Validate all target fields exist and are creatable
            Map<String, Schema.SObjectField> fieldMap = targetType.getDescribe().fields.getMap();
            for (String targetField : fieldMapping.values()) {
                if (!fieldMap.containsKey(targetField)) {
                    throw new SecurityException('Invalid field: ' + targetField);
                }
                if (!fieldMap.get(targetField).getDescribe().isCreateable()) {
                    throw new SecurityException('Field is not creatable: ' + targetField);
                }
            }
            
            // Convert data to SObjects
            List<SObject> records = new List<SObject>();
            
            for (Map<String, Object> row : dataRows) {
                SObject record = targetType.newSObject();
                
                for (String sourceField : fieldMapping.keySet()) {
                    String targetField = fieldMapping.get(sourceField);
                    if (row.containsKey(sourceField)) {
                        record.put(targetField, row.get(sourceField));
                    }
                }
                
                records.add(record);
            }
            
            // Apply field-level security before insert
            if (!records.isEmpty()) {
                // Use Security.stripInaccessible to enforce FLS
                SObjectAccessDecision decision = Security.stripInaccessible(
                    AccessType.CREATABLE,
                    records,
                    true // Enforce FLS
                );
                
                // Get the sanitized records
                records = decision.getRecords();
                
                // Log any stripped fields
                Map<String, Set<String>> strippedFields = decision.getRemovedFields();
                if (!strippedFields.isEmpty()) {
                    // FLS stripped fields during import
                }
            }
            
            // Insert in batches
            List<List<SObject>> batches = createSObjectBatches(records, config.batchSize);
            
            for (List<SObject> batch : batches) {
                Database.SaveResult[] saveResults = Database.insert(
                    batch, 
                    config.allOrNone
                );
                
                processSaveResults(saveResults, batch, result);
            }
            
            result.executionTime = DateTime.now().getTime() - startTime;
            return result;
            
        } catch (Exception e) {
            result.errors.add(new ErrorDetail('SYSTEM', e.getMessage()));
            result.executionTime = DateTime.now().getTime() - startTime;
            return result;
        }
    }
    
    // Bulk delete with recovery
    public static BulkOperationResult deleteBulk(
        List<Id> recordIds,
        Boolean createBackup,
        BulkConfig config
    ) {
        BulkOperationResult result = new BulkOperationResult();
        Long startTime = DateTime.now().getTime();
        
        try {
            result.totalRecords = recordIds.size();
            
            // Create backup if requested
            if (createBackup) {
                createBackupRecords(recordIds, result.operationId);
            }
            
            // Delete in batches
            List<List<Id>> batches = createBatches(recordIds, config.batchSize);
            
            for (List<Id> batch : batches) {
                Database.DeleteResult[] deleteResults = Database.delete(
                    batch, 
                    config.allOrNone
                );
                
                processDeleteResults(deleteResults, batch, result);
            }
            
            result.executionTime = DateTime.now().getTime() - startTime;
            return result;
            
        } catch (Exception e) {
            result.errors.add(new ErrorDetail('SYSTEM', e.getMessage()));
            result.executionTime = DateTime.now().getTime() - startTime;
            return result;
        }
    }
    
    // Bulk field update
    public static BulkOperationResult updateFieldBulk(
        String objectType,
        String fieldName,
        Object fieldValue,
        Map<String, Object> whereParams, // Changed from String whereClause to Map<String, Object>
        BulkConfig config
    ) {
        BulkOperationResult result = new BulkOperationResult();
        Long startTime = DateTime.now().getTime();
        
        try {
            // Validate object type against schema
            Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(objectType);
            if (sObjType == null) {
                throw new SecurityException('Invalid object type: ' + objectType);
            }
            
            // Validate field name exists
            Schema.SObjectField field = sObjType.getDescribe().fields.getMap().get(fieldName);
            if (field == null) {
                throw new SecurityException('Invalid field: ' + fieldName);
            }
            
            // Check field update access
            if (!field.getDescribe().isUpdateable()) {
                throw new SecurityException('Field is not updateable: ' + fieldName);
            }
            
            // Build secure query with bind variables
            String query = 'SELECT Id FROM ' + sObjType.getDescribe().getName();
            
            // Prepare bind variables map
            Map<String, Object> bindVars = new Map<String, Object>();
            
            if (whereParams != null && !whereParams.isEmpty()) {
                query += ' WHERE ';
                List<String> conditions = new List<String>();
                
                // Build conditions with bind variable placeholders
                Integer paramIndex = 0;
                for (String paramName : whereParams.keySet()) {
                    // Validate field exists
                    if (!sObjType.getDescribe().fields.getMap().containsKey(paramName)) {
                        throw new SecurityException('Invalid field in where clause: ' + paramName);
                    }
                    
                    String bindVarName = 'param_' + paramIndex;
                    conditions.add(paramName + ' = :' + bindVarName);
                    bindVars.put(bindVarName, whereParams.get(paramName));
                    paramIndex++;
                }
                
                query += String.join(conditions, ' AND ');
            }
            
            query += ' WITH SECURITY_ENFORCED LIMIT 50000';
            
            // Execute query with bind variables using AccessLevel.USER_MODE
            List<SObject> records = Database.queryWithBinds(query, bindVars, AccessLevel.USER_MODE);
            result.totalRecords = records.size();
            
            // Update field value for all records
            for (SObject record : records) {
                record.put(fieldName, fieldValue);
            }
            
            // Apply field-level security before update
            if (!records.isEmpty()) {
                // Use Security.stripInaccessible to enforce FLS
                SObjectAccessDecision decision = Security.stripInaccessible(
                    AccessType.UPDATABLE,
                    records,
                    true // Enforce FLS
                );
                
                // Get the sanitized records
                records = decision.getRecords();
                
                // Log any stripped fields for debugging
                Map<String, Set<String>> strippedFields = decision.getRemovedFields();
                if (!strippedFields.isEmpty()) {
                    // FLS stripped fields
                    // Optionally log to security audit
                    // SecurityAuditService.logFieldStripping(strippedFields);
                }
            }
            
            // Update in batches
            List<List<SObject>> batches = createSObjectBatches(records, config.batchSize);
            
            for (List<SObject> batch : batches) {
                Database.SaveResult[] saveResults = Database.update(
                    batch, 
                    config.allOrNone
                );
                
                processSaveResults(saveResults, batch, result);
            }
            
            result.executionTime = DateTime.now().getTime() - startTime;
            return result;
            
        } catch (Exception e) {
            result.errors.add(new ErrorDetail('SYSTEM', e.getMessage()));
            result.executionTime = DateTime.now().getTime() - startTime;
            return result;
        }
    }
    
    // Progress tracking
    public static void trackProgress(String operationId, Integer processed, Integer total) {
        // Create progress event
        AI_Bulk_Progress__e progressEvent = new AI_Bulk_Progress__e();
        progressEvent.Operation_Id__c = operationId;
        progressEvent.Records_Processed__c = processed;
        progressEvent.Total_Records__c = total;
        progressEvent.Progress_Percentage__c = (Decimal)processed / total * 100;
        progressEvent.Timestamp__c = DateTime.now();
        
        // Publish event
        EventBus.publish(progressEvent);
    }
    
    // Helper methods
    private static List<List<Id>> createBatches(List<Id> ids, Integer batchSize) {
        List<List<Id>> batches = new List<List<Id>>();
        List<Id> currentBatch = new List<Id>();
        
        for (Id recordId : ids) {
            currentBatch.add(recordId);
            
            if (currentBatch.size() >= batchSize) {
                batches.add(currentBatch);
                currentBatch = new List<Id>();
            }
        }
        
        if (!currentBatch.isEmpty()) {
            batches.add(currentBatch);
        }
        
        return batches;
    }
    
    private static List<List<SObject>> createSObjectBatches(
        List<SObject> records, 
        Integer batchSize
    ) {
        List<List<SObject>> batches = new List<List<SObject>>();
        List<SObject> currentBatch = new List<SObject>();
        
        for (SObject record : records) {
            currentBatch.add(record);
            
            if (currentBatch.size() >= batchSize) {
                batches.add(currentBatch);
                currentBatch = new List<SObject>();
            }
        }
        
        if (!currentBatch.isEmpty()) {
            batches.add(currentBatch);
        }
        
        return batches;
    }
    
    private static void processBatch(
        List<Id> batchIds, 
        String providerType,
        BulkOperationResult result,
        BulkConfig config
    ) {
        try {
            // Process route calculations
            List<AI_Processing_Status__c> statusRecords = 
                new List<AI_Processing_Status__c>();
            
            for (Id routeId : batchIds) {
                AI_Processing_Status__c status = new AI_Processing_Status__c();
                status.Route__c = routeId;
                status.Provider_Type__c = providerType;
                status.Status__c = 'Processing';
                status.Started_At__c = DateTime.now();
                
                statusRecords.add(status);
            }
            
            Database.SaveResult[] saveResults = Database.insert(
                statusRecords, 
                config.allOrNone
            );
            
            processSaveResults(saveResults, statusRecords, result);
            
            // Track progress if enabled
            if (config.trackProgress) {
                trackProgress(
                    result.operationId, 
                    result.successCount, 
                    result.totalRecords
                );
            }
            
        } catch (Exception e) {
            result.errors.add(new ErrorDetail('BATCH', e.getMessage()));
        }
    }
    
    private static void processSaveResults(
        Database.SaveResult[] saveResults,
        List<SObject> records,
        BulkOperationResult result
    ) {
        for (Integer i = 0; i < saveResults.size(); i++) {
            Database.SaveResult sr = saveResults[i];
            
            if (sr.isSuccess()) {
                result.successCount++;
            } else {
                result.errorCount++;
                String recordId = records[i].Id != null ? 
                    String.valueOf(records[i].Id) : 'NEW_' + i;
                
                for (Database.Error err : sr.getErrors()) {
                    ErrorDetail error = new ErrorDetail(
                        recordId,
                        err.getMessage()
                    );
                    error.fieldName = String.join(err.getFields(), ',');
                    result.errors.add(error);
                }
            }
        }
    }
    
    private static void processDeleteResults(
        Database.DeleteResult[] deleteResults,
        List<Id> recordIds,
        BulkOperationResult result
    ) {
        for (Integer i = 0; i < deleteResults.size(); i++) {
            Database.DeleteResult dr = deleteResults[i];
            
            if (dr.isSuccess()) {
                result.successCount++;
            } else {
                result.errorCount++;
                
                for (Database.Error err : dr.getErrors()) {
                    result.errors.add(new ErrorDetail(
                        recordIds[i],
                        err.getMessage()
                    ));
                }
            }
        }
    }
    
    private static Boolean shouldDeferProcessing() {
        return Limits.getQueries() > 90 || 
               Limits.getDMLRows() > 9000 ||
               Limits.getCpuTime() > 9000;
    }
    
    private static void queueRemainingBatches(
        List<List<Id>> allBatches, 
        String operationId
    ) {
        // Implementation would queue remaining work
        // Queueing remaining batches for operation
    }
    
    private static void createBackupRecords(List<Id> recordIds, String operationId) {
        // Implementation would create backup records
        // Creating backup for operation
    }
    
    private static void sendCompletionNotification(
        BulkOperationResult result,
        String email
    ) {
        // Send email notification
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[] { email });
        mail.setSubject('Bulk Operation Complete: ' + result.operationId);
        mail.setPlainTextBody(
            'Operation completed with ' + result.successCount + ' successes and ' +
            result.errorCount + ' errors. Total execution time: ' + 
            result.executionTime + 'ms'
        );
        
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }
}