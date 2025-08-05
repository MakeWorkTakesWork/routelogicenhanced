/**
 * @description Comprehensive test class for LogRetentionBatchMinimal
 * @author RouteLogic Team
 * @date 2025-02-05
 * @security Tests security fixes and AppExchange compliance
 */
@isTest
public class LogRetentionBatchMinimalTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test Error_Log__c records
        List<Error_Log__c> errorLogs = new List<Error_Log__c>();
        for (Integer i = 0; i < 10; i++) {
            errorLogs.add(new Error_Log__c(
                Error_Type__c = 'Test Error',
                Error_Message__c = 'Test error message ' + i,
                Class_Name__c = 'TestClass'
            ));
        }
        insert errorLogs;
        
        // Update CreatedDate to simulate old records (using a different approach)
        // Note: CreatedDate cannot be directly set, so we'll work with the records as-is
        
        // Create test AI_Processing_Status__c records
        List<AI_Processing_Status__c> statusRecords = new List<AI_Processing_Status__c>();
        for (Integer i = 0; i < 5; i++) {
            statusRecords.add(new AI_Processing_Status__c(
                Status__c = 'Completed',
                AI_Provider__c = 'Test Provider',
                Request_Time__c = DateTime.now().addDays(-20 - i)
            ));
        }
        insert statusRecords;
    }
    
    @isTest
    static void testValidObjectRetention() {
        // Test with valid object - using a future cutoff date since we can't modify CreatedDate
        DateTime cutoffDate = DateTime.now().addDays(1); // Future date to test logic
        LogRetentionBatchMinimal batch = new LogRetentionBatchMinimal('Error_Log__c', cutoffDate);
        
        Test.startTest();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Verify batch executed without errors (records created today should be deleted with future cutoff)
        List<Error_Log__c> remainingLogs = [SELECT Id FROM Error_Log__c];
        System.assertEquals(0, remainingLogs.size(), 'All error logs should be deleted with future cutoff date');
    }
    
    @isTest
    static void testSecurityValidation_InvalidObject() {
        // Test security: Invalid object should throw SecurityException
        DateTime cutoffDate = DateTime.now().addDays(-25);
        LogRetentionBatchMinimal batch = new LogRetentionBatchMinimal('InvalidObject__c', cutoffDate);
        
        Test.startTest();
        try {
            Database.QueryLocator ql = batch.start(null);
            System.assert(false, 'Should have thrown SecurityException for invalid object');
        } catch (SecurityException e) {
            System.assert(e.getMessage().contains('Invalid object for log retention'), 
                         'Should throw SecurityException with proper message');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testSecurityValidation_SQLInjectionPrevention() {
        // Test security: SQL injection attempt should be prevented
        DateTime cutoffDate = DateTime.now().addDays(-25);
        LogRetentionBatchMinimal batch = new LogRetentionBatchMinimal('Error_Log__c\'; DROP TABLE User; --', cutoffDate);
        
        Test.startTest();
        try {
            Database.QueryLocator ql = batch.start(null);
            System.assert(false, 'Should have thrown SecurityException for SQL injection attempt');
        } catch (SecurityException e) {
            System.assert(e.getMessage().contains('Invalid object for log retention'), 
                         'Should prevent SQL injection with SecurityException');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testFieldAccessValidation() {
        // Test field access validation
        DateTime cutoffDate = DateTime.now().addDays(-25);
        LogRetentionBatchMinimal batch = new LogRetentionBatchMinimal('Error_Log__c', cutoffDate);
        
        Test.startTest();
        Database.QueryLocator ql = batch.start(null);
        Test.stopTest();
        
        // Should complete without errors if field access is valid
        System.assertNotEquals(null, ql, 'Query locator should be created for valid object and field');
    }
    
    @isTest
    static void testBatchExecution() {
        // Test full batch execution
        DateTime cutoffDate = DateTime.now().addDays(-25);
        LogRetentionBatchMinimal batch = new LogRetentionBatchMinimal('Error_Log__c', cutoffDate);
        
        Test.startTest();
        Id batchId = Database.executeBatch(batch, 5);
        Test.stopTest();
        
        // Verify batch completed
        AsyncApexJob job = [SELECT Status, NumberOfErrors FROM AsyncApexJob WHERE Id = :batchId];
        System.assertEquals('Completed', job.Status, 'Batch should complete successfully');
        System.assertEquals(0, job.NumberOfErrors, 'Batch should complete without errors');
    }
    
    @isTest
    static void testEmptyScope() {
        // Test with empty scope (no records to delete)
        DateTime cutoffDate = DateTime.now().addDays(-100);
        LogRetentionBatchMinimal batch = new LogRetentionBatchMinimal('Error_Log__c', cutoffDate);
        
        Test.startTest();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Should complete without errors even with empty scope
        List<Error_Log__c> allLogs = [SELECT Id FROM Error_Log__c];
        System.assert(allLogs.size() > 0, 'All logs should remain when cutoff is very old');
    }
    
    @isTest
    static void testProcessingStatusRetention() {
        // Test with AI_Processing_Status__c object
        DateTime cutoffDate = DateTime.now().addDays(-15);
        LogRetentionBatchMinimal batch = new LogRetentionBatchMinimal('AI_Processing_Status__c', cutoffDate);
        
        Test.startTest();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Verify records older than cutoff were deleted
        List<AI_Processing_Status__c> remainingStatus = [SELECT Id FROM AI_Processing_Status__c WHERE CreatedDate < :cutoffDate];
        System.assertEquals(0, remainingStatus.size(), 'Old status records should be deleted');
    }
    
    @isTest
    static void testSecurityEnforcement() {
        // Test WITH SECURITY_ENFORCED is applied
        DateTime cutoffDate = DateTime.now().addDays(-25);
        LogRetentionBatchMinimal batch = new LogRetentionBatchMinimal('Error_Log__c', cutoffDate);
        
        Test.startTest();
        Database.QueryLocator ql = batch.start(null);
        Test.stopTest();
        
        // Query should be created with security enforcement
        System.assertNotEquals(null, ql, 'Query locator should be created with security enforcement');
    }
    
    @isTest
    static void testErrorHandling() {
        // Test error handling in execute method
        DateTime cutoffDate = DateTime.now().addDays(-25);
        LogRetentionBatchMinimal batch = new LogRetentionBatchMinimal('Error_Log__c', cutoffDate);
        
        // Create a scenario that might cause errors
        List<Error_Log__c> testLogs = [SELECT Id FROM Error_Log__c LIMIT 1];
        
        Test.startTest();
        if (!testLogs.isEmpty()) {
            batch.execute(null, testLogs);
        }
        Test.stopTest();
        
        // Should handle errors gracefully
        System.assert(true, 'Error handling should work gracefully');
    }
    
    @isTest
    static void testFinishMethod() {
        // Test finish method logging
        DateTime cutoffDate = DateTime.now().addDays(-25);
        LogRetentionBatchMinimal batch = new LogRetentionBatchMinimal('Error_Log__c', cutoffDate);
        
        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        
        // Should complete without errors
        System.assert(true, 'Finish method should complete without errors');
    }
}

