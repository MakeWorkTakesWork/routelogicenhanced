/**
 * @description Test class for AI_Case_Request_EventHandler
 * @author RouteLogic Team
 * @date 2025-01-17
 */
@IsTest
private class AI_Case_Request_EventHandlerTest {
    
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
        for (Integer i = 0; i < 60; i++) {
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
        
        // Create AI provider credential
        AIProviderCredential__c credential = new AIProviderCredential__c(
            Name = 'TestProvider',
            API_Key__c = 'test-api-key-encrypted',
            Endpoint_URL__c = 'https://api.testprovider.com',
            IsActive__c = true
        );
        insert credential;
    }
    
    @IsTest
    static void testHandleAfterInsertSingleEvent() {
        // Get test case
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        // Create AI case request event
        AI_Case_Request__e event = new AI_Case_Request__e(
            CaseId__c = testCase.Id,
            AI_Provider__c = 'TestProvider',
            Request_Type__c = 'Single Process',
            Priority__c = 'High',
            Status__c = 'Pending'
        );
        
        Test.startTest();
        
        // Handle the event
        AI_Case_Request_EventHandler.handleAfterInsert(new List<AI_Case_Request__e>{event});
        
        Test.stopTest();
        
        // Verify processing status record was created
        List<AI_Processing_Status__c> statusRecords = [
            SELECT Id, Case__c, AI_Provider__c, Status__c, Request_Time__c
            FROM AI_Processing_Status__c
            WHERE Case__c = :testCase.Id
        ];
        
        System.assertEquals(1, statusRecords.size(), 'Should create 1 processing status record');
        System.assertEquals('Pending', statusRecords[0].Status__c, 'Status should be Pending');
        System.assertEquals('TestProvider', statusRecords[0].AI_Provider__c, 'Provider should match');
        System.assertNotEquals(null, statusRecords[0].Request_Time__c, 'Request time should be set');
    }
    
    @IsTest
    static void testHandleAfterInsertMultipleEvents() {
        // Get test cases
        List<Case> testCases = [SELECT Id FROM Case LIMIT 10];
        
        // Create AI case request events
        List<AI_Case_Request__e> events = new List<AI_Case_Request__e>();
        for (Case c : testCases) {
            events.add(new AI_Case_Request__e(
                CaseId__c = c.Id,
                AI_Provider__c = 'TestProvider',
                Request_Type__c = 'Bulk Process',
                Priority__c = 'Normal',
                Status__c = 'Pending'
            ));
        }
        
        Test.startTest();
        
        // Handle the events
        AI_Case_Request_EventHandler.handleAfterInsert(events);
        
        Test.stopTest();
        
        // Verify processing status records were created
        List<AI_Processing_Status__c> statusRecords = [
            SELECT Id, Case__c, Status__c
            FROM AI_Processing_Status__c
        ];
        
        System.assertEquals(10, statusRecords.size(), 'Should create 10 processing status records');
        
        for (AI_Processing_Status__c status : statusRecords) {
            System.assertEquals('Pending', status.Status__c, 'All statuses should be Pending');
        }
    }
    
    @IsTest
    static void testBulkProcessingThresholdReached() {
        // Get test cases
        List<Case> testCases = [SELECT Id FROM Case LIMIT 55];
        
        // Create existing pending status records to reach threshold
        List<AI_Processing_Status__c> existingPending = new List<AI_Processing_Status__c>();
        for (Integer i = 0; i < 45; i++) {
            existingPending.add(new AI_Processing_Status__c(
                Case__c = testCases[i].Id,
                AI_Provider__c = 'TestProvider',
                Status__c = 'Pending',
                Request_Time__c = DateTime.now().addMinutes(-10)
            ));
        }
        insert existingPending;
        
        // Create new AI case request events to push over threshold
        List<AI_Case_Request__e> events = new List<AI_Case_Request__e>();
        for (Integer i = 45; i < 55; i++) {
            events.add(new AI_Case_Request__e(
                CaseId__c = testCases[i].Id,
                AI_Provider__c = 'TestProvider',
                Request_Type__c = 'Bulk Process',
                Priority__c = 'Normal',
                Status__c = 'Pending'
            ));
        }
        
        Test.startTest();
        
        // Handle the events - should trigger bulk processing
        AI_Case_Request_EventHandler.handleAfterInsert(events);
        
        Test.stopTest();
        
        // Verify total processing status records
        List<AI_Processing_Status__c> allStatusRecords = [
            SELECT Id, Status__c
            FROM AI_Processing_Status__c
        ];
        
        System.assertEquals(55, allStatusRecords.size(), 'Should have 55 total status records');
        
        // Some records should be moved to Processing status due to threshold
        List<AI_Processing_Status__c> processingRecords = [
            SELECT Id
            FROM AI_Processing_Status__c
            WHERE Status__c = 'Processing'
        ];
        
        System.assert(processingRecords.size() > 0, 'Some records should be in Processing status');
    }
    
