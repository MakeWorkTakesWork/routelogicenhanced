@isTest
private class AIBulkOperationServiceTest {
    
    @testSetup
    static void setupTestData() {
        // Create test routes
        List<Route__c> routes = new List<Route__c>();
        for (Integer i = 0; i < 50; i++) {
            routes.add(new Route__c(
                Name = 'Test Route ' + i,
                Status__c = 'Pending',
                Priority__c = Math.mod(i, 5) + 1
            ));
        }
        insert routes;
        
        // Create test processing status records
        List<AI_Processing_Status__c> statuses = new List<AI_Processing_Status__c>();
        for (Integer i = 0; i < 20; i++) {
            statuses.add(new AI_Processing_Status__c(
                Status__c = 'Processing',
                Provider_Type__c = 'OpenAI'
            ));
        }
        insert statuses;
    }
    
    @isTest
    static void testBulkRouteProcessing() {
        // Get test route IDs
        List<Id> routeIds = new List<Id>();
        for (Route__c route : [SELECT Id FROM Route__c LIMIT 10]) {
            routeIds.add(route.Id);
        }
        
        AIBulkOperationService.BulkConfig config = 
            new AIBulkOperationService.BulkConfig();
        config.batchSize = 5;
        
        Test.startTest();
        
        AIBulkOperationService.BulkOperationResult result = 
            AIBulkOperationService.processRoutesBulk(
                routeIds, 'OpenAI', config
            );
        
        Test.stopTest();
        
        // Verify
        System.assertEquals(10, result.totalRecords, 
            'Should process 10 records');
        System.assert(result.successCount > 0, 
            'Should have some successes');
        System.assertEquals(0, result.errorCount, 
            'Should have no errors');
        System.assert(result.executionTime > 0, 
            'Should track execution time');
        System.assertNotEquals(null, result.operationId, 
            'Should generate operation ID');
    }
    
    @isTest
    static void testBulkStatusUpdate() {
        // Get test status records
        Map<Id, String> statusUpdates = new Map<Id, String>();
        for (AI_Processing_Status__c status : 
             [SELECT Id FROM AI_Processing_Status__c LIMIT 10]) {
            statusUpdates.put(status.Id, 'Completed');
        }
        
        AIBulkOperationService.BulkConfig config = 
            new AIBulkOperationService.BulkConfig();
        
        Test.startTest();
        
        AIBulkOperationService.BulkOperationResult result = 
            AIBulkOperationService.updateStatusBulk(statusUpdates, config);
        
        Test.stopTest();
        
        // Verify
        System.assertEquals(10, result.totalRecords, 
            'Should update 10 records');
        System.assertEquals(10, result.successCount, 
            'All updates should succeed');
        System.assertEquals(0, result.errorCount, 
            'Should have no errors');
        
        // Verify actual updates
        List<AI_Processing_Status__c> updated = [
            SELECT Status__c 
            FROM AI_Processing_Status__c 
            WHERE Id IN :statusUpdates.keySet()
        ];
        for (AI_Processing_Status__c status : updated) {
            System.assertEquals('Completed', status.Status__c, 
                'Status should be updated');
        }
    }
    
    @isTest
    static void testBulkDataImport() {
        // Prepare test data
        List<Map<String, Object>> dataRows = new List<Map<String, Object>>();
        for (Integer i = 0; i < 15; i++) {
            dataRows.add(new Map<String, Object>{
                'name' => 'Imported Route ' + i,
                'status' => 'Active',
                'priority' => i + 1
            });
        }
        
        Map<String, String> fieldMapping = new Map<String, String>{
            'name' => 'Name',
            'status' => 'Status__c',
            'priority' => 'Priority__c'
        };
        
        AIBulkOperationService.BulkConfig config = 
            new AIBulkOperationService.BulkConfig();
        config.batchSize = 10;
        
        Test.startTest();
        
        AIBulkOperationService.BulkOperationResult result = 
            AIBulkOperationService.importDataBulk(
                dataRows, 'Route__c', fieldMapping, config
            );
        
        Test.stopTest();
        
        // Verify
        System.assertEquals(15, result.totalRecords, 
            'Should import 15 records');
        System.assertEquals(15, result.successCount, 
            'All imports should succeed');
        
        // Verify imported records
        List<Route__c> imported = [
            SELECT Name FROM Route__c 
            WHERE Name LIKE 'Imported Route%'
        ];
        System.assertEquals(15, imported.size(), 
            'Should create 15 new routes');
    }
    
    @isTest
    static void testBulkDelete() {
        // Get records to delete
        List<Id> deleteIds = new List<Id>();
        for (Route__c route : [SELECT Id FROM Route__c LIMIT 5]) {
            deleteIds.add(route.Id);
        }
        
        AIBulkOperationService.BulkConfig config = 
            new AIBulkOperationService.BulkConfig();
        
        Test.startTest();
        
        AIBulkOperationService.BulkOperationResult result = 
            AIBulkOperationService.deleteBulk(deleteIds, false, config);
        
        Test.stopTest();
        
        // Verify
        System.assertEquals(5, result.totalRecords, 
            'Should delete 5 records');
        System.assertEquals(5, result.successCount, 
            'All deletes should succeed');
        
        // Verify deletion
        List<Route__c> remaining = [
            SELECT Id FROM Route__c WHERE Id IN :deleteIds
        ];
        System.assertEquals(0, remaining.size(), 
            'Records should be deleted');
    }
    
