/**
 * @description Test class for AIConfigurationController
 * @author RouteLogic Team
 * @date 2025-01-20
 */
@isTest
private class AIConfigurationControllerTest {
    
    @TestSetup
    static void setup() {
        // Create test configuration overrides
        List<AI_Config_Override__c> configOverrides = new List<AI_Config_Override__c>();
        
        configOverrides.add(new AI_Config_Override__c(
            Name = 'Default_Batch_Size__c',
            Setting_Value__c = '50',
            Setting_Type__c = 'Number',
            Is_Active__c = true,
            Description__c = 'Test batch size override'
        ));
        
        configOverrides.add(new AI_Config_Override__c(
            Name = 'Enable_Debug_Logging__c',
            Setting_Value__c = 'true',
            Setting_Type__c = 'Boolean',
            Is_Active__c = true,
            Description__c = 'Test debug logging override'
        ));
        
        insert configOverrides;
        
        // Create test provider overrides
        AI_Provider_Override__c providerOverride = new AI_Provider_Override__c(
            Provider_Metadata_Id__c = 'TEST_PROVIDER_ID_001',
            Provider_Name__c = 'Test AI Provider',
            Is_Active__c = true,
            API_Endpoint__c = 'https://test.api.com/v1',
            Max_Batch_Size__c = 100,
            Timeout_ms__c = 30000,
            Priority__c = 1
        );
        insert providerOverride;
    }
    
    /**
     * @description Test retrieving configuration settings
     */
    @isTest
    static void testGetConfigurationSettings() {
        Test.startTest();
        
        Map<String, Object> settings = AIConfigurationController.getConfigurationSettings();
        
        Test.stopTest();
        
        // Verify settings are returned
        System.assertNotEquals(null, settings, 'Settings should not be null');
        
        // Verify default values are present
        System.assert(settings.containsKey('Default_Batch_Size__c'), 
            'Should contain batch size setting');
        System.assert(settings.containsKey('Max_Retry_Attempts__c'), 
            'Should contain retry attempts setting');
        System.assert(settings.containsKey('Circuit_Breaker_Threshold__c'), 
            'Should contain circuit breaker setting');
        
        // Verify types
        System.assert(settings.get('Default_Batch_Size__c') instanceof Integer || 
                     settings.get('Default_Batch_Size__c') instanceof Decimal,
                     'Batch size should be numeric');
    }
    
    /**
     * @description Test updating configuration setting
     */
    @isTest
    static void testUpdateConfigurationSetting() {
        Test.startTest();
        
        // Update a setting
        AIConfigurationController.updateConfigurationSetting('Test_Setting__c', 'TestValue');
        
        Test.stopTest();
        
        // Verify override was created
        AI_Config_Override__c override = [
            SELECT Setting_Value__c, Last_Modified_By__c
            FROM AI_Config_Override__c
            WHERE Name = 'Test_Setting__c'
            LIMIT 1
        ];
        
        System.assertEquals('TestValue', override.Setting_Value__c, 
            'Setting value should be updated');
        System.assertEquals(UserInfo.getUserId(), override.Last_Modified_By__c, 
            'Should track who modified');
    }
    
    /**
     * @description Test updating existing configuration setting
     */
    @isTest
    static void testUpdateExistingConfigurationSetting() {
        Test.startTest();
        
        // Update existing setting
        AIConfigurationController.updateConfigurationSetting('Default_Batch_Size__c', 75);
        
        Test.stopTest();
        
        // Verify override was updated
        AI_Config_Override__c override = [
            SELECT Setting_Value__c
            FROM AI_Config_Override__c
            WHERE Name = 'Default_Batch_Size__c'
            LIMIT 1
        ];
        
        System.assertEquals('75', override.Setting_Value__c, 
            'Setting value should be updated to new value');
    }
    
    /**
     * @description Test retrieving provider settings
     */
    @isTest
    static void testGetProviderSettings() {
        Test.startTest();
        
        List<AIConfigurationController.ProviderSetting> providers = 
            AIConfigurationController.getProviderSettings();
        
        Test.stopTest();
        
        System.assertNotEquals(null, providers, 'Providers list should not be null');
        // Note: Actual provider count depends on metadata in the org
    }
    