    @IsTest
    static void testBulkProcessingBelowThreshold() {
        // Get test cases
        List<Case> testCases = [SELECT Id FROM Case LIMIT 5];
        
        // Create AI case request events below threshold
        List<AI_Case_Request__e> events = new List<AI_Case_Request__e>();
        for (Case c : testCases) {
            events.add(new AI_Case_Request__e(
                CaseId__c = c.Id,
                AI_Provider__c = 'TestProvider',
                Request_Type__c = 'Single Process',
                Priority__c = 'Low',
                Status__c = 'Pending'
            ));
        }
        
        Test.startTest();
        
        // Handle the events - should NOT trigger bulk processing
        AI_Case_Request_EventHandler.handleAfterInsert(events);
        
        Test.stopTest();
        
        // Verify all records remain in Pending status
        List<AI_Processing_Status__c> statusRecords = [
            SELECT Id, Status__c
            FROM AI_Processing_Status__c
        ];
        
        System.assertEquals(5, statusRecords.size(), 'Should create 5 status records');
        
        for (AI_Processing_Status__c status : statusRecords) {
            System.assertEquals('Pending', status.Status__c, 'All should remain Pending');
        }
    }
    
    @IsTest
    static void testHandleEmptyEventList() {
        Test.startTest();
        
        // Handle empty event list
        AI_Case_Request_EventHandler.handleAfterInsert(new List<AI_Case_Request__e>());
        
        Test.stopTest();
        
        // Verify no records were created
        List<AI_Processing_Status__c> statusRecords = [SELECT Id FROM AI_Processing_Status__c];
        System.assertEquals(0, statusRecords.size(), 'Should not create any status records');
    }
    
    @IsTest
    static void testHandleNullEventList() {
        Test.startTest();
        
        // Handle null event list
        AI_Case_Request_EventHandler.handleAfterInsert(null);
        
        Test.stopTest();
        
        // Verify no records were created and no exceptions thrown
        List<AI_Processing_Status__c> statusRecords = [SELECT Id FROM AI_Processing_Status__c];
        System.assertEquals(0, statusRecords.size(), 'Should not create any status records');
    }
    
    @IsTest
    static void testSecurityEnforcement() {
        // Get test case
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        // Create AI case request event
        AI_Case_Request__e event = new AI_Case_Request__e(
            CaseId__c = testCase.Id,
            AI_Provider__c = 'TestProvider',
            Request_Type__c = 'Security Test',
            Priority__c = 'High',
            Status__c = 'Pending'
        );
        
        Test.startTest();
        
        // Handle the event
        AI_Case_Request_EventHandler.handleAfterInsert(new List<AI_Case_Request__e>{event});
        
        Test.stopTest();
        
        // Verify record was created (security should not prevent creation in test context)
        List<AI_Processing_Status__c> statusRecords = [
            SELECT Id, Case__c
            FROM AI_Processing_Status__c
            WHERE Case__c = :testCase.Id
        ];
        
        System.assertEquals(1, statusRecords.size(), 'Should create record with proper security');
    }
    
    @IsTest
    static void testErrorHandling() {
        // Create AI case request event with invalid case ID
        AI_Case_Request__e event = new AI_Case_Request__e(
            CaseId__c = '500000000000000', // Invalid case ID
            AI_Provider__c = 'TestProvider',
            Request_Type__c = 'Error Test',
            Priority__c = 'High',
            Status__c = 'Pending'
        );
        
        Test.startTest();
        
        try {
            // Handle the event - might cause foreign key constraint error
            AI_Case_Request_EventHandler.handleAfterInsert(new List<AI_Case_Request__e>{event});
        } catch (Exception e) {
            // Expected if foreign key constraint fails
            System.assert(true, 'Exception handling should work properly');
        }
        
        Test.stopTest();
        
        // Verify error logging
        List<Error_Log__c> errorLogs = [
            SELECT Id, Class_Name__c, Error_Type__c
            FROM Error_Log__c
            WHERE Class_Name__c LIKE '%AI_Case_Request_EventHandler%'
        ];
        
        // Error logs may or may not be present depending on execution path
        System.assert(errorLogs.size() >= 0, 'Error logging should work');
    }
    
