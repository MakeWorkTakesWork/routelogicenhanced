/**
 * @description Batch class for scheduled orphaned case detection
 * @author RouteLogic Team
 * @date 2025-01-18
 */
public with sharing class OrphanedCaseDetectionBatch implements Schedulable, Database.Batchable<SObject> {
    
    /**
     * @description Execute method for schedulable interface
     */
    public void execute(SchedulableContext sc) {
        Database.executeBatch(this, 200);
    }
    
    /**
     * @description Start method for batch
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        DateTime thresholdTime = DateTime.now().addHours(-24);
        
        return Database.getQueryLocator([
            SELECT Id, CaseNumber, AI_Processing_Status__c, AI_Last_Analysis__c,
                   Subject, Priority, Status, OwnerId
            FROM Case
            WHERE AI_Processing_Status__c IN ('Processing', 'Pending', 'Queued')
            AND (AI_Last_Analysis__c < :thresholdTime OR AI_Last_Analysis__c = null)
            AND Status != 'Closed'
            WITH SECURITY_ENFORCED
        ]);
    }
    
    /**
     * @description Execute method for batch
     */
    public void execute(Database.BatchableContext bc, List<Case> scope) {
        List<Id> orphanedCaseIds = new List<Id>();
        
        for (Case c : scope) {
            orphanedCaseIds.add(c.Id);
        }
        
        if (!orphanedCaseIds.isEmpty()) {
            OrphanedCaseDetectionService.handleOrphanedCases(orphanedCaseIds);
        }
    }
    
    /**
     * @description Finish method for batch
     */
    public void finish(Database.BatchableContext bc) {
        // Log completion
        AuditService.logOperationalEvent(
            'ORPHANED_CASE_BATCH_COMPLETE',
            'Orphaned case detection batch completed. Job ID: ' + bc.getJobId(),
            'Success'
        );
    }
}