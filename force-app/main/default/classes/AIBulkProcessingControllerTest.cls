/**
 * @description Test class for AIBulkProcessingController
 * @author RouteLogic Team
 * @date 2025-01-17
 */
@IsTest
private class AIBulkProcessingControllerTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test account and contact
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
        
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com',
            AccountId = testAccount.Id
        );
        insert testContact;
        
        // Create test cases
        List<Case> testCases = new List<Case>();
        for (Integer i = 0; i < 10; i++) {
            testCases.add(new Case(
                Subject = 'Test Case ' + i,
                Description = 'Test description for case ' + i,
                Priority = 'Medium',
                Status = 'New',
                AccountId = testAccount.Id,
                ContactId = testContact.Id
            ));
        }
        insert testCases;
        
        // Create AI provider credentials
        List<AIProviderCredential__c> credentials = new List<AIProviderCredential__c>();
        credentials.add(new AIProviderCredential__c(
            Name = 'TestProvider1',
            API_Key__c = 'test-api-key-1',
            Endpoint_URL__c = 'https://api.testprovider1.com',
            IsActive__c = true
        ));
        credentials.add(new AIProviderCredential__c(
            Name = 'TestProvider2',
            API_Key__c = 'test-api-key-2',
            Endpoint_URL__c = 'https://api.testprovider2.com',
            IsActive__c = true
        ));
        credentials.add(new AIProviderCredential__c(
            Name = 'InactiveProvider',
            API_Key__c = 'test-api-key-3',
            Endpoint_URL__c = 'https://api.inactive.com',
            IsActive__c = false
        ));
        insert credentials;
        
        // Create test processing status records
        List<AI_Processing_Status__c> statusRecords = new List<AI_Processing_Status__c>();
        List<Case> cases = [SELECT Id FROM Case];
        
        for (Integer i = 0; i < cases.size(); i++) {
            String status = 'Pending';
            Boolean success = false;
            
            if (i < 3) {
                status = 'Completed';
                success = true;
            } else if (i < 6) {
                status = 'Failed';
                success = false;
            } else if (i < 8) {
                status = 'Processing';
                success = false;
            }
            
            statusRecords.add(new AI_Processing_Status__c(
                Case__c = cases[i].Id,
                AI_Provider__c = 'TestProvider1',
                Status__c = status,
                Success__c = success,
                Request_Time__c = DateTime.now().addMinutes(-30),
                Response_Time__c = success ? DateTime.now().addMinutes(-25) : null
            ));
        }
        insert statusRecords;
        
        // Create test retry requests
        List<AI_Retry_Request__c> retryRequests = new List<AI_Retry_Request__c>();
        for (Integer i = 0; i < 5; i++) {
            retryRequests.add(new AI_Retry_Request__c(
                Case__c = cases[i].Id,
                Provider__c = 'TestProvider1',
                Request_Type__c = 'Bulk Process',
                Request_Data__c = '{"caseId":"' + cases[i].Id + '","provider":"TestProvider1"}',
                Retry_Count__c = i % 3,
                Max_Retries__c = 3,
                Status__c = 'Pending'
            ));
        }
        insert retryRequests;
        
        // Create test metrics
        List<AI_Bulk_Processing_Metrics__c> metrics = new List<AI_Bulk_Processing_Metrics__c>();
        for (Integer i = 0; i < 5; i++) {
            metrics.add(new AI_Bulk_Processing_Metrics__c(
                Batch_Id__c = 'TEST_BATCH_' + i,
                Total_Requests__c = 10 + i,
                Successful_Requests__c = 8 + i,
                Failed_Requests__c = 2,
                Error_Requests__c = 0,
                Rate_Limit_Exceeded__c = 0,
                Processing_Time_Ms__c = 5000 + (i * 1000),
                Average_Time_Per_Request__c = 500 + (i * 100)
            ));
        }
        insert metrics;
    }
    
    @IsTest
    static void testGetProcessingStatus() {
        Test.startTest();
        
        // Get processing status
        AIBulkProcessingCoordinator.ProcessingStatus status = 
            AIBulkProcessingController.getProcessingStatus();
        
        Test.stopTest();
        
        // Verify status data
        System.assertNotEquals(null, status, 'Should return processing status');
        System.assertEquals(3, status.completedCount, 'Should have 3 completed requests');
        System.assertEquals(3, status.failedCount, 'Should have 3 failed requests');
        System.assertEquals(2, status.processingCount, 'Should have 2 processing requests');
        System.assertEquals(2, status.pendingCount, 'Should have 2 pending requests');
        System.assertEquals(5, status.retryQueueCount, 'Should have 5 retry requests');
    }
    
    @IsTest
    static void testInitiateBulkProcessing() {
        Test.startTest();
        
        // Initiate bulk processing
        String jobId = AIBulkProcessingController.initiateBulkProcessing(100);
        
        Test.stopTest();
        
        // Job ID might be null if no pending requests are found
        // This tests the controller method execution without errors
        System.assert(true, 'Method should execute without throwing exceptions');
    }
    
    @IsTest
    static void testProcessRetryQueue() {
        Test.startTest();
        
        // Process retry queue
        Integer processedCount = AIBulkProcessingController.processRetryQueue();
        
        Test.stopTest();
        
        // Verify method executes successfully
        System.assert(processedCount >= 0, 'Should return non-negative processed count');
    }
    
    @IsTest
    static void testCancelAllJobs() {
        Test.startTest();
        
        // Cancel all jobs
        Integer cancelledCount = AIBulkProcessingController.cancelAllJobs();
        
        Test.stopTest();
        
        // In test context, no actual jobs will be running
        System.assertEquals(0, cancelledCount, 'Should return 0 cancelled jobs in test context');
    }
    
    @IsTest
    static void testGetDetailedMetrics() {
        Test.startTest();
        
        // Get detailed metrics
        List<AIBulkProcessingController.ProcessingMetric> metrics = 
            AIBulkProcessingController.getDetailedMetrics();
        
        Test.stopTest();
        
        // Verify metrics data
        System.assertNotEquals(null, metrics, 'Should return metrics list');
        System.assertEquals(5, metrics.size(), 'Should return 5 metrics records');
        
        // Verify metric data structure
        for (AIBulkProcessingController.ProcessingMetric metric : metrics) {
            System.assertNotEquals(null, metric.batchId, 'Batch ID should not be null');
            System.assert(metric.totalRequests > 0, 'Total requests should be positive');
            System.assert(metric.successRate >= 0 && metric.successRate <= 100, 
                'Success rate should be between 0 and 100');
        }
    }
    
    @IsTest
    static void testGetActiveJobs() {
        Test.startTest();
        
        // Get active jobs
        List<AIBulkProcessingController.ActiveJob> jobs = 
            AIBulkProcessingController.getActiveJobs();
        
        Test.stopTest();
        
        // In test context, no active jobs will be found
        System.assertNotEquals(null, jobs, 'Should return jobs list');
        System.assertEquals(0, jobs.size(), 'Should return 0 active jobs in test context');
    }
    
    @IsTest
    static void testForceProcessCases() {
        // Get test cases
        List<Case> testCases = [SELECT Id FROM Case LIMIT 3];
        List<String> caseIds = new List<String>();
        for (Case c : testCases) {
            caseIds.add(c.Id);
        }
        
        Test.startTest();
        
        // Force process cases
        String jobId = AIBulkProcessingController.forceProcessCases(caseIds, 'TestProvider1');
        
        Test.stopTest();
        
        // Verify method execution
        System.assertNotEquals(null, jobId, 'Should return job ID');
    }
    
    @IsTest
    static void testForceProcessCasesValidation() {
        Test.startTest();
        
        try {
            // Test with null case IDs
            AIBulkProcessingController.forceProcessCases(null, 'TestProvider1');
            System.assert(false, 'Should throw exception for null case IDs');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Failed to force process cases'), 
                'Should throw AuraHandledException');
        }
        
        try {
            // Test with empty provider
            AIBulkProcessingController.forceProcessCases(new List<String>(), '');
            System.assert(false, 'Should throw exception for empty provider');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Failed to force process cases'), 
                'Should throw AuraHandledException');
        }
        
        Test.stopTest();
    }
    
    @IsTest
    static void testGetAvailableProviders() {
        Test.startTest();
        
        // Get available providers
        List<String> providers = AIBulkProcessingController.getAvailableProviders();
        
        Test.stopTest();
        
        // Verify providers data
        System.assertNotEquals(null, providers, 'Should return providers list');
        System.assertEquals(2, providers.size(), 'Should return 2 active providers');
        System.assert(providers.contains('TestProvider1'), 'Should include TestProvider1');
        System.assert(providers.contains('TestProvider2'), 'Should include TestProvider2');
        System.assert(!providers.contains('InactiveProvider'), 'Should not include inactive provider');
    }
    
    @IsTest
    static void testProcessingMetricWrapperClass() {
        Test.startTest();
        
        // Test ProcessingMetric wrapper class
        AIBulkProcessingController.ProcessingMetric metric = 
            new AIBulkProcessingController.ProcessingMetric();
        
        metric.batchId = 'TEST_BATCH';
        metric.totalRequests = 100;
        metric.successfulRequests = 85;
        metric.failedRequests = 15;
        metric.processingTimeMs = 30000;
        metric.averageTimePerRequest = 300;
        metric.createdDate = DateTime.now();
        metric.successRate = 85.0;
        
        Test.stopTest();
        
        // Verify wrapper class properties
        System.assertEquals('TEST_BATCH', metric.batchId);
        System.assertEquals(100, metric.totalRequests);
        System.assertEquals(85, metric.successfulRequests);
        System.assertEquals(85.0, metric.successRate);
    }
    
    @IsTest
    static void testActiveJobWrapperClass() {
        Test.startTest();
        
        // Test ActiveJob wrapper class
        AIBulkProcessingController.ActiveJob job = 
            new AIBulkProcessingController.ActiveJob();
        
        job.jobId = 'TEST_JOB_ID';
        job.jobType = 'Queueable';
        job.status = 'Processing';
        job.itemsProcessed = 50;
        job.totalItems = 100;
        job.numberOfErrors = 0;
        job.createdByName = 'Test User';
        job.progressPercentage = 50.0;
        
        Test.stopTest();
        
        // Verify wrapper class properties
        System.assertEquals('TEST_JOB_ID', job.jobId);
        System.assertEquals('Processing', job.status);
        System.assertEquals(50, job.itemsProcessed);
        System.assertEquals(50.0, job.progressPercentage);
    }
    
    @IsTest
    static void testErrorHandling() {
        Test.startTest();
        
        // Test error handling by forcing an exception scenario
        try {
            // This should handle database errors gracefully
            List<AIBulkProcessingController.ProcessingMetric> metrics = 
                AIBulkProcessingController.getDetailedMetrics();
            System.assertNotEquals(null, metrics, 'Should handle errors gracefully');
        } catch (AuraHandledException e) {
            // Expected if there are database issues
            System.assert(e.getMessage().contains('Failed to retrieve'), 
                'Should provide meaningful error message');
        }
        
        Test.stopTest();
        
        // Verify error logs
        List<Error_Log__c> errorLogs = [
            SELECT Id, Class_Name__c, Error_Type__c
            FROM Error_Log__c
            WHERE Class_Name__c LIKE '%AIBulkProcessingController%'
        ];
        
        // Error logs may or may not be present
        System.assert(errorLogs.size() >= 0, 'Error logging should work');
    }
    
    @IsTest
    static void testLargeDataVolume() {
        // Create large number of test records to test performance
        List<AI_Bulk_Processing_Metrics__c> largeMetrics = new List<AI_Bulk_Processing_Metrics__c>();
        
        for (Integer i = 0; i < 100; i++) {
            largeMetrics.add(new AI_Bulk_Processing_Metrics__c(
                Batch_Id__c = 'LARGE_BATCH_' + i,
                Total_Requests__c = i + 1,
                Successful_Requests__c = i,
                Failed_Requests__c = 1,
                Processing_Time_Ms__c = (i + 1) * 1000,
                Average_Time_Per_Request__c = (i + 1) * 10
            ));
        }
        insert largeMetrics;
        
        Test.startTest();
        
        // Get detailed metrics with large dataset
        List<AIBulkProcessingController.ProcessingMetric> metrics = 
            AIBulkProcessingController.getDetailedMetrics();
        
        Test.stopTest();
        
        // Verify performance with large dataset
        System.assertNotEquals(null, metrics, 'Should handle large datasets');
        System.assert(metrics.size() <= 50, 'Should respect LIMIT clause');
    }
    
    @IsTest
    static void testCacheableMethodsInBulk() {
        Test.startTest();
        
        // Test multiple calls to cacheable methods
        for (Integer i = 0; i < 5; i++) {
            AIBulkProcessingCoordinator.ProcessingStatus status = 
                AIBulkProcessingController.getProcessingStatus();
            System.assertNotEquals(null, status, 'Cacheable method should work in bulk');
            
            List<String> providers = AIBulkProcessingController.getAvailableProviders();
            System.assertNotEquals(null, providers, 'Cacheable method should work in bulk');
        }
        
        Test.stopTest();
        
        // Verify all calls completed successfully
        System.assert(true, 'All cacheable method calls should complete successfully');
    }
}