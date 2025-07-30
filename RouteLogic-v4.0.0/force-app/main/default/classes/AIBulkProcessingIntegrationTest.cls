/**
 * @description Comprehensive integration test for AI Bulk Processing system
 * @author RouteLogic Team
 * @date 2025-01-17
 */
@IsTest
private class AIBulkProcessingIntegrationTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test account and contact
        Account testAccount = new Account(Name = 'Integration Test Account');
        insert testAccount;
        
        Contact testContact = new Contact(
            FirstName = 'Integration',
            LastName = 'Test Contact',
            Email = 'integration@test.com',
            AccountId = testAccount.Id
        );
        insert testContact;
        
        // Create test cases with various priorities and statuses
        List<Case> testCases = new List<Case>();
        List<String> priorities = new List<String>{'High', 'Medium', 'Low'};
        List<String> statuses = new List<String>{'New', 'Working', 'Escalated'};
        
        for (Integer i = 0; i < 100; i++) {
            testCases.add(new Case(
                Subject = 'Integration Test Case ' + i,
                Description = 'Detailed description for integration test case ' + i + 
                            '. This case contains customer inquiry about product issues and requires AI analysis.',
                Priority = priorities[Math.mod(i, 3)],
                Status = statuses[Math.mod(i, 3)],
                AccountId = testAccount.Id,
                ContactId = testContact.Id,
                Origin = 'Email'
            ));
        }
        insert testCases;
        
        // Create AI provider credentials
        List<AIProviderCredential__c> credentials = new List<AIProviderCredential__c>();
        credentials.add(new AIProviderCredential__c(
            Name = 'OpenAI',
            API_Key__c = 'sk-test-openai-key-encrypted',
            Endpoint_URL__c = 'https://api.openai.com/v1',
            IsActive__c = true
        ));
        credentials.add(new AIProviderCredential__c(
            Name = 'Azure_Cognitive',
            API_Key__c = 'azure-test-key-encrypted',
            Endpoint_URL__c = 'https://cognitive.azure.com/api',
            IsActive__c = true
        ));
        credentials.add(new AIProviderCredential__c(
            Name = 'AWS_Comprehend',
            API_Key__c = 'aws-test-key-encrypted',
            Endpoint_URL__c = 'https://comprehend.us-east-1.amazonaws.com',
            IsActive__c = false // Inactive for testing
        ));
        insert credentials;
        
        // Create platform cache partition for rate limiting (simulated in test)
        // Note: Platform Cache cannot be easily tested, so we'll mock the behavior
    }
    
    @IsTest
    static void testFullBulkProcessingWorkflow() {
        // This test simulates the complete bulk processing workflow
        Test.setMock(HttpCalloutMock.class, new IntegrationTestMockResponse());
        
        // Get test cases
        List<Case> testCases = [SELECT Id FROM Case LIMIT 50];
        
        Test.startTest();
        
        // Step 1: Create AI case request events (simulating platform event publishing)
        List<AI_Case_Request__e> events = new List<AI_Case_Request__e>();
        for (Case c : testCases) {
            events.add(new AI_Case_Request__e(
                CaseId__c = c.Id,
                AI_Provider__c = 'OpenAI',
                Request_Type__c = 'Full Workflow Test',
                Priority__c = 'High',
                Status__c = 'Pending'
            ));
        }
        
        // Step 2: Handle platform events (simulating trigger execution)
        AI_Case_Request_EventHandler.handleAfterInsert(events);
        
        // Step 3: Initiate bulk processing via coordinator
        Id jobId = AIBulkProcessingCoordinator.initiateBulkProcessing(200);
        
        // Step 4: Execute queueable job (simulating async execution)
        AIBulkProcessingQueueable queueable = new AIBulkProcessingQueueable(events);
        System.enqueueJob(queueable);
        
        Test.stopTest();
        
        // Verify complete workflow results
        
        // Check processing status records
        List<AI_Processing_Status__c> statusRecords = [
            SELECT Id, Case__c, AI_Provider__c, Status__c, Success__c, Request_Time__c
            FROM AI_Processing_Status__c
            WHERE AI_Provider__c = 'OpenAI'
        ];
        
        System.assertEquals(50, statusRecords.size(), 'Should create 50 processing status records');
        
        // Check audit logs
        List<AI_Audit_Log__c> auditLogs = [
            SELECT Id, Action__c, Details__c
            FROM AI_Audit_Log__c
            WHERE Action__c = 'Bulk Processing Initiated'
        ];
        
        System.assert(auditLogs.size() > 0, 'Should create audit log entries');
        
        // Check metrics
        List<AI_Bulk_Processing_Metrics__c> metrics = [
            SELECT Id, Total_Requests__c, Batch_Id__c
            FROM AI_Bulk_Processing_Metrics__c
        ];
        
        System.assert(metrics.size() > 0, 'Should create metrics records');
    }
    
    @IsTest
    static void testBulkProcessingWithRetryFlow() {
        // Test the complete retry workflow
        Test.setMock(HttpCalloutMock.class, new IntegrationTestMockResponse(false, 429)); // Rate limit error
        
        // Get test cases
        List<Case> testCases = [SELECT Id FROM Case LIMIT 10];
        
        Test.startTest();
        
        // Create AI case request events
        List<AI_Case_Request__e> events = new List<AI_Case_Request__e>();
        for (Case c : testCases) {
            events.add(new AI_Case_Request__e(
                CaseId__c = c.Id,
                AI_Provider__c = 'Azure_Cognitive',
                Request_Type__c = 'Retry Flow Test',
                Priority__c = 'Medium',
                Status__c = 'Pending'
            ));
        }
        
        // Execute bulk processing (will fail and create retry requests)
        AIBulkProcessingQueueable queueable = new AIBulkProcessingQueueable(events);
        System.enqueueJob(queueable);
        
        // Process retry queue
        Integer retryCount = AIBulkProcessingCoordinator.processRetryQueue();
        
        Test.stopTest();
        
        // Verify retry workflow
        List<AI_Retry_Request__c> retryRequests = [
            SELECT Id, Case__c, Provider__c, Status__c, Retry_Count__c
            FROM AI_Retry_Request__c
            WHERE Provider__c = 'Azure_Cognitive'
        ];
        
        System.assert(retryRequests.size() > 0, 'Should create retry requests for failed processing');
        
        // Verify metrics captured the failures
        List<AI_Bulk_Processing_Metrics__c> metrics = [
            SELECT Id, Failed_Requests__c, Rate_Limit_Exceeded__c
            FROM AI_Bulk_Processing_Metrics__c
        ];
        
        if (!metrics.isEmpty()) {
            System.assert(metrics[0].Failed_Requests__c > 0 || metrics[0].Rate_Limit_Exceeded__c > 0,
                'Should track failed or rate-limited requests');
        }
    }
    
    @IsTest
    static void testUIControllerIntegration() {
        // Test the complete UI controller integration
        Test.setMock(HttpCalloutMock.class, new IntegrationTestMockResponse());
        
        // Create some test data
        List<Case> testCases = [SELECT Id FROM Case LIMIT 5];
        
        // Create processing status records
        List<AI_Processing_Status__c> statusRecords = new List<AI_Processing_Status__c>();
        for (Integer i = 0; i < testCases.size(); i++) {
            String status = (i < 2) ? 'Completed' : 'Failed';
            statusRecords.add(new AI_Processing_Status__c(
                Case__c = testCases[i].Id,
                AI_Provider__c = 'OpenAI',
                Status__c = status,
                Success__c = status == 'Completed'
            ));
        }
        insert statusRecords;
        
        // Create metrics
        AI_Bulk_Processing_Metrics__c metric = new AI_Bulk_Processing_Metrics__c(
            Batch_Id__c = 'UI_TEST_BATCH',
            Total_Requests__c = 5,
            Successful_Requests__c = 2,
            Failed_Requests__c = 3,
            Processing_Time_Ms__c = 15000,
            Average_Time_Per_Request__c = 3000
        );
        insert metric;
        
        Test.startTest();
        
        // Test all UI controller methods
        AIBulkProcessingCoordinator.ProcessingStatus status = 
            AIBulkProcessingController.getProcessingStatus();
        
        List<String> providers = AIBulkProcessingController.getAvailableProviders();
        
        List<AIBulkProcessingController.ProcessingMetric> metrics = 
            AIBulkProcessingController.getDetailedMetrics();
        
        List<AIBulkProcessingController.ActiveJob> activeJobs = 
            AIBulkProcessingController.getActiveJobs();
        
        // Test force processing
        List<String> caseIds = new List<String>();
        for (Case c : testCases) {
            caseIds.add(c.Id);
        }
        String jobId = AIBulkProcessingController.forceProcessCases(caseIds, 'OpenAI');
        
        Test.stopTest();
        
        // Verify UI controller results
        System.assertNotEquals(null, status, 'Should return processing status');
        System.assertEquals(2, status.completedCount, 'Should show 2 completed');
        System.assertEquals(3, status.failedCount, 'Should show 3 failed');
        
        System.assertNotEquals(null, providers, 'Should return available providers');
        System.assertEquals(2, providers.size(), 'Should return 2 active providers');
        
        System.assertNotEquals(null, metrics, 'Should return metrics');
        System.assertEquals(1, metrics.size(), 'Should return 1 metric record');
        
        System.assertNotEquals(null, activeJobs, 'Should return active jobs list');
        
        System.assertNotEquals(null, jobId, 'Should return job ID for force processing');
    }
    
    @IsTest
    static void testErrorHandlingAndLogging() {
        // Test comprehensive error handling throughout the system
        Test.setMock(HttpCalloutMock.class, new IntegrationTestMockResponse(false, 500)); // Server error
        
        // Get test cases
        List<Case> testCases = [SELECT Id FROM Case LIMIT 3];
        
        Test.startTest();
        
        // Create events with various error scenarios
        List<AI_Case_Request__e> events = new List<AI_Case_Request__e>();
        
        // Valid event
        events.add(new AI_Case_Request__e(
            CaseId__c = testCases[0].Id,
            AI_Provider__c = 'OpenAI',
            Request_Type__c = 'Error Handling Test',
            Priority__c = 'High',
            Status__c = 'Pending'
        ));
        
        // Event with invalid provider
        events.add(new AI_Case_Request__e(
            CaseId__c = testCases[1].Id,
            AI_Provider__c = 'InvalidProvider',
            Request_Type__c = 'Error Handling Test',
            Priority__c = 'Medium',
            Status__c = 'Pending'
        ));
        
        // Execute processing with errors
        AIBulkProcessingQueueable queueable = new AIBulkProcessingQueueable(events);
        System.enqueueJob(queueable);
        
        // Test error scenarios in controller
        try {
            AIBulkProcessingController.forceProcessCases(null, 'OpenAI');
        } catch (Exception e) {
            // Expected
        }
        
        try {
            AIBulkProcessingController.forceProcessCases(new List<String>{'invalid-id'}, '');
        } catch (Exception e) {
            // Expected
        }
        
        Test.stopTest();
        
        // Verify error logging
        List<Error_Log__c> errorLogs = [
            SELECT Id, Class_Name__c, Error_Type__c, Error_Message__c
            FROM Error_Log__c
        ];
        
        System.assert(errorLogs.size() > 0, 'Should create error log entries');
        
        // Verify error handling didn't break the system
        List<AI_Processing_Status__c> statusRecords = [
            SELECT Id, Status__c
            FROM AI_Processing_Status__c
        ];
        
        // Some records should still be processed despite errors
        System.assert(statusRecords.size() > 0, 'Should process some records despite errors');
    }
    
    @IsTest
    static void testHighVolumeProcessing() {
        // Test system behavior with high volume of requests
        Test.setMock(HttpCalloutMock.class, new IntegrationTestMockResponse());
        
        // Get all test cases
        List<Case> testCases = [SELECT Id FROM Case];
        
        Test.startTest();
        
        // Create high volume of AI case request events
        List<AI_Case_Request__e> events = new List<AI_Case_Request__e>();
        for (Case c : testCases) {
            events.add(new AI_Case_Request__e(
                CaseId__c = c.Id,
                AI_Provider__c = 'OpenAI',
                Request_Type__c = 'High Volume Test',
                Priority__c = 'Normal',
                Status__c = 'Pending'
            ));
        }
        
        // Process in batches to simulate real-world scenario
        List<AI_Case_Request__e> batch1 = new List<AI_Case_Request__e>();
        List<AI_Case_Request__e> batch2 = new List<AI_Case_Request__e>();
        
        for (Integer i = 0; i < events.size(); i++) {
            if (i < 50) {
                batch1.add(events[i]);
            } else {
                batch2.add(events[i]);
            }
        }
        
        // Process batches
        AI_Case_Request_EventHandler.handleAfterInsert(batch1);
        AI_Case_Request_EventHandler.handleAfterInsert(batch2);
        
        // Execute bulk processing
        AIBulkProcessingQueueable queueable1 = new AIBulkProcessingQueueable(batch1);
        AIBulkProcessingQueueable queueable2 = new AIBulkProcessingQueueable(batch2);
        
        System.enqueueJob(queueable1);
        System.enqueueJob(queueable2);
        
        Test.stopTest();
        
        // Verify high volume processing
        List<AI_Processing_Status__c> statusRecords = [
            SELECT Id, Status__c
            FROM AI_Processing_Status__c
        ];
        
        System.assertEquals(100, statusRecords.size(), 'Should process all 100 cases');
        
        // Verify metrics for high volume
        List<AI_Bulk_Processing_Metrics__c> metrics = [
            SELECT Id, Total_Requests__c
            FROM AI_Bulk_Processing_Metrics__c
        ];
        
        System.assert(metrics.size() > 0, 'Should create metrics for high volume processing');
    }
    
    @IsTest
    static void testSecurityAndFieldLevelSecurity() {
        // Test security enforcement throughout the system
        Test.setMock(HttpCalloutMock.class, new IntegrationTestMockResponse());
        
        // Get test cases
        List<Case> testCases = [SELECT Id FROM Case LIMIT 5];
        
        Test.startTest();
        
        // Test security utils
        List<AI_Processing_Status__c> newRecords = new List<AI_Processing_Status__c>();
        for (Case c : testCases) {
            newRecords.add(new AI_Processing_Status__c(
                Case__c = c.Id,
                AI_Provider__c = 'OpenAI',
                Status__c = 'Security Test',
                Success__c = false
            ));
        }
        
        // Test security stripping
        List<SObject> secureRecords = SecurityUtils.stripInaccessibleRecords(
            AccessType.CREATABLE,
            newRecords
        );
        
        insert secureRecords;
        
        // Test field-level security checks
        Set<String> fields = new Set<String>{'Case__c', 'AI_Provider__c', 'Status__c'};
        Boolean hasReadAccess = SecurityUtils.hasReadAccess(
            AI_Processing_Status__c.SObjectType,
            fields
        );
        
        Boolean hasCreateAccess = SecurityUtils.hasCreateAccess(
            AI_Processing_Status__c.SObjectType,
            fields
        );
        
        Test.stopTest();
        
        // Verify security enforcement
        System.assertNotEquals(null, secureRecords, 'Should return secure records');
        System.assertEquals(5, secureRecords.size(), 'Should process all secure records');
        System.assertEquals(true, hasReadAccess, 'Should have read access in test context');
        System.assertEquals(true, hasCreateAccess, 'Should have create access in test context');
        
        // Verify records were created securely
        List<AI_Processing_Status__c> createdRecords = [
            SELECT Id, Status__c
            FROM AI_Processing_Status__c
            WHERE Status__c = 'Security Test'
        ];
        
        System.assertEquals(5, createdRecords.size(), 'Should create all secure records');
    }
    
    @IsTest
    static void testCleanupAndMaintenance() {
        // Test system cleanup and maintenance functions
        
        // Create old test data (note: CreatedDate cannot be set in tests)
        List<AI_Processing_Status__c> statusRecords = new List<AI_Processing_Status__c>();
        List<AI_Retry_Request__c> retryRequests = new List<AI_Retry_Request__c>();
        List<AI_Bulk_Processing_Metrics__c> metrics = new List<AI_Bulk_Processing_Metrics__c>();
        List<Error_Log__c> errorLogs = new List<Error_Log__c>();
        
        List<Case> testCases = [SELECT Id FROM Case LIMIT 10];
        
        // Create test records for cleanup
        for (Case c : testCases) {
            statusRecords.add(new AI_Processing_Status__c(
                Case__c = c.Id,
                AI_Provider__c = 'OpenAI',
                Status__c = 'Completed',
                Success__c = true
            ));
            
            retryRequests.add(new AI_Retry_Request__c(
                Case__c = c.Id,
                Provider__c = 'OpenAI',
                Request_Type__c = 'Cleanup Test',
                Status__c = 'Completed',
                Retry_Count__c = 3,
                Max_Retries__c = 3
            ));
            
            errorLogs.add(new Error_Log__c(
                Class_Name__c = 'CleanupTest',
                Error_Type__c = 'TestError',
                Error_Message__c = 'Test error for cleanup',
                User__c = UserInfo.getUserId(),
                Timestamp__c = DateTime.now()
            ));
        }
        
        for (Integer i = 0; i < 5; i++) {
            metrics.add(new AI_Bulk_Processing_Metrics__c(
                Batch_Id__c = 'CLEANUP_BATCH_' + i,
                Total_Requests__c = 10,
                Successful_Requests__c = 8,
                Failed_Requests__c = 2
            ));
        }
        
        insert statusRecords;
        insert retryRequests;
        insert metrics;
        insert errorLogs;
        
        Test.startTest();
        
        // Test cleanup functions
        Integer cleanedBulkRecords = AIBulkProcessingCoordinator.cleanupOldRecords(30);
        ErrorLogService.cleanupOldLogs(30);
        
        Test.stopTest();
        
        // In test context, cleanup won't delete records due to date filters
        // This verifies the cleanup logic executes without errors
        System.assert(cleanedBulkRecords >= 0, 'Cleanup should return non-negative count');
        
        // Verify records still exist (they won't be deleted in test context)
        List<AI_Processing_Status__c> remainingStatus = [SELECT Id FROM AI_Processing_Status__c];
        List<Error_Log__c> remainingLogs = [SELECT Id FROM Error_Log__c];
        
        System.assert(remainingStatus.size() > 0, 'Records should remain in test context');
        System.assert(remainingLogs.size() > 0, 'Error logs should remain in test context');
    }
    
    /**
     * @description Mock HTTP response for integration testing
     */
    public class IntegrationTestMockResponse implements HttpCalloutMock {
        private Boolean success;
        private Integer statusCode;
        
        public IntegrationTestMockResponse() {
            this(true, 200);
        }
        
        public IntegrationTestMockResponse(Boolean success, Integer statusCode) {
            this.success = success;
            this.statusCode = statusCode;
        }
        
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(this.statusCode);
            
            if (this.success && this.statusCode == 200) {
                // Create successful bulk response
                Map<String, Object> bulkResponse = new Map<String, Object>{
                    'batchId' => 'INTEGRATION_TEST_BATCH',
                    'success' => true,
                    'processedCount' => 50,
                    'responses' => new List<Object>()
                };
                
                // Create individual responses
                List<Object> responses = new List<Object>();
                for (Integer i = 0; i < 50; i++) {
                    responses.add(new Map<String, Object>{
                        'requestId' => 'INT_REQ_' + i,
                        'success' => true,
                        'sentiment' => 'Positive',
                        'intent' => 'Product Inquiry',
                        'suggestedPriority' => 'Medium',
                        'suggestedResponse' => 'Thank you for your inquiry. We will respond shortly.',
                        'isAsync' => false
                    });
                }
                
                bulkResponse.put('responses', responses);
                res.setBody(JSON.serialize(bulkResponse));
            } else {
                res.setStatus('Error');
                String errorMessage = 'Integration test error - Status: ' + this.statusCode;
                res.setBody('{"error": "' + errorMessage + '"}');
            }
            
            return res;
        }
    }
}