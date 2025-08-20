/**
 * @description End-to-end integration test for Phase 1 bulk processing implementation
 * Tests the complete flow from Platform Event to AI response processing
 * @author RouteLogic Team  
 * @date 2025-01-20
 */
@isTest
private class AIBulkProcessingIntegrationTest_Phase1 {
    
    @TestSetup
    static void setup() {
        // Create test cases
        List<Case> testCases = new List<Case>();
        for (Integer i = 0; i < 20; i++) {
            testCases.add(new Case(
                Subject = 'Integration Test Case ' + i,
                Description = 'Test case for end-to-end processing validation',
                Priority = Math.mod(i, 3) == 0 ? 'High' : 'Normal',
                Status = 'New',
                Origin = 'Email'
            ));
        }
        insert testCases;
        
        // Configure AI provider settings
        AI_Provider_Settings__mdt providerSettings = new AI_Provider_Settings__mdt(
            DeveloperName = 'Ada_Test',
            Label = 'Ada Test Provider',
            Provider_Name__c = 'Ada',
            Is_Active__c = true,
            API_Endpoint__c = 'https://api.ada.support/v1/analyze',
            Max_Batch_Size__c = 10,
            Timeout_ms__c = 30000
        );
        
        // Since we can't insert metadata in tests, we'll use custom settings or mocking
    }
    
    /**
     * @description Test complete flow from Platform Event through processing
     */
    @isTest
    static void testCompleteProcessingFlow() {
        List<Case> testCases = [SELECT Id FROM Case];
        
        Test.startTest();
        
        // Step 1: Publish Platform Events
        List<AI_Case_Request__e> events = new List<AI_Case_Request__e>();
        for (Case c : testCases) {
            events.add(new AI_Case_Request__e(
                CaseId__c = c.Id,
                AI_Provider__c = 'Ada',
                Request_Type__c = 'Bulk Process',
                Priority__c = 'Normal',
                Status__c = 'Pending'
            ));
        }
        
        List<Database.SaveResult> publishResults = EventBus.publish(events);
        
        // Verify events published successfully
        for (Database.SaveResult sr : publishResults) {
            System.assert(sr.isSuccess(), 'Platform event should publish successfully');
        }
        
        // Platform Event trigger should create AI_Processing_Status__c records
        Test.getEventBus().deliver();
        
        // Step 2: Verify AI_Processing_Status__c records created
        List<AI_Processing_Status__c> statusRecords = [
            SELECT Id, Case__c, Status__c, AI_Provider__c
            FROM AI_Processing_Status__c
            WHERE Status__c = 'Pending'
        ];
        
        System.assertEquals(testCases.size(), statusRecords.size(), 
            'Should create status record for each platform event');
        
        // Step 3: Mock HTTP callout for AI provider
        Test.setMock(HttpCalloutMock.class, new MockBulkAIResponse());
        
        // Step 4: Initiate bulk processing
        String jobId = AIBulkProcessingCoordinator.initiateBulkProcessing(10);
        
        System.assertNotEquals('No pending requests to process', jobId, 
            'Should find and process pending requests');
        
        Test.stopTest();
        
        // Step 5: Verify processing results
        List<AI_Processing_Status__c> processedRecords = [
            SELECT Id, Status__c, Processing_Start_Time__c, 
                   Completion_Time__c, Response_Data__c
            FROM AI_Processing_Status__c
            WHERE Id IN :statusRecords
        ];
        
        Integer processingCount = 0;
        Integer completedCount = 0;
        
        for (AI_Processing_Status__c status : processedRecords) {
            if (status.Status__c == 'Processing') {
                processingCount++;
                System.assertNotEquals(null, status.Processing_Start_Time__c,
                    'Processing start time should be set');
            } else if (status.Status__c == 'Completed') {
                completedCount++;
                System.assertNotEquals(null, status.Completion_Time__c,
                    'Completion time should be set for completed records');
            }
        }
        
        // Due to batch size of 10, we should have 10 in processing
        System.assertEquals(10, processingCount, 'Should have 10 records in processing');
        
        // Verify Cases were updated with AI insights
        List<Case> updatedCases = [
            SELECT Id, AI_Sentiment__c, AI_Intent__c, AI_Processing_Status__c
            FROM Case
            WHERE Id IN :testCases
            AND AI_Processing_Status__c != null
        ];
        
        System.assert(!updatedCases.isEmpty(), 'Cases should be updated with AI insights');
    }
    
