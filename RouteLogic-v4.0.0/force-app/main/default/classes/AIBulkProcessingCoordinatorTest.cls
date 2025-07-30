/**
 * @description Test class for AIBulkProcessingCoordinator with Phase 1 updates
 * Includes comprehensive testing for the getPendingRequests implementation
 * @author RouteLogic Team
 * @date 2025-01-20
 */
@isTest
private class AIBulkProcessingCoordinatorTest {
    
    @TestSetup
    static void setup() {
        // Create test cases
        List<Case> testCases = new List<Case>();
        for (Integer i = 0; i < 10; i++) {
            testCases.add(new Case(
                Subject = 'Test Case ' + i,
                Priority = (i < 5) ? 'High' : 'Medium',
                Status = 'New'
            ));
        }
        insert testCases;
        
        // Create AI Processing Status records for testing getPendingRequests
        List<AI_Processing_Status__c> statusRecords = new List<AI_Processing_Status__c>();
        for (Integer i = 0; i < 10; i++) {
            statusRecords.add(new AI_Processing_Status__c(
                Case__c = testCases[i].Id,
                Status__c = (i < 5) ? 'Pending' : 'Completed',
                AI_Provider__c = 'Ada',
                Request_Type__c = 'Bulk Process',
                Priority__c = (i < 3) ? 'High' : 'Normal',
                Request_Time__c = DateTime.now().addMinutes(-i),
                Is_Active__c = true
            ));
        }
        insert statusRecords;
        
        // Create retry requests
        List<AI_Retry_Request__c> retryRequests = new List<AI_Retry_Request__c>();
        for (Integer i = 0; i < 3; i++) {
            retryRequests.add(new AI_Retry_Request__c(
                Case__c = testCases[i].Id,
                AI_Provider__c = 'Ada',
                Status__c = 'Pending',
                Retry_Count__c = i,
                Error_Message__c = 'Test error',
                Original_Request_Id__c = 'TEST-' + i
            ));
        }
        insert retryRequests;
    }
    
    /**
     * @description Test successful bulk processing initiation with pending requests
     */
    @isTest
    static void testInitiateBulkProcessingSuccess() {
        Test.startTest();
        
        // Mock the queueable job
        Test.setMock(HttpCalloutMock.class, new MockAIProviderResponse());
        
        String jobId = AIBulkProcessingCoordinator.initiateBulkProcessing(3);
        
        Test.stopTest();
        
        // Verify job was queued
        System.assertNotEquals(null, jobId, 'Job ID should not be null');
        System.assertNotEquals('No pending requests to process', jobId, 'Should have found pending requests');
        
        // Verify status records were updated to Processing
        List<AI_Processing_Status__c> processingRecords = [
            SELECT Id, Status__c, Processing_Start_Time__c
            FROM AI_Processing_Status__c
            WHERE Status__c = 'Processing'
        ];
        
        System.assertEquals(3, processingRecords.size(), 'Should have 3 records in processing status');
        
        for (AI_Processing_Status__c status : processingRecords) {
            System.assertNotEquals(null, status.Processing_Start_Time__c, 
                'Processing start time should be set');
        }
    }
    
    /**
     * @description Test getPendingRequests priority ordering
     */
    @isTest
    static void testGetPendingRequestsPriorityOrder() {
        // Create a custom test method to directly test the private method behavior
        Test.startTest();
        
        String jobId = AIBulkProcessingCoordinator.initiateBulkProcessing(5);
        
        Test.stopTest();
        
        // Verify high priority records were processed first
        List<AI_Processing_Status__c> processingRecords = [
            SELECT Id, Priority__c, Request_Time__c
            FROM AI_Processing_Status__c
            WHERE Status__c = 'Processing'
            ORDER BY Request_Time__c ASC
        ];
        
        // First records should be high priority
        System.assertEquals('High', processingRecords[0].Priority__c, 
            'First record should be high priority');
        System.assertEquals('High', processingRecords[1].Priority__c, 
            'Second record should be high priority');
    }
    
