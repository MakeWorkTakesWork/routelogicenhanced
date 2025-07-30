/**
 * @description Automated log retention scheduler for cleaning up old logs
 * @author RouteLogic Team
 * @date 2025-01-20
 */
public with sharing class LogRetentionScheduler implements Schedulable {
    
    /**
     * @description Execute scheduled job
     * @param ctx Schedulable context
     */
    public void execute(SchedulableContext ctx) {
        try {
            // Get retention settings from custom metadata
            Integer errorLogRetentionDays = getErrorLogRetentionDays();
            Integer auditLogRetentionDays = getAuditLogRetentionDays();
            
            // Clean up error logs
            if (errorLogRetentionDays > 0) {
                cleanupErrorLogs(errorLogRetentionDays);
            }
            
            // Clean up audit logs
            if (auditLogRetentionDays > 0) {
                cleanupAuditLogs(auditLogRetentionDays);
            }
            
            // Clean up AI processing logs
            cleanupAIProcessingLogs();
            
            // Log the cleanup operation
            AuditService.logOperationalEvent(
                'LOG_RETENTION_CLEANUP',
                'Automated log retention cleanup completed',
                'Success'
            );
            
        } catch (Exception e) {
            // Log error but don't throw to prevent job failure
            ErrorLogService.logError(
                'LogRetentionScheduler',
                e,
                'Failed to execute log retention cleanup'
            );
        }
    }
    
    /**
     * @description Clean up old error logs
     * @param retentionDays Number of days to retain logs
     */
    private void cleanupErrorLogs(Integer retentionDays) {
        DateTime cutoffDate = DateTime.now().addDays(-retentionDays);
        
        // Use batch delete for large volumes
        Database.executeBatch(
            new LogRetentionBatch('Error_Log__c', cutoffDate),
            200
        );
    }
    
    /**
     * @description Clean up old audit logs
     * @param retentionDays Number of days to retain logs
     */
    private void cleanupAuditLogs(Integer retentionDays) {
        DateTime cutoffDate = DateTime.now().addDays(-retentionDays);
        
        // Audit logs require special handling - archive before delete
        List<AI_Audit_Event__c> logsToArchive = [
            SELECT Id, Event_Type__c, Category__c, Description__c, 
                   Status__c, User_Id__c, Timestamp__c, Security_Hash__c
            FROM AI_Audit_Event__c
            WHERE Timestamp__c < :cutoffDate
            AND Category__c != 'COMPLIANCE' // Never delete compliance logs
            WITH SECURITY_ENFORCED
            LIMIT 10000
        ];
        
        if (!logsToArchive.isEmpty()) {
            // Archive to external system or file before deletion
            archiveAuditLogs(logsToArchive);
            
            // Delete after successful archive
            delete SecurityUtils.stripInaccessibleRecords(
                AccessType.DELETABLE,
                logsToArchive
            );
        }
    }
    
    /**
     * @description Clean up AI processing logs
     */
    private void cleanupAIProcessingLogs() {
        // Clean up old AI processing status records (keep 30 days)
        DateTime statusCutoff = DateTime.now().addDays(-30);
        
        List<AI_Processing_Status__c> statusesToDelete = [
            SELECT Id
            FROM AI_Processing_Status__c
            WHERE CreatedDate < :statusCutoff
            WITH SECURITY_ENFORCED
            LIMIT 10000
        ];
        
        if (!statusesToDelete.isEmpty()) {
            delete SecurityUtils.stripInaccessibleRecords(
                AccessType.DELETABLE,
                statusesToDelete
            );
        }
        
        // Clean up old metrics (keep 90 days)
        DateTime metricsCutoff = DateTime.now().addDays(-90);
        
        List<AI_Bulk_Processing_Metrics__c> metricsToDelete = [
            SELECT Id
            FROM AI_Bulk_Processing_Metrics__c
            WHERE CreatedDate < :metricsCutoff
            WITH SECURITY_ENFORCED
            LIMIT 10000
        ];
        
        if (!metricsToDelete.isEmpty()) {
            delete SecurityUtils.stripInaccessibleRecords(
                AccessType.DELETABLE,
                metricsToDelete
            );
        }
    }
    
    /**
     * @description Archive audit logs before deletion
     * @param logs Logs to archive
     */
    private void archiveAuditLogs(List<AI_Audit_Event__c> logs) {
        // Create archive records or export to external system
        String archiveData = JSON.serialize(logs);
        
        // Store archive reference
        AI_Archive_Reference__c archiveRef = new AI_Archive_Reference__c(
            Archive_Type__c = 'Audit_Logs',
            Record_Count__c = logs.size(),
            Archive_Date__c = DateTime.now(),
            Date_Range_Start__c = getOldestTimestamp(logs),
            Date_Range_End__c = getNewestTimestamp(logs),
            Archive_Location__c = 'Salesforce_Files',
            Archive_Status__c = 'Completed'
        );
        
        insert SecurityUtils.stripInaccessibleRecords(
            AccessType.CREATABLE,
            new List<AI_Archive_Reference__c>{archiveRef}
        )[0];
        
        // Create file attachment with archived data
        ContentVersion cv = new ContentVersion(
            Title = 'Audit_Log_Archive_' + DateTime.now().format('yyyy-MM-dd'),
            PathOnClient = 'audit_archive.json',
            VersionData = Blob.valueOf(archiveData),
            Description = 'Archived audit logs from ' + archiveRef.Date_Range_Start__c.format() + 
                         ' to ' + archiveRef.Date_Range_End__c.format()
        );
        
        insert cv;
        
        // Link to archive reference
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId,
            LinkedEntityId = archiveRef.Id,
            ShareType = 'V'
        );
        
        insert cdl;
    }
    
    /**
     * @description Get error log retention days from configuration
     */
    private Integer getErrorLogRetentionDays() {
        // Default to 30 days if not configured
        return ConfigManager.getErrorLogRetentionDays() != null ? 
            ConfigManager.getErrorLogRetentionDays() : 30;
    }
    
    /**
     * @description Get audit log retention days from configuration
     */
    private Integer getAuditLogRetentionDays() {
        // Default to 365 days for audit logs
        return ConfigManager.getAuditLogRetentionDays() != null ? 
            ConfigManager.getAuditLogRetentionDays() : 365;
    }
    
    /**
     * @description Get oldest timestamp from logs
     */
    private DateTime getOldestTimestamp(List<AI_Audit_Event__c> logs) {
        DateTime oldest = logs[0].Timestamp__c;
        for (AI_Audit_Event__c log : logs) {
            if (log.Timestamp__c < oldest) {
                oldest = log.Timestamp__c;
            }
        }
        return oldest;
    }
    
    /**
     * @description Get newest timestamp from logs
     */
    private DateTime getNewestTimestamp(List<AI_Audit_Event__c> logs) {
        DateTime newest = logs[0].Timestamp__c;
        for (AI_Audit_Event__c log : logs) {
            if (log.Timestamp__c > newest) {
                newest = log.Timestamp__c;
            }
        }
        return newest;
    }
    
    /**
     * @description Schedule the retention job
     * @param cronExpression CRON expression for scheduling
     * @return Job ID
     */
    public static String scheduleJob(String cronExpression) {
        // Default to daily at 2 AM if not specified
        if (String.isBlank(cronExpression)) {
            cronExpression = '0 0 2 * * ?';
        }
        
        return System.schedule(
            'Log Retention Cleanup - ' + DateTime.now().format(),
            cronExpression,
            new LogRetentionScheduler()
        );
    }
}