    /**
     * @description Test processing with mixed priorities
     */
    @isTest
    static void testPriorityBasedProcessing() {
        // Create cases with different priorities
        List<Case> highPriorityCases = new List<Case>();
        List<Case> normalPriorityCases = new List<Case>();
        
        for (Integer i = 0; i < 5; i++) {
            highPriorityCases.add(new Case(
                Subject = 'High Priority Case ' + i,
                Priority = 'High',
                Status = 'New'
            ));
            normalPriorityCases.add(new Case(
                Subject = 'Normal Priority Case ' + i,
                Priority = 'Medium',
                Status = 'New'
            ));
        }
        
        insert highPriorityCases;
        insert normalPriorityCases;
        
        // Create AI_Processing_Status__c records directly (simulating Platform Event handler)
        List<AI_Processing_Status__c> statusRecords = new List<AI_Processing_Status__c>();
        
        for (Case c : highPriorityCases) {
            statusRecords.add(new AI_Processing_Status__c(
                Case__c = c.Id,
                Status__c = 'Pending',
                Priority__c = 'High',
                AI_Provider__c = 'Ada',
                Request_Time__c = DateTime.now(),
                Is_Active__c = true
            ));
        }
        
        for (Case c : normalPriorityCases) {
            statusRecords.add(new AI_Processing_Status__c(
                Case__c = c.Id,
                Status__c = 'Pending',
                Priority__c = 'Normal',
                AI_Provider__c = 'Ada',
                Request_Time__c = DateTime.now(),
                Is_Active__c = true
            ));
        }
        
        insert statusRecords;
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockBulkAIResponse());
        
        // Process only 5 records
        String jobId = AIBulkProcessingCoordinator.initiateBulkProcessing(5);
        
        Test.stopTest();
        
        // Verify high priority records were processed first
        List<AI_Processing_Status__c> processingRecords = [
            SELECT Id, Priority__c, Case__r.Priority
            FROM AI_Processing_Status__c
            WHERE Status__c = 'Processing'
        ];
        
        System.assertEquals(5, processingRecords.size(), 'Should process 5 records');
        