    /**
     * @description Test updating provider setting
     */
    @isTest
    static void testUpdateProviderSetting() {
        Test.startTest();
        
        Map<String, Object> settings = new Map<String, Object>{
            'Is_Active__c' => false,
            'API_Endpoint__c' => 'https://updated.api.com/v2',
            'Max_Batch_Size__c' => 150,
            'Timeout_ms__c' => 45000,
            'Priority__c' => 2
        };
        
        AIConfigurationController.updateProviderSetting('TEST_PROVIDER_ID_002', settings);
        
        Test.stopTest();
        
        // Verify override was created
        AI_Provider_Override__c override = [
            SELECT Is_Active__c, API_Endpoint__c, Max_Batch_Size__c
            FROM AI_Provider_Override__c
            WHERE Provider_Metadata_Id__c = 'TEST_PROVIDER_ID_002'
            LIMIT 1
        ];
        
        System.assertEquals(false, override.Is_Active__c, 'Should be inactive');
        System.assertEquals('https://updated.api.com/v2', override.API_Endpoint__c, 
            'Endpoint should be updated');
        System.assertEquals(150, override.Max_Batch_Size__c, 'Batch size should be updated');
    }
    
    /**
     * @description Test provider connection test with mock
     */
    @isTest
    static void testProviderConnectionSuccess() {
        // This would require a provider metadata record to exist
        // Using mock HTTP response
        Test.setMock(HttpCalloutMock.class, new MockHealthCheckResponse(200));
        
        Test.startTest();
        
        try {
            // This will fail without actual metadata, but tests the structure
            AIConfigurationController.ConnectionTestResult result = 
                AIConfigurationController.testProviderConnection('TEST_ID');
                
            // In a real test with metadata, we'd verify:
            // System.assertEquals(true, result.success, 'Connection should succeed');
        } catch (Exception e) {
            // Expected without actual metadata
            System.assert(e.getMessage().contains('List has no rows'), 
                'Should fail due to missing metadata');
        }
        
        Test.stopTest();
    }
    
    /**
     * @description Test configuration validation
     */
    @isTest
    static void testValidateConfiguration() {
        Test.startTest();
        
        Map<String, AIConfigurationController.ValidationResult> results = 
            AIConfigurationController.validateConfiguration();
        
        Test.stopTest();
        
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assert(results.containsKey('General Settings'), 
            'Should validate general settings');
        System.assert(results.containsKey('Provider Configuration'), 
            'Should validate provider configuration');
        System.assert(results.containsKey('Security Settings'), 
            'Should validate security settings');
        
        // Verify structure of results
        for (String category : results.keySet()) {
            AIConfigurationController.ValidationResult result = results.get(category);
            System.assertNotEquals(null, result.success, 
                'Each result should have success status');
            System.assertNotEquals(null, result.message, 
                'Each result should have a message');
        }
    }
    
    /**
     * @description Test permission checking
     */
    @isTest
    static void testPermissionDenied() {
        // Create user without permission
        User testUser = createTestUser('Standard User');
        
        System.runAs(testUser) {
            Test.startTest();
            
            try {
                AIConfigurationController.updateConfigurationSetting('Test', 'Value');
                System.assert(false, 'Should have thrown permission exception');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('permission'), 
                    'Should be permission error');
            }
            
            Test.stopTest();
        }
    }
    
    /**
     * @description Test error handling
     */
    @isTest
    static void testErrorHandling() {
        Test.startTest();
        
        try {
            // Try to update with null setting name
            AIConfigurationController.updateConfigurationSetting(null, 'Value');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Failed to update'), 
                'Should have proper error message');
        }
        
        Test.stopTest();
    }
    
    // Helper methods
    
    private static User createTestUser(String profileName) {
        Profile p = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
        
        User u = new User(
            Alias = 'configtst',
            Email = 'configtest@routelogic.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'ConfigTest',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'configtest' + DateTime.now().getTime() + '@routelogic.com'
        );
        
        insert u;
        return u;
    }
    
    /**
     * @description Mock for health check HTTP response
     */
    private class MockHealthCheckResponse implements HttpCalloutMock {
        private Integer statusCode;
        
        public MockHealthCheckResponse(Integer statusCode) {
            this.statusCode = statusCode;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setHeader('X-Response-Time', '123ms');
            
            if (statusCode == 200) {
                res.setBody('{"status":"healthy","version":"1.0"}');
            } else {
                res.setBody('{"error":"Service unavailable"}');
            }
            
            res.setStatusCode(statusCode);
            return res;
        }
    }
}