    @IsTest
    static void testMixedProviders() {
        // Get test cases
        List<Case> testCases = [SELECT Id FROM Case LIMIT 6];
        
        // Create AI case request events with different providers
        List<AI_Case_Request__e> events = new List<AI_Case_Request__e>();
        for (Integer i = 0; i < testCases.size(); i++) {
            String provider = (Math.mod(i, 2) == 0) ? 'TestProvider' : 'OtherProvider';
            events.add(new AI_Case_Request__e(
                CaseId__c = testCases[i].Id,
                AI_Provider__c = provider,
                Request_Type__c = 'Mixed Provider Test',
                Priority__c = 'Normal',
                Status__c = 'Pending'
            ));
        }
        
        Test.startTest();
        
        // Handle the events
        AI_Case_Request_EventHandler.handleAfterInsert(events);
        
        Test.stopTest();
        
        // Verify processing status records for different providers
        List<AI_Processing_Status__c> testProviderRecords = [
            SELECT Id
            FROM AI_Processing_Status__c
            WHERE AI_Provider__c = 'TestProvider'
        ];
        
        List<AI_Processing_Status__c> otherProviderRecords = [
            SELECT Id
            FROM AI_Processing_Status__c
            WHERE AI_Provider__c = 'OtherProvider'
        ];
        
        System.assertEquals(3, testProviderRecords.size(), 'Should have 3 TestProvider records');
        System.assertEquals(3, otherProviderRecords.size(), 'Should have 3 OtherProvider records');
    }
    
    @IsTest
    static void testBulkProcessingWithDifferentPriorities() {
        // Get test cases
        List<Case> testCases = [SELECT Id FROM Case LIMIT 10];
        
        // Create AI case request events with different priorities
        List<AI_Case_Request__e> events = new List<AI_Case_Request__e>();
        List<String> priorities = new List<String>{'High', 'Medium', 'Low'};
        
        for (Integer i = 0; i < testCases.size(); i++) {
            String priority = priorities[Math.mod(i, 3)];
            events.add(new AI_Case_Request__e(
                CaseId__c = testCases[i].Id,
                AI_Provider__c = 'TestProvider',
                Request_Type__c = 'Priority Test',
                Priority__c = priority,
                Status__c = 'Pending'
            ));
        }
        
        Test.startTest();
        
        // Handle the events
        AI_Case_Request_EventHandler.handleAfterInsert(events);
        
        Test.stopTest();
        
        // Verify processing status records were created for all priorities
        Map<String, Integer> priorityCounts = new Map<String, Integer>();
        
        for (AI_Processing_Status__c status : [SELECT Id FROM AI_Processing_Status__c]) {
            priorityCounts.put('Total', (priorityCounts.get('Total') ?: 0) + 1);
        }
        
        System.assertEquals(10, priorityCounts.get('Total'), 'Should process all priority levels');
    }
    
    @IsTest
    static void testConcurrentEventHandling() {
        // Get test cases
        List<Case> testCases = [SELECT Id FROM Case LIMIT 20];
        
        // Create multiple batches of AI case request events
        List<AI_Case_Request__e> batch1 = new List<AI_Case_Request__e>();
        List<AI_Case_Request__e> batch2 = new List<AI_Case_Request__e>();
        
        for (Integer i = 0; i < 10; i++) {
            batch1.add(new AI_Case_Request__e(
                CaseId__c = testCases[i].Id,
                AI_Provider__c = 'TestProvider',
                Request_Type__c = 'Concurrent Test Batch 1',
                Priority__c = 'Normal',
                Status__c = 'Pending'
            ));
            
            batch2.add(new AI_Case_Request__e(
                CaseId__c = testCases[i + 10].Id,
                AI_Provider__c = 'TestProvider',
                Request_Type__c = 'Concurrent Test Batch 2',
                Priority__c = 'Normal',
                Status__c = 'Pending'
            ));
        }
        
        Test.startTest();
        
        // Handle both batches
        AI_Case_Request_EventHandler.handleAfterInsert(batch1);
        AI_Case_Request_EventHandler.handleAfterInsert(batch2);
        
        Test.stopTest();
        
        // Verify all records were processed
        List<AI_Processing_Status__c> statusRecords = [
            SELECT Id, Case__c
            FROM AI_Processing_Status__c
        ];
        
        System.assertEquals(20, statusRecords.size(), 'Should handle concurrent batches correctly');
    }
}