/**
 * @description Service to detect and handle orphaned cases in AI processing pipeline
 * @author RouteLogic Team
 * @date 2025-01-18
 */
public with sharing class OrphanedCaseDetectionService {
    
    private static final Integer ORPHANED_THRESHOLD_HOURS = 24;
    private static final Integer BATCH_SIZE = 200;
    private static final String ORPHANED_STATUS = 'AI Processing Orphaned';
    
    /**
     * @description Detect cases that have been stuck in processing
     * @return List of orphaned case IDs
     */
    public static List<Id> detectOrphanedCases() {
        DateTime thresholdTime = DateTime.now().addHours(-ORPHANED_THRESHOLD_HOURS);
        
        // Find cases stuck in processing status
        List<Case> orphanedCases = [
            SELECT Id, CaseNumber, AI_Processing_Status__c, AI_Last_Analysis__c,
                   Subject, Priority, Status, OwnerId, Owner.Name
            FROM Case
            WHERE AI_Processing_Status__c IN ('Processing', 'Pending', 'Queued')
            AND (AI_Last_Analysis__c < :thresholdTime OR AI_Last_Analysis__c = null)
            AND Status != 'Closed'
            WITH SECURITY_ENFORCED
            LIMIT :BATCH_SIZE
        ];
        
        List<Id> orphanedCaseIds = new List<Id>();
        
        for (Case c : orphanedCases) {
            // Additional validation - check if there's an active retry request
            if (!hasActiveRetryRequest(c.Id)) {
                orphanedCaseIds.add(c.Id);
            }
        }
        
        // Log detection results
        if (!orphanedCaseIds.isEmpty()) {
            AuditService.logOperationalEvent(
                'ORPHANED_CASE_DETECTION',
                'Detected ' + orphanedCaseIds.size() + ' orphaned cases',
                'Success'
            );
        }
        
        return orphanedCaseIds;
    }
    
    /**
     * @description Handle orphaned cases by reassigning or escalating
     * @param orphanedCaseIds List of orphaned case IDs
     * @return Number of cases successfully handled
     */
    public static Integer handleOrphanedCases(List<Id> orphanedCaseIds) {
        if (orphanedCaseIds.isEmpty()) {
            return 0;
        }
        
        List<Case> casesToUpdate = new List<Case>();
        List<AI_Processing_Status__c> statusRecords = new List<AI_Processing_Status__c>();
        List<Task> escalationTasks = new List<Task>();
        
        // Retrieve full case details
        Map<Id, Case> orphanedCases = new Map<Id, Case>([
            SELECT Id, CaseNumber, AI_Processing_Status__c, AI_Last_Analysis__c,
                   Subject, Priority, Status, OwnerId, Owner.Name, Owner.IsActive,
                   Account.Name, Contact.Name
            FROM Case
            WHERE Id IN :orphanedCaseIds
            WITH SECURITY_ENFORCED
        ]);
        
        for (Case c : orphanedCases.values()) {
            // Reset processing status
            c.AI_Processing_Status__c = ORPHANED_STATUS;
            casesToUpdate.add(c);
            
            // Create status record for tracking
            AI_Processing_Status__c status = new AI_Processing_Status__c(
                Case__c = c.Id,
                Status__c = 'Orphaned',
                Error_Message__c = 'Case was orphaned after ' + ORPHANED_THRESHOLD_HOURS + ' hours without processing',
                Request_Time__c = c.AI_Last_Analysis__c != null ? c.AI_Last_Analysis__c : DateTime.now().addHours(-ORPHANED_THRESHOLD_HOURS),
                Response_Time__c = DateTime.now(),
                Success__c = false,
                AI_Provider__c = 'System'
            );
            statusRecords.add(status);
            
            // Determine reassignment strategy
            if (!c.Owner.IsActive || c.Priority == 'High') {
                // Create escalation task for inactive owner or high priority
                Task escalation = createEscalationTask(c);
                escalationTasks.add(escalation);
            } else {
                // Re-queue for processing
                requeueCaseForProcessing(c);
            }
        }
        
        // Perform DML operations
        Integer successCount = 0;
        
        try {
            if (!casesToUpdate.isEmpty()) {
                List<Database.SaveResult> caseResults = Database.update(
                    SecurityUtils.stripInaccessibleRecords(AccessType.UPDATABLE, casesToUpdate),
                    false
                );
                successCount = countSuccesses(caseResults);
            }
            
            if (!statusRecords.isEmpty()) {
                insert SecurityUtils.stripInaccessibleRecords(AccessType.CREATABLE, statusRecords);
            }
            
            if (!escalationTasks.isEmpty()) {
                insert SecurityUtils.stripInaccessibleRecords(AccessType.CREATABLE, escalationTasks);
            }
            
        } catch (Exception e) {
            ErrorLogService.logError('OrphanedCaseDetectionService.handleOrphanedCases', e, 
                'Failed to handle ' + orphanedCaseIds.size() + ' orphaned cases');
        }
        
        // Send alert if significant number of orphaned cases
        if (orphanedCaseIds.size() >= 10) {
            sendOrphanedCaseAlert(orphanedCaseIds.size());
        }
        
        return successCount;
    }
    
    /**
     * @description Schedule detection and handling of orphaned cases
     * @param cronExpression CRON expression for scheduling (default: hourly)
     */
    public static String scheduleOrphanedCaseDetection(String cronExpression) {
        if (String.isBlank(cronExpression)) {
            // Default to hourly execution
            cronExpression = '0 0 * * * ?';
        }
        
        OrphanedCaseDetectionBatch batch = new OrphanedCaseDetectionBatch();
        return System.schedule('Orphaned Case Detection - ' + DateTime.now().format(), cronExpression, batch);
    }
    
    /**
     * @description Check if case has an active retry request
     */
    private static Boolean hasActiveRetryRequest(Id caseId) {
        // Validate access before querying
        if (!RouteLogicSecurityUtils.hasReadAccess('AI_Retry_Request__c')) {
            
            return false; // Assume no active retry if can't check
        }
        
        List<AI_Retry_Request__c> activeRetries = [
            SELECT Id
            FROM AI_Retry_Request__c
            WHERE Case__c = :caseId
            AND Status__c IN ('Pending', 'Processing')
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        
        return !activeRetries.isEmpty();
    }
    
    /**
     * @description Create escalation task for orphaned case
     */
    private static Task createEscalationTask(Case c) {
        // Find appropriate escalation user
        Id escalationUserId = findEscalationUser(c);
        
        Task escalation = new Task(
            Subject = 'URGENT: Orphaned AI Processing Case - ' + c.CaseNumber,
            Description = buildEscalationDescription(c),
            Priority = 'High',
            Status = 'Not Started',
            ActivityDate = Date.today(),
            WhatId = c.Id,
            OwnerId = escalationUserId
        );
        
        return escalation;
    }
    
    /**
     * @description Find appropriate user for escalation
     */
    private static Id findEscalationUser(Case c) {
        // First try to find an active queue member
        List<GroupMember> queueMembers = new List<GroupMember>();
        if (RouteLogicSecurityUtils.hasReadAccess('GroupMember')) {
            queueMembers = [
                SELECT UserOrGroupId
                FROM GroupMember
                WHERE Group.Type = 'Queue'
                AND Group.DeveloperName = 'AI_Processing_Escalation_Queue'
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        }
        
        if (!queueMembers.isEmpty()) {
            return queueMembers[0].UserOrGroupId;
        }
        
        // Fallback to active system admin
        List<User> admins = new List<User>();
        if (RouteLogicSecurityUtils.hasReadAccess('User')) {
            admins = [
                SELECT Id
                FROM User
                WHERE Profile.Name = 'System Administrator'
                AND IsActive = true
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        }
        
        return !admins.isEmpty() ? admins[0].Id : UserInfo.getUserId();
    }
    
    /**
     * @description Build escalation task description
     */
    private static String buildEscalationDescription(Case c) {
        List<String> details = new List<String>{
            'This case has been orphaned in the AI processing pipeline.',
            '',
            'Case Details:',
            '- Case Number: ' + c.CaseNumber,
            '- Subject: ' + c.Subject,
            '- Priority: ' + c.Priority,
            '- Current Status: ' + c.Status,
            '- Last AI Analysis: ' + (c.AI_Last_Analysis__c != null ? c.AI_Last_Analysis__c.format() : 'Never'),
            '- Processing Status: ' + c.AI_Processing_Status__c,
            '- Original Owner: ' + c.Owner.Name
        };
        
        if (c.Account != null) {
            details.add('- Account: ' + c.Account.Name);
        }
        
        if (c.Contact != null) {
            details.add('- Contact: ' + c.Contact.Name);
        }
        
        details.addAll(new List<String>{
            '',
            'Required Actions:',
            '1. Review the case and determine appropriate routing',
            '2. Manually process or re-queue for AI processing',
            '3. Update the case status and notify relevant parties',
            '4. Investigate why this case became orphaned'
        });
        
        return String.join(details, '\n');
    }
    
    /**
     * @description Re-queue case for AI processing
     */
    private static void requeueCaseForProcessing(Case c) {
        // Create new AI case request event
        AI_Case_Request__e request = new AI_Case_Request__e(
            CaseId__c = c.Id,
            Request_Type__c = 'Reprocess',
            Priority__c = c.Priority,
            AI_Provider__c = 'Auto',
            Status__c = 'Pending',
            Metadata__c = JSON.serialize(new Map<String, Object>{
                'orphanedDetection' => true,
                'originalStatus' => c.AI_Processing_Status__c,
                'detectionTime' => DateTime.now()
            })
        );
        
        EventBus.publish(request);
    }
    
    /**
     * @description Send alert for significant number of orphaned cases
     */
    private static void sendOrphanedCaseAlert(Integer count) {
        // Publish critical error event
        AI_Critical_Error__e alert = new AI_Critical_Error__e(
            Error_Type__c = 'Orphaned Cases Detected',
            Error_Message__c = count + ' cases detected as orphaned in AI processing pipeline',
            Component__c = 'OrphanedCaseDetectionService',
            Severity__c = 'High',
            Stack_Trace__c = 'Threshold: ' + ORPHANED_THRESHOLD_HOURS + ' hours'
        );
        
        EventBus.publish(alert);
        
        // Log to audit trail
        AuditService.logOperationalEvent(
            'ORPHANED_CASE_ALERT',
            'Alert sent for ' + count + ' orphaned cases',
            'Warning'
        );
    }
    
    /**
     * @description Count successful DML operations
     */
    private static Integer countSuccesses(List<Database.SaveResult> results) {
        Integer count = 0;
        for (Database.SaveResult result : results) {
            if (result.isSuccess()) {
                count++;
            }
        }
        return count;
    }
    
    /**
     * @description Get orphaned case statistics
     */
    @AuraEnabled(cacheable=true)
    public static OrphanedCaseStats getOrphanedCaseStatistics() {
        OrphanedCaseStats stats = new OrphanedCaseStats();
        
        DateTime thresholdTime = DateTime.now().addHours(-ORPHANED_THRESHOLD_HOURS);
        
        // Count current orphaned cases
        stats.currentOrphanedCount = [
            SELECT COUNT()
            FROM Case
            WHERE AI_Processing_Status__c = :ORPHANED_STATUS
            WITH SECURITY_ENFORCED
        ];
        
        // Count potential orphaned cases
        stats.potentialOrphanedCount = [
            SELECT COUNT()
            FROM Case
            WHERE AI_Processing_Status__c IN ('Processing', 'Pending', 'Queued')
            AND (AI_Last_Analysis__c < :thresholdTime OR AI_Last_Analysis__c = null)
            AND Status != 'Closed'
            WITH SECURITY_ENFORCED
        ];
        
        // Get recent detection history
        stats.last24HourDetections = [
            SELECT COUNT()
            FROM AI_Processing_Status__c
            WHERE Status__c = 'Orphaned'
            AND CreatedDate >= :DateTime.now().addHours(-24)
            WITH SECURITY_ENFORCED
        ];
        
        stats.thresholdHours = ORPHANED_THRESHOLD_HOURS;
        stats.lastDetectionRun = getLastDetectionRunTime();
        
        return stats;
    }
    
    /**
     * @description Get last detection run time
     */
    private static DateTime getLastDetectionRunTime() {
        // Validate access before querying
        if (!RouteLogicSecurityUtils.hasReadAccess('AI_Audit_Event__c')) {
            
            return null;
        }
        
        List<AI_Audit_Event__c> lastRun = [
            SELECT Timestamp__c
            FROM AI_Audit_Event__c
            WHERE Event_Type__c = 'ORPHANED_CASE_DETECTION'
            WITH SECURITY_ENFORCED
            ORDER BY Timestamp__c DESC
            LIMIT 1
        ];
        
        return !lastRun.isEmpty() ? lastRun[0].Timestamp__c : null;
    }
    
    /**
     * @description Stats class for orphaned cases
     */
    public class OrphanedCaseStats {
        @AuraEnabled public Integer currentOrphanedCount { get; set; }
        @AuraEnabled public Integer potentialOrphanedCount { get; set; }
        @AuraEnabled public Integer last24HourDetections { get; set; }
        @AuraEnabled public Integer thresholdHours { get; set; }
        @AuraEnabled public DateTime lastDetectionRun { get; set; }
        
        public OrphanedCaseStats() {
            this.currentOrphanedCount = 0;
            this.potentialOrphanedCount = 0;
            this.last24HourDetections = 0;
        }
    }
}