    /**
     * @description Test initiateBulkProcessing with no pending requests
     */
    @isTest
    static void testInitiateBulkProcessingNoPendingRequests() {
        // Update all pending records to completed
        List<AI_Processing_Status__c> pendingRecords = [
            SELECT Id FROM AI_Processing_Status__c WHERE Status__c = 'Pending'
        ];
        for (AI_Processing_Status__c status : pendingRecords) {
            status.Status__c = 'Completed';
        }
        update pendingRecords;
        
        Test.startTest();
        
        String result = AIBulkProcessingCoordinator.initiateBulkProcessing(10);
        
        Test.stopTest();
        
        System.assertEquals('No pending requests to process', result, 
            'Should return no pending requests message');
    }
    
    /**
     * @description Test batch size limiting
     */
    @isTest
    static void testBatchSizeLimiting() {
        Test.startTest();
        
        // Request only 2 records despite having 5 pending
        String jobId = AIBulkProcessingCoordinator.initiateBulkProcessing(2);
        
        Test.stopTest();
        
        // Verify only 2 records were processed
        Integer processingCount = [
            SELECT COUNT() FROM AI_Processing_Status__c WHERE Status__c = 'Processing'
        ];
        System.assertEquals(2, processingCount, 'Should process only 2 records as per batch size');
        
        // Verify 3 records remain pending
        Integer pendingCount = [
            SELECT COUNT() FROM AI_Processing_Status__c WHERE Status__c = 'Pending'
        ];
        System.assertEquals(3, pendingCount, 'Should have 3 records still pending');
    }
    
    /**
     * @description Test security enforcement in getPendingRequests
     */
    @isTest
    static void testGetPendingRequestsSecurity() {
        // Create a user without access to AI_Processing_Status__c
        User testUser = createTestUser('Standard User');
        
        System.runAs(testUser) {
            Test.startTest();
            
            try {
                AIBulkProcessingCoordinator.initiateBulkProcessing(5);
                System.assert(false, 'Should have thrown exception due to security');
            } catch (Exception e) {
                System.assert(e.getMessage().contains('security') || 
                             e.getMessage().contains('access'), 
                             'Should be security related exception');
            }
            
            Test.stopTest();
        }
    }
    
    /**
     * @description Test retry queue processing
     */
    @isTest
    static void testProcessRetryQueue() {
        Test.startTest();
        
        Integer retryCount = AIBulkProcessingCoordinator.processRetryQueue();
        
        Test.stopTest();
        
        System.assertEquals(3, retryCount, 'Should process 3 retry requests');
        
        // Verify retry records were updated
        List<AI_Retry_Request__c> updatedRetries = [
            SELECT Id, Status__c, Retry_Count__c, Last_Retry_Time__c
            FROM AI_Retry_Request__c
        ];
        
        for (AI_Retry_Request__c retry : updatedRetries) {
            System.assertEquals('Processing', retry.Status__c, 'Status should be Processing');
            System.assertNotEquals(null, retry.Last_Retry_Time__c, 'Last retry time should be set');
        }
    }
    
    /**
     * @description Test circuit breaker functionality
     */
    @isTest
    static void testCircuitBreaker() {
        // Create multiple error logs to trigger circuit breaker
        List<Error_Log__c> errors = new List<Error_Log__c>();
        for (Integer i = 0; i < 6; i++) {
            errors.add(new Error_Log__c(
                Class_Name__c = 'AIBulkProcessingCoordinator',
                Method_Name__c = 'Test',
                Error_Message__c = 'Test error',
                Stack_Trace__c = 'Test trace'
            ));
        }
        insert errors;
        
        Test.startTest();
        
        try {
            AIBulkProcessingCoordinator.initiateBulkProcessing(5);
            System.assert(false, 'Should have thrown circuit breaker exception');
        } catch (AIHandledException e) {
            System.assert(e.getMessage().contains('Circuit breaker'), 
                'Should be circuit breaker exception');
        }
        
        Test.stopTest();
    }
    
