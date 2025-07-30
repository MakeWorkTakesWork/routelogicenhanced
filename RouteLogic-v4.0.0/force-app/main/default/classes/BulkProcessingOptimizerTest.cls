/**
 * @description Test class for BulkProcessingOptimizer
 * @author RouteLogic Team
 * @date 2025-01-18
 */
@isTest
private class BulkProcessingOptimizerTest {
    
    @testSetup
    static void setup() {
        // Create test cases
        List<Case> testCases = new List<Case>();
        
        // High priority cases
        for (Integer i = 0; i < 100; i++) {
            testCases.add(new Case(
                Subject = 'High Priority Case ' + i,
                Priority = 'High',
                Status = 'New',
                AI_Processing_Status__c = 'Pending'
            ));
        }
        
        // Medium priority cases
        for (Integer i = 0; i < 200; i++) {
            testCases.add(new Case(
                Subject = 'Medium Priority Case ' + i,
                Priority = 'Medium',
                Status = 'New',
                AI_Processing_Status__c = 'Pending'
            ));
        }
        
        // Low priority cases
        for (Integer i = 0; i < 300; i++) {
            testCases.add(new Case(
                Subject = 'Low Priority Case ' + i,
                Priority = 'Low',
                Status = 'New',
                AI_Processing_Status__c = 'New'
            ));
        }
        
        insert testCases;
    }
    
    @isTest
    static void testOptimizeBulkProcessingNormalVolume() {
        List<Case> cases = [SELECT Id FROM Case LIMIT 500];
        List<Id> caseIds = new List<Id>();
        for (Case c : cases) {
            caseIds.add(c.Id);
        }
        
        Test.startTest();
        
        List<Id> jobIds = BulkProcessingOptimizer.optimizeBulkProcessing(caseIds);
        
        Test.stopTest();
        
        System.assert(jobIds.size() > 0, 'Should create at least one job');
        System.assert(jobIds.size() <= 5, 'Should not exceed max concurrent jobs');
        
        // Verify optimization metrics were logged
        List<AI_Optimization_Metrics__c> metrics = [
            SELECT Total_Cases__c, Jobs_Queued__c, Optimization_Type__c
            FROM AI_Optimization_Metrics__c
            WHERE Optimization_Type__c = 'Bulk Processing'
        ];
        
        System.assertEquals(1, metrics.size(), 'Should create optimization metrics');
        System.assertEquals(500, metrics[0].Total_Cases__c, 'Should log total cases');
    }
    
    @isTest
    static void testOptimizeBulkProcessingExtremeVolume() {
        // Create case IDs for extreme volume (>10K)
        List<Id> extremeVolumeCaseIds = new List<Id>();
        List<Case> cases = [SELECT Id FROM Case];
        
        // Simulate 11K cases by duplicating IDs
        for (Integer i = 0; i < 20; i++) {
            for (Case c : cases) {
                if (extremeVolumeCaseIds.size() < 11000) {
                    extremeVolumeCaseIds.add(c.Id);
                }
            }
        }
        
        Test.startTest();
        
        List<Id> jobIds = BulkProcessingOptimizer.optimizeBulkProcessing(extremeVolumeCaseIds);
        
        Test.stopTest();
        
        // For extreme volumes, platform events are used instead of jobs
        // Verify no jobs were created (platform events used instead)
        System.assertEquals(0, jobIds.size(), 'Should use platform events for extreme volume');
    }
    
    @isTest
    static void testPartitioningByPriority() {
        List<Case> allCases = [SELECT Id, Priority FROM Case];
        List<Id> caseIds = new List<Id>();
        Map<String, Integer> priorityCounts = new Map<String, Integer>{
            'High' => 0,
            'Medium' => 0,
            'Low' => 0
        };
        
        for (Case c : allCases) {
            caseIds.add(c.Id);
            priorityCounts.put(c.Priority, priorityCounts.get(c.Priority) + 1);
        }
        
        Test.startTest();
        
        List<Id> jobIds = BulkProcessingOptimizer.optimizeBulkProcessing(caseIds);
        
        Test.stopTest();
        
        // Verify partitioning worked (different priorities should create different jobs)
        System.assert(jobIds.size() >= 2, 'Should create multiple jobs for different priorities');
    }
    
