/**
 * @description Test class for OrphanedCaseDetectionService
 * @author RouteLogic Team
 * @date 2025-01-18
 */
@isTest
private class OrphanedCaseDetectionServiceTest {
    
    @testSetup
    static void setup() {
        // Create test cases in various states
        List<Case> testCases = new List<Case>();
        
        // Create orphaned cases (stuck in processing > 24 hours)
        for (Integer i = 0; i < 5; i++) {
            Case c = new Case(
                Subject = 'Orphaned Test Case ' + i,
                Priority = 'High',
                Status = 'New',
                AI_Processing_Status__c = 'Processing',
                AI_Last_Analysis__c = DateTime.now().addHours(-30) // 30 hours ago
            );
            testCases.add(c);
        }
        
        // Create recent processing cases (not orphaned)
        for (Integer i = 0; i < 3; i++) {
            Case c = new Case(
                Subject = 'Recent Test Case ' + i,
                Priority = 'Medium',
                Status = 'New',
                AI_Processing_Status__c = 'Processing',
                AI_Last_Analysis__c = DateTime.now().addHours(-2) // 2 hours ago
            );
            testCases.add(c);
        }
        
        // Create completed cases
        for (Integer i = 0; i < 2; i++) {
            Case c = new Case(
                Subject = 'Completed Test Case ' + i,
                Priority = 'Low',
                Status = 'Closed',
                AI_Processing_Status__c = 'Processed',
                AI_Last_Analysis__c = DateTime.now().addHours(-48)
            );
            testCases.add(c);
        }
        
        insert testCases;
        
        // Create test queue
        Group testQueue = new Group(
            Name = 'AI Processing Escalation Queue',
            DeveloperName = 'AI_Processing_Escalation_Queue',
            Type = 'Queue'
        );
        insert testQueue;
        
        // Add queue support for Case object
        QueueSobject queueCase = new QueueSobject(
            QueueId = testQueue.Id,
            SobjectType = 'Case'
        );
        insert queueCase;
    }
    
    @isTest
    static void testDetectOrphanedCases() {
        Test.startTest();
        
        List<Id> orphanedIds = OrphanedCaseDetectionService.detectOrphanedCases();
        
        Test.stopTest();
        
        // Should detect the 5 orphaned cases
        System.assertEquals(5, orphanedIds.size(), 'Should detect 5 orphaned cases');
        
        // Verify correct cases were identified
        List<Case> orphanedCases = [
            SELECT Subject, AI_Processing_Status__c
            FROM Case
            WHERE Id IN :orphanedIds
        ];
        
        for (Case c : orphanedCases) {
            System.assert(c.Subject.startsWith('Orphaned Test Case'), 'Should only detect orphaned cases');
            System.assertEquals('Processing', c.AI_Processing_Status__c, 'Should be in processing status');
        }
    }
    
    @isTest
    static void testHandleOrphanedCases() {
        // Get orphaned cases
        List<Id> orphanedIds = OrphanedCaseDetectionService.detectOrphanedCases();
        
        Test.startTest();
        
        Integer handled = OrphanedCaseDetectionService.handleOrphanedCases(orphanedIds);
        
        Test.stopTest();
        
        // Verify cases were updated
        System.assertEquals(5, handled, 'Should handle all 5 orphaned cases');
        
        List<Case> updatedCases = [
            SELECT AI_Processing_Status__c
            FROM Case
            WHERE Id IN :orphanedIds
        ];
        
        for (Case c : updatedCases) {
            System.assertEquals('AI Processing Orphaned', c.AI_Processing_Status__c, 
                'Should update processing status');
        }
        
        // Verify status records created
        Integer statusCount = [
            SELECT COUNT()
            FROM AI_Processing_Status__c
            WHERE Status__c = 'Orphaned'
        ];
        System.assertEquals(5, statusCount, 'Should create status records');
        
        // Verify escalation tasks created for high priority
        Integer taskCount = [
            SELECT COUNT()
            FROM Task
            WHERE Subject LIKE 'URGENT: Orphaned AI Processing Case%'
        ];
        System.assert(taskCount > 0, 'Should create escalation tasks');
    }
    
    @isTest
    static void testHandleEmptyOrphanedList() {
        Test.startTest();
        
        Integer handled = OrphanedCaseDetectionService.handleOrphanedCases(new List<Id>());
        
        Test.stopTest();
        
        System.assertEquals(0, handled, 'Should handle 0 cases for empty list');
    }
    