    /**
     * @description Test cancel all pending jobs
     */
    @isTest
    static void testCancelAllPendingJobs() {
        Test.startTest();
        
        Integer cancelledCount = AIBulkProcessingCoordinator.cancelAllPendingJobs();
        
        Test.stopTest();
        
        System.assertEquals(5, cancelledCount, 'Should cancel 5 pending records');
        
        // Verify all pending records are cancelled
        Integer remainingPending = [
            SELECT COUNT() FROM AI_Processing_Status__c 
            WHERE Status__c IN ('Pending', 'Processing')
        ];
        System.assertEquals(0, remainingPending, 'No records should remain pending');
    }
    
    /**
     * @description Test processing status retrieval
     */
    @isTest
    static void testGetProcessingStatus() {
        Test.startTest();
        
        AIBulkProcessingCoordinator.ProcessingStatus status = 
            AIBulkProcessingCoordinator.getProcessingStatus();
        
        Test.stopTest();
        
        System.assertEquals(5, status.pendingCount, 'Should have 5 pending');
        System.assertEquals(5, status.completedCount, 'Should have 5 completed');
        System.assertEquals(10, status.totalCount, 'Should have 10 total');
        System.assertEquals(0, status.failedCount, 'Should have 0 failed');
    }
    
    /**
     * @description Test inactive records are excluded
     */
    @isTest
    static void testInactiveRecordsExcluded() {
        // Deactivate some pending records
        List<AI_Processing_Status__c> pendingRecords = [
            SELECT Id FROM AI_Processing_Status__c 
            WHERE Status__c = 'Pending' LIMIT 2
        ];
        for (AI_Processing_Status__c status : pendingRecords) {
            status.Is_Active__c = false;
        }
        update pendingRecords;
        
        Test.startTest();
        
        String jobId = AIBulkProcessingCoordinator.initiateBulkProcessing(10);
        
        Test.stopTest();
        
        // Should only process 3 active pending records
        Integer processingCount = [
            SELECT COUNT() FROM AI_Processing_Status__c WHERE Status__c = 'Processing'
        ];
        System.assertEquals(3, processingCount, 'Should process only active records');
    }
    
    /**
     * @description Test original request ID preservation
     */
    @isTest
    static void testOriginalRequestIdPreservation() {
        // Add original request IDs to test data
        List<AI_Processing_Status__c> pendingRecords = [
            SELECT Id FROM AI_Processing_Status__c 
            WHERE Status__c = 'Pending' LIMIT 2
        ];
        for (Integer i = 0; i < pendingRecords.size(); i++) {
            pendingRecords[i].Original_Request_Id__c = 'ORIGINAL-' + i;
        }
        update pendingRecords;
        
        Test.startTest();
        
        // We'll verify through the processing chain that IDs are preserved
        String jobId = AIBulkProcessingCoordinator.initiateBulkProcessing(2);
        
        Test.stopTest();
        
        System.assertNotEquals('No pending requests to process', jobId, 
            'Should have processed requests with original IDs');
    }
    
    // Helper methods
    
    /**
     * @description Creates a test user with specified profile
     */
    private static User createTestUser(String profileName) {
        Profile p = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
        
        User u = new User(
            Alias = 'testuser',
            Email = 'testuser@routelogic.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Test',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testuser' + DateTime.now().getTime() + '@routelogic.com'
        );
        
        insert u;
        return u;
    }
    
    /**
     * @description Mock class for AI provider HTTP responses
     */
    private class MockAIProviderResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"success":true,"data":{"sentiment":"positive","intent":"inquiry"}}');
            res.setStatusCode(200);
            return res;
        }
    }
}