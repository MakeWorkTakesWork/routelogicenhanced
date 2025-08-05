/**
 * @description Comprehensive test class for AIQueryOptimizationServiceMinimal
 * @author RouteLogic Team
 * @date 2025-02-05
 * @security Tests security fixes and AppExchange compliance
 */
@isTest
public class AIQueryOptimizationServiceMinimalTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test AI_Processing_Status__c records
        List<AI_Processing_Status__c> statusRecords = new List<AI_Processing_Status__c>();
        for (Integer i = 0; i < 5; i++) {
            statusRecords.add(new AI_Processing_Status__c(
                Status__c = 'Completed',
                AI_Provider__c = 'Test Provider ' + i
            ));
        }
        insert statusRecords;
        
        // Create test Error_Log__c records
        List<Error_Log__c> errorLogs = new List<Error_Log__c>();
        for (Integer i = 0; i < 3; i++) {
            errorLogs.add(new Error_Log__c(
                Error_Type__c = 'Test Error',
                Error_Message__c = 'Test error message ' + i,
                Class_Name__c = 'TestClass'
            ));
        }
        insert errorLogs;
        
        // Create test Case records
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 3; i++) {
            cases.add(new Case(
                Subject = 'Test Case ' + i,
                Status = 'New',
                Priority = 'Medium'
            ));
        }
        insert cases;
    }
    
    @isTest
    static void testExecuteSecureQuery_ValidObject() {
        // Test with valid object and fields
        List<String> fields = new List<String>{'Id', 'Name', 'Status__c'};
        
        Test.startTest();
        List<SObject> results = AIQueryOptimizationServiceMinimal.executeSecureQuery(
            'AI_Processing_Status__c', fields, null, null, null
        );
        Test.stopTest();
        
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assert(results.size() > 0, 'Should return test records');
    }
    
    @isTest
    static void testExecuteSecureQuery_InvalidObject() {
        // Test security: Invalid object should throw SecurityException
        List<String> fields = new List<String>{'Id', 'Name'};
        
        Test.startTest();
        try {
            AIQueryOptimizationServiceMinimal.executeSecureQuery(
                'InvalidObject__c', fields, null, null, null
            );
            System.assert(false, 'Should have thrown SecurityException for invalid object');
        } catch (SecurityException e) {
            System.assert(e.getMessage().contains('Object not allowed for queries'), 
                         'Should throw SecurityException with proper message');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testExecuteSecureQuery_InvalidField() {
        // Test security: Invalid field should throw SecurityException
        List<String> fields = new List<String>{'Id', 'InvalidField__c'};
        
        Test.startTest();
        try {
            AIQueryOptimizationServiceMinimal.executeSecureQuery(
                'AI_Processing_Status__c', fields, null, null, null
            );
            System.assert(false, 'Should have thrown SecurityException for invalid field');
        } catch (SecurityException e) {
            System.assert(e.getMessage().contains('Field not allowed'), 
                         'Should throw SecurityException for invalid field');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testExecuteSecureQuery_SQLInjectionPrevention() {
        // Test security: SQL injection attempt should be prevented
        List<String> fields = new List<String>{'Id\'; DROP TABLE User; --', 'Name'};
        
        Test.startTest();
        try {
            AIQueryOptimizationServiceMinimal.executeSecureQuery(
                'AI_Processing_Status__c', fields, null, null, null
            );
            System.assert(false, 'Should have thrown SecurityException for SQL injection attempt');
        } catch (SecurityException e) {
            System.assert(e.getMessage().contains('Field not allowed'), 
                         'Should prevent SQL injection with SecurityException');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testExecuteSecureQuery_WithWhereClause() {
        // Test with valid WHERE clause
        List<String> fields = new List<String>{'Id', 'Name', 'Status__c'};
        String whereClause = 'Status__c = \'Completed\'';
        
        Test.startTest();
        List<SObject> results = AIQueryOptimizationServiceMinimal.executeSecureQuery(
            'AI_Processing_Status__c', fields, whereClause, null, null
        );
        Test.stopTest();
        
        System.assertNotEquals(null, results, 'Results should not be null');
    }
    
    @isTest
    static void testExecuteSecureQuery_WithOrderBy() {
        // Test with valid ORDER BY
        List<String> fields = new List<String>{'Id', 'Name', 'Status__c'};
        
        Test.startTest();
        List<SObject> results = AIQueryOptimizationServiceMinimal.executeSecureQuery(
            'AI_Processing_Status__c', fields, null, 'CreatedDate', null
        );
        Test.stopTest();
        
        System.assertNotEquals(null, results, 'Results should not be null');
    }
    
    @isTest
    static void testExecuteSecureQuery_InvalidOrderBy() {
        // Test security: Invalid ORDER BY field should throw SecurityException
        List<String> fields = new List<String>{'Id', 'Name'};
        
        Test.startTest();
        try {
            AIQueryOptimizationServiceMinimal.executeSecureQuery(
                'AI_Processing_Status__c', fields, null, 'InvalidField__c', null
            );
            System.assert(false, 'Should have thrown SecurityException for invalid ORDER BY field');
        } catch (SecurityException e) {
            System.assert(e.getMessage().contains('ORDER BY field not allowed'), 
                         'Should throw SecurityException for invalid ORDER BY field');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testExecuteSecureQuery_WithLimit() {
        // Test with valid limit
        List<String> fields = new List<String>{'Id', 'Name', 'Status__c'};
        
        Test.startTest();
        List<SObject> results = AIQueryOptimizationServiceMinimal.executeSecureQuery(
            'AI_Processing_Status__c', fields, null, null, 2
        );
        Test.stopTest();
        
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assert(results.size() <= 2, 'Should respect limit');
    }
    
    @isTest
    static void testExecuteSecureQuery_ExcessiveLimit() {
        // Test security: Excessive limit should throw SecurityException
        List<String> fields = new List<String>{'Id', 'Name'};
        
        Test.startTest();
        try {
            AIQueryOptimizationServiceMinimal.executeSecureQuery(
                'AI_Processing_Status__c', fields, null, null, 100000
            );
            System.assert(false, 'Should have thrown SecurityException for excessive limit');
        } catch (SecurityException e) {
            System.assert(e.getMessage().contains('Query limit exceeds maximum'), 
                         'Should throw SecurityException for excessive limit');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testGetProcessingStatus() {
        // Test getProcessingStatus method
        Test.startTest();
        List<AI_Processing_Status__c> results = AIQueryOptimizationServiceMinimal.getProcessingStatus(
            'Completed', 10
        );
        Test.stopTest();
        
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assert(results.size() > 0, 'Should return test records');
    }
    
    @isTest
    static void testGetProcessingStatus_NoFilter() {
        // Test getProcessingStatus without filter
        Test.startTest();
        List<AI_Processing_Status__c> results = AIQueryOptimizationServiceMinimal.getProcessingStatus(
            null, 10
        );
        Test.stopTest();
        
        System.assertNotEquals(null, results, 'Results should not be null');
    }
    
    @isTest
    static void testGetErrorLogs() {
        // Test getErrorLogs method
        Test.startTest();
        List<Error_Log__c> results = AIQueryOptimizationServiceMinimal.getErrorLogs(
            'Test Error', 10
        );
        Test.stopTest();
        
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assert(results.size() > 0, 'Should return test records');
    }
    
    @isTest
    static void testGetErrorLogs_NoFilter() {
        // Test getErrorLogs without filter
        Test.startTest();
        List<Error_Log__c> results = AIQueryOptimizationServiceMinimal.getErrorLogs(
            null, 10
        );
        Test.stopTest();
        
        System.assertNotEquals(null, results, 'Results should not be null');
    }
    
    @isTest
    static void testSecurityEnforcement() {
        // Test that security enforcement is applied
        List<String> fields = new List<String>{'Id', 'CaseNumber'};
        
        Test.startTest();
        List<SObject> results = AIQueryOptimizationServiceMinimal.executeSecureQuery(
            'Case', fields, null, null, 5
        );
        Test.stopTest();
        
        // Should complete without errors with security enforcement
        System.assertNotEquals(null, results, 'Results should not be null with security enforcement');
    }
    
    @isTest
    static void testFieldWhitelistValidation() {
        // Test comprehensive field whitelist validation
        List<String> validFields = new List<String>{'Id', 'Name', 'Status__c', 'AI_Provider__c', 'CreatedDate'};
        
        Test.startTest();
        List<SObject> results = AIQueryOptimizationServiceMinimal.executeSecureQuery(
            'AI_Processing_Status__c', validFields, null, null, null
        );
        Test.stopTest();
        
        System.assertNotEquals(null, results, 'Should accept all whitelisted fields');
    }
}