    @isTest
    static void testBulkFieldUpdate() {
        AIBulkOperationService.BulkConfig config = 
            new AIBulkOperationService.BulkConfig();
        config.batchSize = 25;
        
        Test.startTest();
        
        AIBulkOperationService.BulkOperationResult result = 
            AIBulkOperationService.updateFieldBulk(
                'Route__c',
                'Status__c',
                'Updated',
                'Priority__c > 3',
                config
            );
        
        Test.stopTest();
        
        // Verify
        System.assert(result.totalRecords > 0, 
            'Should update some records');
        System.assertEquals(result.totalRecords, result.successCount, 
            'All updates should succeed');
        
        // Verify field updates
        List<Route__c> updated = [
            SELECT Status__c FROM Route__c 
            WHERE Priority__c > 3
        ];
        for (Route__c route : updated) {
            System.assertEquals('Updated', route.Status__c, 
                'Status should be updated');
        }
    }
    
    @isTest
    static void testErrorHandling() {
        // Test with invalid data
        Map<Id, String> invalidUpdates = new Map<Id, String>{
            'invalid_id' => 'Failed'
        };
        
        AIBulkOperationService.BulkConfig config = 
            new AIBulkOperationService.BulkConfig();
        config.allOrNone = false;
        
        Test.startTest();
        
        AIBulkOperationService.BulkOperationResult result = 
            AIBulkOperationService.updateStatusBulk(invalidUpdates, config);
        
        Test.stopTest();
        
        // Verify error handling
        System.assertEquals(1, result.totalRecords, 
            'Should attempt 1 record');
        System.assertEquals(0, result.successCount, 
            'Should have no successes');
        System.assertEquals(1, result.errorCount, 
            'Should have 1 error');
        System.assert(result.errors.size() > 0, 
            'Should capture error details');
    }
    
    @isTest
    static void testProgressTracking() {
        AIBulkOperationService.BulkConfig config = 
            new AIBulkOperationService.BulkConfig();
        config.trackProgress = true;
        
        Test.startTest();
        
        // Track progress
        AIBulkOperationService.trackProgress('TEST_OP_123', 50, 100);
        
        Test.stopTest();
        
        // Verify no exceptions
        System.assert(true, 'Progress tracking should complete');
    }
    
    @isTest
    static void testLargeBatchHandling() {
        // Create large dataset
        List<Id> largeDataset = new List<Id>();
        for (Route__c route : [SELECT Id FROM Route__c]) {
            largeDataset.add(route.Id);
        }
        
        AIBulkOperationService.BulkConfig config = 
            new AIBulkOperationService.BulkConfig();
        config.batchSize = 10;
        
        Test.startTest();
        
        AIBulkOperationService.BulkOperationResult result = 
            AIBulkOperationService.processRoutesBulk(
                largeDataset, 'Claude', config
            );
        
        Test.stopTest();
        
        // Verify batch processing
        System.assertEquals(largeDataset.size(), result.totalRecords, 
            'Should process all records');
        System.assert(result.successCount > 0, 
            'Should have processed records');
    }
    
    @isTest
    static void testEmptyInputHandling() {
        AIBulkOperationService.BulkConfig config = 
            new AIBulkOperationService.BulkConfig();
        
        Test.startTest();
        
        // Test with empty list
        AIBulkOperationService.BulkOperationResult result = 
            AIBulkOperationService.processRoutesBulk(
                new List<Id>(), 'OpenAI', config
            );
        
        Test.stopTest();
        
        // Verify
        System.assertEquals(0, result.totalRecords, 
            'Should handle empty input');
        System.assertEquals(0, result.successCount, 
            'Should have no successes');
        System.assertEquals(0, result.errorCount, 
            'Should have no errors');
    }
    
    @isTest
    static void testNotificationEmail() {
        List<Id> routeIds = new List<Id>();
        for (Route__c route : [SELECT Id FROM Route__c LIMIT 5]) {
            routeIds.add(route.Id);
        }
        
        AIBulkOperationService.BulkConfig config = 
            new AIBulkOperationService.BulkConfig();
        config.notificationEmail = 'test@example.com';
        
        Test.startTest();
        
        AIBulkOperationService.BulkOperationResult result = 
            AIBulkOperationService.processRoutesBulk(
                routeIds, 'OpenAI', config
            );
        
        Test.stopTest();
        
        // Verify operation completed
        System.assertEquals(5, result.totalRecords, 
            'Should process records');
        // Note: Can't verify actual email sending in test context
    }
}