    @isTest
    static void testDetectWithActiveRetryRequest() {
        // Create a case with active retry
        Case testCase = new Case(
            Subject = 'Case with Active Retry',
            AI_Processing_Status__c = 'Processing',
            AI_Last_Analysis__c = DateTime.now().addHours(-30)
        );
        insert testCase;
        
        // Create active retry request
        AI_Retry_Request__c retry = new AI_Retry_Request__c(
            Case__c = testCase.Id,
            Status__c = 'Pending',
            Provider__c = 'Test',
            Request_Type__c = 'Process'
        );
        insert retry;
        
        Test.startTest();
        
        List<Id> orphanedIds = OrphanedCaseDetectionService.detectOrphanedCases();
        
        Test.stopTest();
        
        // Should not include case with active retry
        System.assert(!orphanedIds.contains(testCase.Id), 
            'Should not detect case with active retry request');
    }
    
    @isTest
    static void testScheduleOrphanedCaseDetection() {
        Test.startTest();
        
        String jobId = OrphanedCaseDetectionService.scheduleOrphanedCaseDetection(null);
        
        Test.stopTest();
        
        System.assertNotEquals(null, jobId, 'Should return job ID');
        
        // Verify scheduled job exists
        List<CronTrigger> jobs = [
            SELECT Id, CronExpression
            FROM CronTrigger
            WHERE Id = :jobId
        ];
        
        System.assertEquals(1, jobs.size(), 'Should create scheduled job');
        System.assertEquals('0 0 * * * ?', jobs[0].CronExpression, 'Should use hourly schedule');
    }
    
    @isTest
    static void testScheduleWithCustomCron() {
        String customCron = '0 30 * * * ?'; // Every hour at 30 minutes
        
        Test.startTest();
        
        String jobId = OrphanedCaseDetectionService.scheduleOrphanedCaseDetection(customCron);
        
        Test.stopTest();
        
        CronTrigger job = [
            SELECT CronExpression
            FROM CronTrigger
            WHERE Id = :jobId
        ];
        
        System.assertEquals(customCron, job.CronExpression, 'Should use custom cron expression');
    }
    
    @isTest
    static void testGetOrphanedCaseStatistics() {
        Test.startTest();
        
        OrphanedCaseDetectionService.OrphanedCaseStats stats = 
            OrphanedCaseDetectionService.getOrphanedCaseStatistics();
        
        Test.stopTest();
        
        System.assertNotEquals(null, stats, 'Should return stats object');
        System.assertEquals(0, stats.currentOrphanedCount, 'Should have no current orphaned');
        System.assertEquals(5, stats.potentialOrphanedCount, 'Should have 5 potential orphaned');
        System.assertEquals(24, stats.thresholdHours, 'Should have 24 hour threshold');
    }
    
    @isTest
    static void testOrphanedCaseAlert() {
        // Create 10+ orphaned cases to trigger alert
        List<Case> largeBatch = new List<Case>();
        for (Integer i = 0; i < 15; i++) {
            largeBatch.add(new Case(
                Subject = 'Bulk Orphaned ' + i,
                AI_Processing_Status__c = 'Processing',
                AI_Last_Analysis__c = DateTime.now().addHours(-30)
            ));
        }
        insert largeBatch;
        
        List<Id> caseIds = new List<Id>();
        for (Case c : largeBatch) {
            caseIds.add(c.Id);
        }
        
        Test.startTest();
        
        OrphanedCaseDetectionService.handleOrphanedCases(caseIds);
        
        Test.stopTest();
        
        // Verify alert was logged
        List<AI_Audit_Event__c> alerts = [
            SELECT Event_Type__c, Description__c
            FROM AI_Audit_Event__c
            WHERE Event_Type__c = 'ORPHANED_CASE_ALERT'
        ];
        
        System.assertEquals(1, alerts.size(), 'Should create alert for large batch');
        System.assert(alerts[0].Description__c.contains('15'), 
            'Alert should mention number of orphaned cases');
    }
    
    @isTest
    static void testRequeueForProcessing() {
        Case testCase = [
            SELECT Id, OwnerId, Owner.IsActive
            FROM Case
            WHERE Subject LIKE 'Orphaned Test Case%'
            AND Priority = 'High'
            LIMIT 1
        ];
        
        // Update owner to active to trigger requeue instead of escalation
        testCase.Priority = 'Low';
        update testCase;
        
        Test.startTest();
        
        OrphanedCaseDetectionService.handleOrphanedCases(new List<Id>{testCase.Id});
        
        Test.stopTest();
        
        // Platform events are published but can't be queried in test
        // Verify case was updated
        Case updatedCase = [
            SELECT AI_Processing_Status__c
            FROM Case
            WHERE Id = :testCase.Id
        ];
        
        System.assertEquals('AI Processing Orphaned', updatedCase.AI_Processing_Status__c, 
            'Should update case status');
    }
}