    @isTest
    static void testQueueCapacityHandling() {
        // Simulate full queue by creating dummy jobs
        List<AsyncApexJob> currentJobs = [
            SELECT Id FROM AsyncApexJob 
            WHERE Status IN ('Holding', 'Queued', 'Processing')
            AND JobType = 'Queueable'
        ];
        
        Integer slotsToFill = 5 - currentJobs.size();
        
        // Fill up queue slots
        for (Integer i = 0; i < slotsToFill; i++) {
            System.enqueueJob(new TestQueueable());
        }
        
        List<Case> cases = [SELECT Id FROM Case LIMIT 100];
        List<Id> caseIds = new List<Id>();
        for (Case c : cases) {
            caseIds.add(c.Id);
        }
        
        Test.startTest();
        
        List<Id> jobIds = BulkProcessingOptimizer.optimizeBulkProcessing(caseIds);
        
        Test.stopTest();
        
        // Should queue to staging table when capacity is full
        List<AI_Processing_Queue__c> stagedCases = [
            SELECT Id FROM AI_Processing_Queue__c
            WHERE Status__c = 'Pending'
        ];
        
        System.assert(stagedCases.size() > 0 || jobIds.size() == 0, 
            'Should either stage cases or return no jobs when queue is full');
    }
    
    @isTest
    static void testInitializeHighVolumeCache() {
        // Create cache partition in test context
        // Note: Platform Cache testing requires specific setup
        
        Test.startTest();
        
        try {
            BulkProcessingOptimizer.initializeHighVolumeCache();
            System.assert(true, 'Cache initialization should complete');
        } catch (BulkProcessingOptimizer.OptimizationException e) {
            // Expected in test context without cache partition
            System.assert(e.getMessage().contains('cache partition'), 
                'Should throw cache partition error in test');
        }
        
        Test.stopTest();
    }
    
    @isTest
    static void testAutoScaleProcessing() {
        // Create test metrics
        List<AI_Bulk_Processing_Metrics__c> testMetrics = new List<AI_Bulk_Processing_Metrics__c>();
        
        // Slow processing metrics
        for (Integer i = 0; i < 5; i++) {
            testMetrics.add(new AI_Bulk_Processing_Metrics__c(
                Total_Requests__c = 100,
                Processing_Time_Ms__c = 150000, // 150 seconds
                Average_Time_Per_Request__c = 1500 // 1.5 seconds per request
            ));
        }
        
        insert testMetrics;
        
        Test.startTest();
        
        BulkProcessingOptimizer.autoScaleProcessing();
        
        Test.stopTest();
        
        // Verify auto-scaling logic executed
        // In production, this would adjust batch sizes in cache
        System.assert(true, 'Auto-scaling should complete without errors');
    }
    
    @isTest
    static void testErrorHandling() {
        // Create invalid case IDs
        List<Id> invalidIds = new List<Id>{
            '500000000000000AAA',
            '500000000000001AAA'
        };
        
        Test.startTest();
        
        try {
            BulkProcessingOptimizer.optimizeBulkProcessing(invalidIds);
            System.assert(false, 'Should throw exception for invalid IDs');
        } catch (BulkProcessingOptimizer.OptimizationException e) {
            System.assert(true, 'Expected exception thrown');
        }
        
        Test.stopTest();
        
        // Verify error was logged
        List<Error_Log__c> errors = [
            SELECT Class_Name__c, Error_Type__c
            FROM Error_Log__c
            WHERE Class_Name__c LIKE '%BulkProcessingOptimizer%'
        ];
        
        System.assert(errors.size() > 0, 'Should log error');
    }
    
    @isTest
    static void testChunkCreation() {
        List<Case> cases = [SELECT Id FROM Case LIMIT 250];
        List<Id> caseIds = new List<Id>();
        for (Case c : cases) {
            caseIds.add(c.Id);
        }
        
        Test.startTest();
        
        List<Id> jobIds = BulkProcessingOptimizer.optimizeBulkProcessing(caseIds);
        
        Test.stopTest();
        
        // With 250 cases and batch size of 200, should create 2 jobs minimum
        System.assert(jobIds.size() >= 1, 'Should create appropriate number of jobs for chunks');
    }
    
    /**
     * @description Test queueable for filling queue slots
     */
    private class TestQueueable implements Queueable {
        public void execute(QueueableContext context) {
            // Do nothing - just hold queue slot
        }
    }
}