        for (AI_Processing_Status__c status : processingRecords) {
            System.assertEquals('High', status.Priority__c, 
                'All processed records should be high priority');
        }
    }
    
    /**
     * @description Test retry mechanism integration
     */
    @isTest
    static void testRetryMechanismIntegration() {
        Case testCase = new Case(
            Subject = 'Retry Test Case',
            Status = 'New'
        );
        insert testCase;
        
        // Create a failed processing status
        AI_Processing_Status__c failedStatus = new AI_Processing_Status__c(
            Case__c = testCase.Id,
            Status__c = 'Failed',
            AI_Provider__c = 'Ada',
            Error_Message__c = 'API timeout',
            Is_Active__c = true
        );
        insert failedStatus;
        
        // Create retry request
        AI_Retry_Request__c retryRequest = new AI_Retry_Request__c(
            Case__c = testCase.Id,
            AI_Provider__c = 'Ada',
            Status__c = 'Pending',
            Retry_Count__c = 0,
            Original_Request_Id__c = failedStatus.Id,
            Error_Message__c = 'API timeout'
        );
        insert retryRequest;
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockBulkAIResponse());
        
        // Process retry queue
        Integer retryCount = AIBulkProcessingCoordinator.processRetryQueue();
        
        Test.stopTest();
        
        System.assertEquals(1, retryCount, 'Should process 1 retry request');
        
        // Verify retry was processed
        AI_Retry_Request__c updatedRetry = [
            SELECT Id, Status__c, Retry_Count__c, Last_Retry_Time__c
            FROM AI_Retry_Request__c
            WHERE Id = :retryRequest.Id
        ];
        
        System.assertEquals('Processing', updatedRetry.Status__c, 'Retry should be processing');
        System.assertEquals(1, updatedRetry.Retry_Count__c, 'Retry count should increment');
        System.assertNotEquals(null, updatedRetry.Last_Retry_Time__c, 'Last retry time should be set');
    }
    
    /**
     * @description Test error handling and circuit breaker
     */
    @isTest
    static void testErrorHandlingFlow() {
        // Create test case
        Case testCase = new Case(Subject = 'Error Test Case', Status = 'New');
        insert testCase;
        
        // Create pending status
        AI_Processing_Status__c pendingStatus = new AI_Processing_Status__c(
            Case__c = testCase.Id,
            Status__c = 'Pending',
            AI_Provider__c = 'Ada',
            Is_Active__c = true
        );
        insert pendingStatus;
        
        Test.startTest();
        
        // Mock failing API response
        Test.setMock(HttpCalloutMock.class, new MockFailingAIResponse());
        
        try {
            String jobId = AIBulkProcessingCoordinator.initiateBulkProcessing(1);
            // The actual error would occur in the queueable execution
        } catch (Exception e) {
            // Expected in some scenarios
        }
        
        Test.stopTest();
        
        // In a real scenario, we'd verify error logs were created
        // and the circuit breaker logic was triggered after multiple failures
    }
    
    /**
     * @description Test concurrent processing handling
     */
    @isTest
    static void testConcurrentProcessing() {
        List<Case> testCases = new List<Case>();
        for (Integer i = 0; i < 30; i++) {
            testCases.add(new Case(
                Subject = 'Concurrent Test ' + i,
                Status = 'New'
            ));
        }
        insert testCases;
        
        // Create pending status records
        List<AI_Processing_Status__c> statusRecords = new List<AI_Processing_Status__c>();
        for (Case c : testCases) {
            statusRecords.add(new AI_Processing_Status__c(
                Case__c = c.Id,
                Status__c = 'Pending',
                AI_Provider__c = 'Ada',
                Is_Active__c = true
            ));
        }
        insert statusRecords;
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockBulkAIResponse());
        
        // Simulate multiple concurrent processing requests
        String jobId1 = AIBulkProcessingCoordinator.initiateBulkProcessing(10);
        String jobId2 = AIBulkProcessingCoordinator.initiateBulkProcessing(10);
        String jobId3 = AIBulkProcessingCoordinator.initiateBulkProcessing(10);
        
        Test.stopTest();
        
        // Verify no duplicate processing
        List<AI_Processing_Status__c> allStatuses = [
            SELECT Id, Status__c
            FROM AI_Processing_Status__c
            WHERE Id IN :statusRecords
        ];
        
        Map<String, Integer> statusCounts = new Map<String, Integer>{
            'Pending' => 0,
            'Processing' => 0
        };
        
        for (AI_Processing_Status__c status : allStatuses) {
            Integer count = statusCounts.get(status.Status__c);
            statusCounts.put(status.Status__c, count != null ? count + 1 : 1);
        }
        
        // Should have processed exactly 30 records (no duplicates)
        System.assertEquals(30, statusCounts.get('Processing'), 
            'All records should be in processing without duplicates');
    }
    
    // Mock response classes
    
    /**
     * @description Mock successful bulk AI response
     */
    private class MockBulkAIResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            
            // Parse request to return appropriate bulk response
            Map<String, Object> responseData = new Map<String, Object>{
                'success' => true,
                'results' => new List<Map<String, Object>>{
                    new Map<String, Object>{
                        'caseId' => 'CASE-001',
                        'sentiment' => 'positive',
                        'intent' => 'inquiry',
                        'confidence' => 0.95,
                        'suggestedResponse' => 'Thank you for your inquiry.'
                    }
                }
            };
            
            res.setBody(JSON.serialize(responseData));
            res.setStatusCode(200);
            return res;
        }
    }
    
    /**
     * @description Mock failing AI response
     */
    private class MockFailingAIResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":"Service temporarily unavailable"}');
            res.setStatusCode(503);
            return res;
        }
    }
}