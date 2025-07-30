/**
 * @description Test class for AIConfigurationValidationService
 * @author RouteLogic Team
 * @date 2025-01-20
 */
@isTest
private class AIConfigurationValidationServiceTest {
    
    @TestSetup
    static void setup() {
        // Create test configuration data
        List<AI_Config_Override__c> configOverrides = new List<AI_Config_Override__c>();
        
        configOverrides.add(new AI_Config_Override__c(
            Name = 'Default_Batch_Size__c',
            Setting_Value__c = '100',
            Setting_Type__c = 'Number',
            Is_Active__c = true
        ));
        
        configOverrides.add(new AI_Config_Override__c(
            Name = 'Max_Retry_Attempts__c',
            Setting_Value__c = '3',
            Setting_Type__c = 'Number',
            Is_Active__c = true
        ));
        
        configOverrides.add(new AI_Config_Override__c(
            Name = 'Circuit_Breaker_Threshold__c',
            Setting_Value__c = '5',
            Setting_Type__c = 'Number',
            Is_Active__c = true
        ));
        
        insert configOverrides;
        
        // Create test processing status records
        Case testCase = new Case(Subject = 'Test Case', Status = 'New');
        insert testCase;
        
        List<AI_Processing_Status__c> statusRecords = new List<AI_Processing_Status__c>();
        
        // Create some stuck processing records
        for (Integer i = 0; i < 3; i++) {
            statusRecords.add(new AI_Processing_Status__c(
                Case__c = testCase.Id,
                Status__c = 'Processing',
                AI_Provider__c = 'Test Provider',
                Request_Time__c = DateTime.now().addHours(-3)
            ));
        }
        
        // Create orphaned records
        for (Integer i = 0; i < 2; i++) {
            statusRecords.add(new AI_Processing_Status__c(
                Status__c = 'Failed',
                AI_Provider__c = 'Test Provider',
                Request_Time__c = DateTime.now().addDays(-10)
            ));
        }
        
        insert statusRecords;
        
        // Create error logs
        List<Error_Log__c> errorLogs = new List<Error_Log__c>();
        for (Integer i = 0; i < 5; i++) {
            errorLogs.add(new Error_Log__c(
                Class_Name__c = 'TestClass',
                Method_Name__c = 'testMethod',
                Error_Message__c = 'Test error',
                Stack_Trace__c = 'Test trace'
            ));
        }
        insert errorLogs;
    }
    
    /**
     * @description Test complete configuration validation
     */
    @isTest
    static void testValidateCompleteConfiguration() {
        Test.startTest();
        
        AIConfigurationValidationService.ValidationReport report = 
            AIConfigurationValidationService.validateCompleteConfiguration();
        
        Test.stopTest();
        
        // Verify report structure
        System.assertNotEquals(null, report, 'Report should not be null');
        System.assertNotEquals(null, report.timestamp, 'Should have timestamp');
        System.assertEquals(UserInfo.getUserName(), report.validatedBy, 
            'Should track validator');
        
        // Verify all categories are validated
        System.assertNotEquals(null, report.generalSettingsValidation, 
            'Should validate general settings');
        System.assertNotEquals(null, report.providerValidation, 
            'Should validate providers');
        System.assertNotEquals(null, report.securityValidation, 
            'Should validate security');
        System.assertNotEquals(null, report.integrationValidation, 
            'Should validate integrations');
        System.assertNotEquals(null, report.performanceValidation, 
            'Should validate performance');
        System.assertNotEquals(null, report.dataIntegrityValidation, 
            'Should validate data integrity');
        
        // Verify overall status
        System.assertNotEquals(null, report.overallStatus, 'Should have overall status');
        System.assertNotEquals(null, report.isValid, 'Should have validity flag');
    }
    
    /**
     * @description Test general settings validation
     */
    @isTest
    static void testValidateGeneralSettings() {
        Test.startTest();
        
        AIConfigurationValidationService.ValidationCategory result = 
            AIConfigurationValidationService.validateGeneralSettings();
        
        Test.stopTest();
        
        System.assertEquals('General Settings', result.name, 'Should have correct name');
        System.assertNotEquals(null, result.items, 'Should have validation items');
        System.assert(result.items.size() > 0, 'Should validate multiple settings');
        
        // Check specific validations
        Boolean foundBatchSize = false;
        Boolean foundRetry = false;
        
        for (AIConfigurationValidationService.ValidationItem item : result.items) {
            if (item.name.contains('Batch Size')) {
                foundBatchSize = true;
                System.assertEquals('PASSED', item.status, 
                    'Batch size should pass with valid value');
            }
            if (item.name.contains('Retry')) {
                foundRetry = true;
                System.assertEquals('PASSED', item.status, 
                    'Retry config should pass with valid value');
            }
        }
        
        System.assert(foundBatchSize, 'Should validate batch size');
        System.assert(foundRetry, 'Should validate retry configuration');
    }
    
    /**
     * @description Test provider validation
     */
    @isTest
    static void testValidateProviders() {
        Test.startTest();
        
        AIConfigurationValidationService.ValidationCategory result = 
            AIConfigurationValidationService.validateProviders();
        
        Test.stopTest();
        
        System.assertEquals('AI Provider Configuration', result.name, 
            'Should have correct name');
        
        // Check for active provider validation
        Boolean foundActiveCheck = false;
        for (AIConfigurationValidationService.ValidationItem item : result.items) {
            if (item.name.contains('Active Provider')) {
                foundActiveCheck = true;
                // Without metadata, this will fail
                if (item.errorCode == AIConfigurationValidationService.ERROR_NO_ACTIVE_PROVIDER) {
                    System.assertEquals('FAILED', item.status, 
                        'Should fail when no active providers');
                }
            }
        }
        
        System.assert(foundActiveCheck, 'Should check for active providers');
    }
    
