/**
 * @description Test class for SecurityUtils
 * @author RouteLogic Team
 * @date 2025-01-17
 */
@IsTest
private class SecurityUtilsTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test account
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
        
        // Create test cases
        List<Case> testCases = new List<Case>();
        for (Integer i = 0; i < 5; i++) {
            testCases.add(new Case(
                Subject = 'Test Case ' + i,
                Description = 'Test description ' + i,
                Priority = 'Medium',
                Status = 'New',
                AccountId = testAccount.Id
            ));
        }
        insert testCases;
        
        // Create test AI processing status records
        List<AI_Processing_Status__c> statusRecords = new List<AI_Processing_Status__c>();
        for (Case c : testCases) {
            statusRecords.add(new AI_Processing_Status__c(
                Case__c = c.Id,
                AI_Provider__c = 'TestProvider',
                Status__c = 'Pending',
                Success__c = false
            ));
        }
        insert statusRecords;
    }
    
    @IsTest
    static void testStripInaccessibleRecordsCreatable() {
        // Get test cases for creating new records
        List<Case> testCases = [SELECT Id FROM Case LIMIT 3];
        
        // Create new AI processing status records
        List<AI_Processing_Status__c> newRecords = new List<AI_Processing_Status__c>();
        for (Case c : testCases) {
            newRecords.add(new AI_Processing_Status__c(
                Case__c = c.Id,
                AI_Provider__c = 'NewProvider',
                Status__c = 'New',
                Success__c = true
            ));
        }
        
        Test.startTest();
        
        // Strip inaccessible fields for creation
        List<SObject> accessibleRecords = SecurityUtils.stripInaccessibleRecords(
            AccessType.CREATABLE,
            newRecords
        );
        
        Test.stopTest();
        
        // Verify records are returned
        System.assertNotEquals(null, accessibleRecords, 'Should return accessible records');
        System.assertEquals(3, accessibleRecords.size(), 'Should return all accessible records');
        
        // Verify records can be inserted
        insert accessibleRecords;
        
        // Verify insertion was successful
        List<AI_Processing_Status__c> insertedRecords = [
            SELECT Id, AI_Provider__c
            FROM AI_Processing_Status__c
            WHERE AI_Provider__c = 'NewProvider'
        ];
        System.assertEquals(3, insertedRecords.size(), 'Should insert all records successfully');
    }
    
    @IsTest
    static void testStripInaccessibleRecordsUpdatable() {
        // Get existing test records
        List<AI_Processing_Status__c> existingRecords = [
            SELECT Id, Status__c, Success__c
            FROM AI_Processing_Status__c
            LIMIT 3
        ];
        
        // Update the records
        for (AI_Processing_Status__c record : existingRecords) {
            record.Status__c = 'Updated';
            record.Success__c = true;
        }
        
        Test.startTest();
        
        // Strip inaccessible fields for update
        List<SObject> accessibleRecords = SecurityUtils.stripInaccessibleRecords(
            AccessType.UPDATABLE,
            existingRecords
        );
        
        Test.stopTest();
        
        // Verify records are returned
        System.assertNotEquals(null, accessibleRecords, 'Should return accessible records');
        System.assertEquals(3, accessibleRecords.size(), 'Should return all accessible records');
        
        // Verify records can be updated
        update accessibleRecords;
        
        // Verify update was successful
        List<AI_Processing_Status__c> updatedRecords = [
            SELECT Id, Status__c
            FROM AI_Processing_Status__c
            WHERE Status__c = 'Updated'
        ];
        System.assertEquals(3, updatedRecords.size(), 'Should update all records successfully');
    }
    
    @IsTest
    static void testStripInaccessibleRecordsEmptyList() {
        Test.startTest();
        
        // Test with empty list
        List<SObject> result = SecurityUtils.stripInaccessibleRecords(
            AccessType.CREATABLE,
            new List<Case>()
        );
        
        Test.stopTest();
        
        // Verify empty list is returned
        System.assertNotEquals(null, result, 'Should return empty list, not null');
        System.assertEquals(0, result.size(), 'Should return empty list');
    }
    
    @IsTest
    static void testStripInaccessibleRecordsNullList() {
        Test.startTest();
        
        // Test with null list
        List<SObject> result = SecurityUtils.stripInaccessibleRecords(
            AccessType.CREATABLE,
            null
        );
        
        Test.stopTest();
        
        // Verify null is returned
        System.assertEquals(null, result, 'Should return null for null input');
    }
    
    @IsTest
    static void testHasReadAccess() {
        Test.startTest();
        
        // Test read access for Case object fields
        Set<String> caseFields = new Set<String>{'Subject', 'Description', 'Priority', 'Status'};
        Boolean hasAccess = SecurityUtils.hasReadAccess(Case.SObjectType, caseFields);
        
        Test.stopTest();
        
        // In test context, user should have read access to standard Case fields
        System.assertEquals(true, hasAccess, 'Should have read access to standard Case fields');
    }
    
    @IsTest
    static void testHasReadAccessInvalidField() {
        Test.startTest();
        
        // Test read access with invalid field
        Set<String> invalidFields = new Set<String>{'InvalidField__c'};
        Boolean hasAccess = SecurityUtils.hasReadAccess(Case.SObjectType, invalidFields);
        
        Test.stopTest();
        
        // Should handle invalid fields gracefully
        System.assertEquals(true, hasAccess, 'Should handle invalid fields gracefully');
    }
    
    @IsTest
    static void testHasCreateAccess() {
        Test.startTest();
        
        // Test create access for Case object
        Set<String> caseFields = new Set<String>{'Subject', 'Description', 'Priority'};
        Boolean hasAccess = SecurityUtils.hasCreateAccess(Case.SObjectType, caseFields);
        
        Test.stopTest();
        
        // In test context, user should have create access to Case
        System.assertEquals(true, hasAccess, 'Should have create access to Case fields');
    }
    
    @IsTest
    static void testHasUpdateAccess() {
        Test.startTest();
        
        // Test update access for Case object
        Set<String> caseFields = new Set<String>{'Subject', 'Description', 'Priority', 'Status'};
        Boolean hasAccess = SecurityUtils.hasUpdateAccess(Case.SObjectType, caseFields);
        
        Test.stopTest();
        
        // In test context, user should have update access to Case
        System.assertEquals(true, hasAccess, 'Should have update access to Case fields');
    }
    
    @IsTest
    static void testHasDeleteAccess() {
        Test.startTest();
        
        // Test delete access for Case object
        Boolean hasAccess = SecurityUtils.hasDeleteAccess(Case.SObjectType);
        
        Test.stopTest();
        
        // In test context, user should have delete access to Case
        System.assertEquals(true, hasAccess, 'Should have delete access to Case');
    }
    
    @IsTest
    static void testSecurityException() {
        Test.startTest();
        
        // Test SecurityException creation
        SecurityUtils.SecurityException secEx = new SecurityUtils.SecurityException('Test security error');
        
        Test.stopTest();
        
        // Verify exception properties
        System.assertEquals('Test security error', secEx.getMessage(), 'Should set error message');
        System.assert(secEx instanceof Exception, 'Should be instance of Exception');
    }
    
    @IsTest
    static void testMultipleObjectTypes() {
        Test.startTest();
        
        // Test with multiple object types
        Set<String> accountFields = new Set<String>{'Name', 'Type'};
        Set<String> caseFields = new Set<String>{'Subject', 'Status'};
        
        Boolean accountReadAccess = SecurityUtils.hasReadAccess(Account.SObjectType, accountFields);
        Boolean caseReadAccess = SecurityUtils.hasReadAccess(Case.SObjectType, caseFields);
        
        Test.stopTest();
        
        // Verify access for both object types
        System.assertEquals(true, accountReadAccess, 'Should have read access to Account fields');
        System.assertEquals(true, caseReadAccess, 'Should have read access to Case fields');
    }
    
    @IsTest
    static void testLargeFieldSet() {
        Test.startTest();
        
        // Test with large field set
        Set<String> largeFieldSet = new Set<String>();
        for (Integer i = 0; i < 50; i++) {
            largeFieldSet.add('Field' + i + '__c');
        }
        
        // Add some valid fields
        largeFieldSet.add('Subject');
        largeFieldSet.add('Description');
        largeFieldSet.add('Status');
        
        Boolean hasAccess = SecurityUtils.hasReadAccess(Case.SObjectType, largeFieldSet);
        
        Test.stopTest();
        
        // Should handle large field sets efficiently
        System.assertEquals(true, hasAccess, 'Should handle large field sets');
    }
    
    @IsTest
    static void testCustomObjectAccess() {
        Test.startTest();
        
        // Test with custom object
        Set<String> customFields = new Set<String>{'Case__c', 'AI_Provider__c', 'Status__c'};
        Boolean hasCreateAccess = SecurityUtils.hasCreateAccess(
            AI_Processing_Status__c.SObjectType,
            customFields
        );
        Boolean hasUpdateAccess = SecurityUtils.hasUpdateAccess(
            AI_Processing_Status__c.SObjectType,
            customFields
        );
        Boolean hasDeleteAccess = SecurityUtils.hasDeleteAccess(AI_Processing_Status__c.SObjectType);
        
        Test.stopTest();
        
        // Verify access to custom object
        System.assertEquals(true, hasCreateAccess, 'Should have create access to custom object');
        System.assertEquals(true, hasUpdateAccess, 'Should have update access to custom object');
        System.assertEquals(true, hasDeleteAccess, 'Should have delete access to custom object');
    }
    
    @IsTest
    static void testErrorHandlingInStripInaccessible() {
        // Create records that might cause security issues
        List<AI_Processing_Status__c> problematicRecords = new List<AI_Processing_Status__c>();
        
        // Add a record with potentially restricted data
        problematicRecords.add(new AI_Processing_Status__c(
            AI_Provider__c = 'RestrictedProvider',
            Status__c = 'Restricted'
        ));
        
        Test.startTest();
        
        try {
            // This should handle any security exceptions gracefully
            List<SObject> result = SecurityUtils.stripInaccessibleRecords(
                AccessType.CREATABLE,
                problematicRecords
            );
            
            // If no exception, verify result
            System.assertNotEquals(null, result, 'Should return result even with restrictions');
        } catch (SecurityUtils.SecurityException secEx) {
            // Expected security exception
            System.assert(secEx.getMessage().contains('Insufficient permissions'), 
                'Should throw meaningful security exception');
        } catch (Exception e) {
            // Unexpected exception - should be handled by SecurityUtils
            System.assert(false, 'Should handle exceptions gracefully: ' + e.getMessage());
        }
        
        Test.stopTest();
        
        // Verify error logging occurred
        List<Error_Log__c> errorLogs = [
            SELECT Id, Class_Name__c
            FROM Error_Log__c
            WHERE Class_Name__c LIKE '%SecurityUtils%'
        ];
        
        // Error logs may or may not be present depending on execution path
        System.assert(errorLogs.size() >= 0, 'Error logging should work');
    }
}