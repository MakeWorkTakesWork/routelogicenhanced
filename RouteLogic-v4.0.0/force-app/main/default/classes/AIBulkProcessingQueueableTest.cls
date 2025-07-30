/**
 * @description Test class for AIBulkProcessingQueueable
 * @author RouteLogic Team
 * @date 2025-01-17
 */
@IsTest
private class AIBulkProcessingQueueableTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test accounts and contacts
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
        AIProviderCredential__c credential = new AIProviderCredential__c(
            Name = 'TestProvider',
            API_Key__c = 'test-api-key-encrypted',
            Endpoint_URL__c = 'https://api.testprovider.com',
            IsActive__c = true
        );
        insert credential;
    }
    
    @IsTest
    static void testBulkProcessingSuccess() {
        // Get test data
        List<Case> testCases = [SELECT Id FROM Case LIMIT 5];
        
        // Create AI case request events
        List<AI_Case_Request__e> requests = new List<AI_Case_Request__e>();
        for (Case c : testCases) {
            requests.add(new AI_Case_Request__e(
                CaseId__c = c.Id,
                AI_Provider__c = 'TestProvider',
                Request_Type__c = 'Bulk Process',
                Priority__c = 'Normal',
                Status__c = 'Pending'
            ));
        }
        
        // Mock HTTP response
        Test.setMock(HttpCalloutMock.class, new AIBulkProcessingMockResponse(true));
        
        Test.startTest();
        
        // Execute queueable
        AIBulkProcessingQueueable queueable = new AIBulkProcessingQueueable(requests);
        System.enqueueJob(queueable);
        
        Test.stopTest();
        
        // Verify processing status records were created
        List<AI_Processing_Status__c> statusRecords = [
            SELECT Id, Case__c, AI_Provider__c, Status__c, Success__c
            FROM AI_Processing_Status__c
        ];
        
        System.assertEquals(5, statusRecords.size(), 'Should create 5 processing status records');
        
        // Verify metrics record was created
        List<AI_Bulk_Processing_Metrics__c> metrics = [
            SELECT Id, Total_Requests__c, Successful_Requests__c
            FROM AI_Bulk_Processing_Metrics__c
        ];
        
        System.assertEquals(1, metrics.size(), 'Should create 1 metrics record');
        System.assertEquals(5, metrics[0].Total_Requests__c, 'Should track 5 total requests');
    }
    
    @IsTest
    static void testBulkProcessingWithRetries() {
        // Get test data
        List<Case> testCases = [SELECT Id FROM Case LIMIT 3];
        
        // Create AI case request events
        List<AI_Case_Request__e> requests = new List<AI_Case_Request__e>();
        for (Case c : testCases) {
            requests.add(new AI_Case_Request__e(
                CaseId__c = c.Id,
                AI_Provider__c = 'TestProvider',
                Request_Type__c = 'Bulk Process',
                Priority__c = 'High',
                Status__c = 'Pending'
            ));
        }
        
        // Mock HTTP response with retryable error
        Test.setMock(HttpCalloutMock.class, new AIBulkProcessingMockResponse(false, 429));
        
        Test.startTest();
        
        // Execute queueable
        AIBulkProcessingQueueable queueable = new AIBulkProcessingQueueable(requests);
        System.enqueueJob(queueable);
        
        Test.stopTest();
        
        // Verify retry requests were created
        List<AI_Retry_Request__c> retryRequests = [
            SELECT Id, Case__c, Provider__c, Status__c, Retry_Count__c
            FROM AI_Retry_Request__c
        ];
        
        System.assertEquals(3, retryRequests.size(), 'Should create 3 retry requests');
        
        for (AI_Retry_Request__c retry : retryRequests) {
            System.assertEquals('Pending', retry.Status__c, 'Retry status should be Pending');
            System.assertEquals(0, retry.Retry_Count__c, 'Initial retry count should be 0');
        }
    }
    
    @IsTest
    static void testBulkProcessingWithNonRetryableError() {
        // Get test data
        List<Case> testCases = [SELECT Id FROM Case LIMIT 2];
        
        // Create AI case request events
        List<AI_Case_Request__e> requests = new List<AI_Case_Request__e>();
        for (Case c : testCases) {
            requests.add(new AI_Case_Request__e(
                CaseId__c = c.Id,
                AI_Provider__c = 'TestProvider',
                Request_Type__c = 'Bulk Process',
                Priority__c = 'Low',
                Status__c = 'Pending'
            ));
        }
        
        // Mock HTTP response with non-retryable error
        Test.setMock(HttpCalloutMock.class, new AIBulkProcessingMockResponse(false, 400));
        
        Test.startTest();
        
        // Execute queueable
        AIBulkProcessingQueueable queueable = new AIBulkProcessingQueueable(requests);
        System.enqueueJob(queueable);
        
        Test.stopTest();
        
        // Verify failed status records were created
        List<AI_Processing_Status__c> statusRecords = [
            SELECT Id, Case__c, Status__c, Success__c
            FROM AI_Processing_Status__c
            WHERE Status__c = 'Failed'
        ];
        
        System.assertEquals(2, statusRecords.size(), 'Should create 2 failed status records');
        
        // Verify no retry requests were created for non-retryable errors
        List<AI_Retry_Request__c> retryRequests = [SELECT Id FROM AI_Retry_Request__c];
        System.assertEquals(0, retryRequests.size(), 'Should not create retry requests for non-retryable errors');
    }
    
    @IsTest
    static void testBulkProcessingWithMixedResults() {
        // Get test data
        List<Case> testCases = [SELECT Id FROM Case LIMIT 4];
        
        // Create AI case request events
        List<AI_Case_Request__e> requests = new List<AI_Case_Request__e>();
        for (Case c : testCases) {
            requests.add(new AI_Case_Request__e(
                CaseId__c = c.Id,
                AI_Provider__c = 'TestProvider',
                Request_Type__c = 'Bulk Process',
                Priority__c = 'Normal',
                Status__c = 'Pending'
            ));
        }
        
        // Mock HTTP response with mixed results
        Test.setMock(HttpCalloutMock.class, new AIBulkProcessingMockResponse(true, 200, true));
        
        Test.startTest();
        
        // Execute queueable
        AIBulkProcessingQueueable queueable = new AIBulkProcessingQueueable(requests);
        System.enqueueJob(queueable);
        
        Test.stopTest();
        
        // Verify processing status records
        List<AI_Processing_Status__c> statusRecords = [
            SELECT Id, Status__c, Success__c
            FROM AI_Processing_Status__c
        ];
        
        System.assertEquals(4, statusRecords.size(), 'Should create 4 status records');
        
        // Verify metrics record
        List<AI_Bulk_Processing_Metrics__c> metrics = [
            SELECT Id, Total_Requests__c, Successful_Requests__c, Failed_Requests__c
            FROM AI_Bulk_Processing_Metrics__c
        ];
        
        System.assertEquals(1, metrics.size(), 'Should create 1 metrics record');
        System.assertEquals(4, metrics[0].Total_Requests__c, 'Should track total requests');
    }
    
    @IsTest
    static void testEmptyRequestList() {
        Test.startTest();
        
        // Execute queueable with empty list
        AIBulkProcessingQueueable queueable = new AIBulkProcessingQueueable(new List<AI_Case_Request__e>());
        System.enqueueJob(queueable);
        
        Test.stopTest();
        
        // Verify no records were created
        List<AI_Processing_Status__c> statusRecords = [SELECT Id FROM AI_Processing_Status__c];
        System.assertEquals(0, statusRecords.size(), 'Should not create any status records for empty list');
    }
    
    @IsTest
    static void testExceptionHandling() {
        // Get test data
        List<Case> testCases = [SELECT Id FROM Case LIMIT 2];
        
        // Create AI case request events with invalid data
        List<AI_Case_Request__e> requests = new List<AI_Case_Request__e>();
        for (Case c : testCases) {
            requests.add(new AI_Case_Request__e(
                CaseId__c = c.Id,
                AI_Provider__c = 'InvalidProvider', // This will cause an exception
                Request_Type__c = 'Bulk Process',
                Priority__c = 'Normal',
                Status__c = 'Pending'
            ));
        }
        
        Test.startTest();
        
        // Execute queueable - should handle exception gracefully
        AIBulkProcessingQueueable queueable = new AIBulkProcessingQueueable(requests);
        System.enqueueJob(queueable);
        
        Test.stopTest();
        
        // Verify error logging
        List<Error_Log__c> errorLogs = [
            SELECT Id, Class_Name__c, Error_Type__c
            FROM Error_Log__c
            WHERE Class_Name__c LIKE '%AIBulkProcessingQueueable%'
        ];
        
        System.assert(errorLogs.size() > 0, 'Should create error log entries for exceptions');
    }
    
    /**
     * @description Mock HTTP response class for testing
     */
    public class AIBulkProcessingMockResponse implements HttpCalloutMock {
        private Boolean success;
        private Integer statusCode;
        private Boolean mixedResults;
        
        public AIBulkProcessingMockResponse(Boolean success) {
            this(success, success ? 200 : 500, false);
        }
        
        public AIBulkProcessingMockResponse(Boolean success, Integer statusCode) {
            this(success, statusCode, false);
        }
        
        public AIBulkProcessingMockResponse(Boolean success, Integer statusCode, Boolean mixedResults) {
            this.success = success;
            this.statusCode = statusCode;
            this.mixedResults = mixedResults;
        }
        
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(this.statusCode);
            
            if (this.success) {
                // Create mock bulk response
                Map<String, Object> bulkResponse = new Map<String, Object>{
                    'batchId' => 'TEST_BATCH_123',
                    'success' => true,
                    'processedCount' => 4,
                    'responses' => new List<Object>()
                };
                
                // Create individual responses
                List<Object> responses = new List<Object>();
                for (Integer i = 0; i < 4; i++) {
                    Map<String, Object> singleResponse = new Map<String, Object>{
                        'requestId' => 'REQ_' + i,
                        'success' => mixedResults ? (Math.mod(i, 2) == 0) : true,
                        'sentiment' => 'Neutral',
                        'intent' => 'Support Request',
                        'suggestedPriority' => 'Medium',
                        'suggestedResponse' => 'Thank you for contacting us.',
                        'isAsync' => false
                    };
                    
                    if (mixedResults && Math.mod(i, 2) != 0) {
                        singleResponse.put('errorMessage', 'Test error for mixed results');
                        singleResponse.put('retryable', true);
                    }
                    
                    responses.add(singleResponse);
                }
                
                bulkResponse.put('responses', responses);
                res.setBody(JSON.serialize(bulkResponse));
            } else {
                res.setStatus('Error');
                res.setBody('{"error": "Test error response"}');
            }
            
            return res;
        }
    }
}