    /**
     * @description Test security validation
     */
    @isTest
    static void testValidateSecurity() {
        Test.startTest();
        
        AIConfigurationValidationService.ValidationCategory result = 
            AIConfigurationValidationService.validateSecurity();
        
        Test.stopTest();
        
        System.assertEquals('Security Configuration', result.name, 
            'Should have correct name');
        
        // Check for specific security validations
        Boolean foundCredentials = false;
        Boolean foundPermissions = false;
        Boolean foundEncryption = false;
        
        for (AIConfigurationValidationService.ValidationItem item : result.items) {
            if (item.name.contains('Named Credentials')) foundCredentials = true;
            if (item.name.contains('Permissions')) foundPermissions = true;
            if (item.name.contains('Encryption')) foundEncryption = true;
        }
        
        System.assert(foundCredentials, 'Should validate named credentials');
        System.assert(foundPermissions, 'Should validate permissions');
        System.assert(foundEncryption, 'Should validate encryption');
    }
    
    /**
     * @description Test performance validation
     */
    @isTest
    static void testValidatePerformance() {
        Test.startTest();
        
        AIConfigurationValidationService.ValidationCategory result = 
            AIConfigurationValidationService.validatePerformance();
        
        Test.stopTest();
        
        System.assertEquals('Performance & Limits', result.name, 
            'Should have correct name');
        
        // Check for limit validations
        Boolean foundAsyncLimit = false;
        Boolean foundApiLimit = false;
        
        for (AIConfigurationValidationService.ValidationItem item : result.items) {
            if (item.name.contains('Async Apex')) {
                foundAsyncLimit = true;
                System.assertEquals('PASSED', item.status, 
                    'Async limit should pass in test');
            }
            if (item.name.contains('API Call')) {
                foundApiLimit = true;
                System.assertEquals('PASSED', item.status, 
                    'API limit should pass in test');
            }
        }
        
        System.assert(foundAsyncLimit, 'Should check async apex limit');
        System.assert(foundApiLimit, 'Should check API call limit');
    }
    
    /**
     * @description Test data integrity validation
     */
    @isTest
    static void testValidateDataIntegrity() {
        Test.startTest();
        
        AIConfigurationValidationService.ValidationCategory result = 
            AIConfigurationValidationService.validateDataIntegrity();
        
        Test.stopTest();
        
        System.assertEquals('Data Integrity', result.name, 'Should have correct name');
        
        // Check for data integrity validations
        Boolean foundOrphans = false;
        Boolean foundStuck = false;
        Boolean foundErrorLog = false;
        
        for (AIConfigurationValidationService.ValidationItem item : result.items) {
            if (item.name.contains('Orphaned')) {
                foundOrphans = true;
                System.assertEquals('WARNING', item.status, 
                    'Should warn about orphaned records');
            }
            if (item.name.contains('Stuck')) {
                foundStuck = true;
                System.assertEquals('WARNING', item.status, 
                    'Should warn about stuck records');
            }
            if (item.name.contains('Error Log')) {
                foundErrorLog = true;
            }
        }
        
        System.assert(foundOrphans, 'Should check for orphaned records');
        System.assert(foundStuck, 'Should check for stuck processing');
        System.assert(foundErrorLog, 'Should check error log size');
    }
    
    /**
     * @description Test validation with invalid settings
     */
    @isTest
    static void testValidationWithInvalidSettings() {
        // Update settings to invalid values
        AI_Config_Override__c invalidBatchSize = [
            SELECT Id FROM AI_Config_Override__c 
            WHERE Name = 'Default_Batch_Size__c' 
            LIMIT 1
        ];
        invalidBatchSize.Setting_Value__c = '300'; // Over limit
        update invalidBatchSize;
        
        Test.startTest();
        
        AIConfigurationValidationService.ValidationCategory result = 
            AIConfigurationValidationService.validateGeneralSettings();
        
        Test.stopTest();
        
        // Find batch size validation
        Boolean foundInvalidBatchSize = false;
        for (AIConfigurationValidationService.ValidationItem item : result.items) {
            if (item.name.contains('Batch Size')) {
                System.assertEquals('FAILED', item.status, 
                    'Should fail with invalid batch size');
                System.assertEquals(
                    AIConfigurationValidationService.ERROR_INVALID_BATCH_SIZE, 
                    item.errorCode,
                    'Should have correct error code'
                );
                foundInvalidBatchSize = true;
            }
        }
        
        System.assert(foundInvalidBatchSize, 'Should validate batch size');
    }
    
    /**
     * @description Test recommendation generation
     */
    @isTest
    static void testRecommendationGeneration() {
        Test.startTest();
        
        AIConfigurationValidationService.ValidationReport report = 
            AIConfigurationValidationService.validateCompleteConfiguration();
        
        Test.stopTest();
        
        System.assertNotEquals(null, report.recommendations, 
            'Should have recommendations list');
        
        // With test data, should have recommendations for:
        // - No active providers
        // - Orphaned records
        System.assert(report.recommendations.size() > 0, 
            'Should generate recommendations based on issues');
    }
    
    /**
     * @description Test error handling in validation
     */
    @isTest
    static void testValidationErrorHandling() {
        // Force an error by corrupting data
        delete [SELECT Id FROM AI_Config_Override__c];
        
        Test.startTest();
        
        AIConfigurationValidationService.ValidationReport report = 
            AIConfigurationValidationService.validateCompleteConfiguration();
        
        Test.stopTest();
        
        // Should handle errors gracefully
        System.assertNotEquals(null, report, 'Should return report even with errors');
        // Report should indicate issues but not crash
    }
}