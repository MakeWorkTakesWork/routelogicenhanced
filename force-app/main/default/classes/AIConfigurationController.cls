/**
 * @description Apex controller for AI Configuration Manager LWC
 * Provides secure access to configuration settings with proper validation
 * @author RouteLogic Team
 * @date 2025-01-20
 * @group Configuration Management
 */
public with sharing class AIConfigurationController {
    
    /**
     * @description Retrieves all AI processing configuration settings
     * @return Map of configuration settings
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getConfigurationSettings() {
        try {
            // Query custom metadata for AI processing configuration
            List<AI_Processing_Config__mdt> configs = [
                SELECT DeveloperName, Label, Setting_Type__c, Setting_Value__c, 
                       Description__c, Is_Active__c, Category__c
                FROM AI_Processing_Config__mdt
                WHERE Is_Active__c = true
                WITH SECURITY_ENFORCED
            ];
            
            Map<String, Object> settings = new Map<String, Object>();
            
            // Convert to a structure suitable for the LWC
            for (AI_Processing_Config__mdt config : configs) {
                settings.put(config.DeveloperName, config.Setting_Value__c);
            }
            
            // Add default values if settings don't exist
            if (!settings.containsKey('Default_Batch_Size__c')) {
                settings.put('Default_Batch_Size__c', 100);
            }
            if (!settings.containsKey('Max_Retry_Attempts__c')) {
                settings.put('Max_Retry_Attempts__c', 3);
            }
            if (!settings.containsKey('Circuit_Breaker_Threshold__c')) {
                settings.put('Circuit_Breaker_Threshold__c', 5);
            }
            if (!settings.containsKey('Circuit_Breaker_Timeout__c')) {
                settings.put('Circuit_Breaker_Timeout__c', 30);
            }
            if (!settings.containsKey('API_Timeout__c')) {
                settings.put('API_Timeout__c', 30);
            }
            if (!settings.containsKey('Enable_Debug_Logging__c')) {
                settings.put('Enable_Debug_Logging__c', false);
            }
            if (!settings.containsKey('Log_Retention_Days__c')) {
                settings.put('Log_Retention_Days__c', 30);
            }
            
            return settings;
            
        } catch (Exception e) {
            ErrorLogService.logError(
                'AIConfigurationController.getConfigurationSettings',
                e.getMessage(),
                e.getStackTraceString(),
                null
            );
            throw new AuraHandledException('Failed to retrieve configuration settings: ' + e.getMessage());
        }
    }
    
    /**
     * @description Updates a specific configuration setting
     * @param settingName The name of the setting to update
     * @param value The new value for the setting
     */
    @AuraEnabled
    public static void updateConfigurationSetting(String settingName, Object value) {
        try {
            // Input validation
            RouteLogicInputValidator.ValidationResult nameValidation = 
                RouteLogicInputValidator.validateString(settingName, 'Setting Name', 255, true);
            if (!nameValidation.isValid) {
                throw new RouteLogicValidationException(nameValidation.errorMessage);
            }
            
            // Sanitize input to prevent injection
            settingName = RouteLogicInputValidator.sanitizeInput(settingName);
            
            // Validate value is not null
            if (value == null) {
                throw new RouteLogicValidationException('Setting value cannot be null');
            }
            
            // Validate user has permission to modify settings
            if (!hasConfigurationPermission()) {
                throw new RouteLogicSecurityException('You do not have permission to modify configuration settings');
            }
            
            // Since custom metadata cannot be updated directly in Apex,
            // we'll use a custom object to store overrides
            List<AI_Config_Override__c> existingOverrides = [
                SELECT Id, Setting_Value__c
                FROM AI_Config_Override__c
                WHERE Setting_Name__c = :settingName
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            
            AI_Config_Override__c override;
            if (!existingOverrides.isEmpty()) {
                override = existingOverrides[0];
            } else {
                override = new AI_Config_Override__c(
                    Setting_Name__c = settingName
                );
            }
            
            override.Setting_Value__c = String.valueOf(value);
            override.Last_Modified_By__c = UserInfo.getUserId();
            override.Last_Modified_Date__c = DateTime.now();
            
            upsert override;
            
            // Log the configuration change
            MetricsLogger.logEvent('CONFIG_UPDATED', new Map<String, Object>{
                'setting' => settingName,
                'newValue' => value,
                'userId' => UserInfo.getUserId(),
                'timestamp' => System.now()
            });
            
        } catch (Exception e) {
            ErrorLogService.logError(
                'AIConfigurationController.updateConfigurationSetting',
                e.getMessage(),
                e.getStackTraceString(),
                null
            );
            throw new AuraHandledException('Failed to update configuration: ' + e.getMessage());
        }
    }
    
    /**
     * @description Retrieves all AI provider settings
     * @return List of provider settings
     */
    @AuraEnabled(cacheable=true)
    public static List<ProviderSetting> getProviderSettings() {
        try {
            List<AI_Provider_Settings__mdt> providers = [
                SELECT Id, DeveloperName, Label, Provider_Name__c, Is_Active__c,
                       API_Endpoint__c, Max_Batch_Size__c, Timeout_ms__c, Priority__c,
                       Authentication_Type__c, Named_Credential__c
                FROM AI_Provider_Settings__mdt
                ORDER BY Priority__c ASC
                WITH SECURITY_ENFORCED
            ];
            
            List<ProviderSetting> settings = new List<ProviderSetting>();
            
            for (AI_Provider_Settings__mdt provider : providers) {
                ProviderSetting setting = new ProviderSetting();
                setting.Id = provider.Id;
                setting.DeveloperName = provider.DeveloperName;
                setting.Provider_Name__c = provider.Provider_Name__c;
                setting.Is_Active__c = provider.Is_Active__c;
                setting.API_Endpoint__c = provider.API_Endpoint__c;
                setting.Max_Batch_Size__c = Integer.valueOf(provider.Max_Batch_Size__c);
                setting.Timeout_ms__c = Integer.valueOf(provider.Timeout_ms__c);
                setting.Priority__c = Integer.valueOf(provider.Priority__c);
                setting.Authentication_Type__c = provider.Authentication_Type__c;
                setting.Named_Credential__c = provider.Named_Credential__c;
                
                settings.add(setting);
            }
            
            return settings;
            
        } catch (Exception e) {
            ErrorLogService.logError(
                'AIConfigurationController.getProviderSettings',
                e.getMessage(),
                e.getStackTraceString(),
                null
            );
            throw new AuraHandledException('Failed to retrieve provider settings: ' + e.getMessage());
        }
    }
    
    /**
     * @description Updates AI provider settings
     * @param providerId The ID of the provider to update
     * @param settings Map of settings to update
     */
    @AuraEnabled
    public static void updateProviderSetting(String providerId, Map<String, Object> settings) {
        try {
            // Validate user has permission
            if (!hasConfigurationPermission()) {
                throw new AuraHandledException('You do not have permission to modify provider settings');
            }
            
            // Create or update provider override record
            List<AI_Provider_Override__c> existingOverrides = [
                SELECT Id
                FROM AI_Provider_Override__c
                WHERE Provider_Metadata_Id__c = :providerId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            
            AI_Provider_Override__c override;
            if (!existingOverrides.isEmpty()) {
                override = existingOverrides[0];
            } else {
                override = new AI_Provider_Override__c(
                    Provider_Metadata_Id__c = providerId
                );
            }
            
            // Update fields from settings map
            if (settings.containsKey('Is_Active__c')) {
                override.Is_Active__c = (Boolean)settings.get('Is_Active__c');
            }
            if (settings.containsKey('API_Endpoint__c')) {
                override.API_Endpoint__c = (String)settings.get('API_Endpoint__c');
            }
            if (settings.containsKey('Max_Batch_Size__c')) {
                override.Max_Batch_Size__c = (Decimal)settings.get('Max_Batch_Size__c');
            }
            if (settings.containsKey('Timeout_ms__c')) {
                override.Timeout_ms__c = (Decimal)settings.get('Timeout_ms__c');
            }
            if (settings.containsKey('Priority__c')) {
                override.Priority__c = (Decimal)settings.get('Priority__c');
            }
            
            override.Last_Modified_By__c = UserInfo.getUserId();
            override.Last_Modified_Date__c = DateTime.now();
            
            upsert override;
            
            // Log the change
            MetricsLogger.logEvent('PROVIDER_CONFIG_UPDATED', new Map<String, Object>{
                'providerId' => providerId,
                'settings' => settings,
                'userId' => UserInfo.getUserId(),
                'timestamp' => System.now()
            });
            
        } catch (Exception e) {
            ErrorLogService.logError(
                'AIConfigurationController.updateProviderSetting',
                e.getMessage(),
                e.getStackTraceString(),
                null
            );
            throw new AuraHandledException('Failed to update provider settings: ' + e.getMessage());
        }
    }
    
    /**
     * @description Tests connection to an AI provider
     * @param providerId The ID of the provider to test
     * @return Test result with success status and message
     */
    @AuraEnabled
    public static ConnectionTestResult testProviderConnection(String providerId) {
        try {
            // Get provider settings
            AI_Provider_Settings__mdt provider = [
                SELECT Provider_Name__c, API_Endpoint__c, Named_Credential__c,
                       Authentication_Type__c, Timeout_ms__c
                FROM AI_Provider_Settings__mdt
                WHERE Id = :providerId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            
            ConnectionTestResult result = new ConnectionTestResult();
            
            // Perform health check call
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:' + provider.Named_Credential__c + '/health');
            req.setMethod('GET');
            req.setTimeout(Integer.valueOf(provider.Timeout_ms__c));
            
            try {
                Http http = new Http();
                HttpResponse res = http.send(req);
                
                if (res.getStatusCode() == 200) {
                    result.success = true;
                    result.message = 'Connection successful';
                    result.responseTime = res.getHeader('X-Response-Time');
                } else {
                    result.success = false;
                    result.message = 'Connection failed: HTTP ' + res.getStatusCode();
                    result.errorDetails = res.getBody();
                }
            } catch (Exception e) {
                result.success = false;
                result.message = 'Connection error: ' + e.getMessage();
                result.errorDetails = e.getStackTraceString();
            }
            
            // Log test result
            MetricsLogger.logEvent('PROVIDER_CONNECTION_TEST', new Map<String, Object>{
                'providerId' => providerId,
                'providerName' => provider.Provider_Name__c,
                'success' => result.success,
                'message' => result.message,
                'timestamp' => System.now()
            });
            
            return result;
            
        } catch (Exception e) {
            ErrorLogService.logError(
                'AIConfigurationController.testProviderConnection',
                e.getMessage(),
                e.getStackTraceString(),
                null
            );
            
            ConnectionTestResult errorResult = new ConnectionTestResult();
            errorResult.success = false;
            errorResult.message = 'Test failed: ' + e.getMessage();
            return errorResult;
        }
    }
    
    /**
     * @description Validates the current configuration
     * @return Map of validation results by category
     */
    @AuraEnabled
    public static Map<String, ValidationResult> validateConfiguration() {
        Map<String, ValidationResult> results = new Map<String, ValidationResult>();
        
        try {
            // Validate general settings
            results.put('General Settings', validateGeneralSettings());
            
            // Validate provider configuration
            results.put('Provider Configuration', validateProviderConfiguration());
            
            // Validate security settings
            results.put('Security Settings', validateSecuritySettings());
            
            // Validate integration endpoints
            results.put('Integration Endpoints', validateIntegrationEndpoints());
            
            // Validate processing limits
            results.put('Processing Limits', validateProcessingLimits());
            
            return results;
            
        } catch (Exception e) {
            ErrorLogService.logError(
                'AIConfigurationController.validateConfiguration',
                e.getMessage(),
                e.getStackTraceString(),
                null
            );
            
            ValidationResult errorResult = new ValidationResult();
            errorResult.success = false;
            errorResult.message = 'Validation failed: ' + e.getMessage();
            results.put('Error', errorResult);
            return results;
        }
    }
    
    // Private helper methods
    
    /**
     * @description Checks if current user has permission to modify configuration
     * @return True if user has permission
     */
    private static Boolean hasConfigurationPermission() {
        // Check for custom permission
        return FeatureManagement.checkPermission('AI_Configuration_Manager') ||
               System.Label.AI_Config_Admin_Profile.contains(UserInfo.getProfileId());
    }
    
    private static ValidationResult validateGeneralSettings() {
        ValidationResult result = new ValidationResult();
        result.success = true;
        result.details = new List<String>();
        
        Map<String, Object> settings = getConfigurationSettings();
        
        // Validate batch size
        Integer batchSize = Integer.valueOf(settings.get('Default_Batch_Size__c'));
        if (batchSize < 1 || batchSize > 200) {
            result.success = false;
            result.details.add('Batch size must be between 1 and 200');
        }
        
        // Validate retry attempts
        Integer retryAttempts = Integer.valueOf(settings.get('Max_Retry_Attempts__c'));
        if (retryAttempts < 0 || retryAttempts > 5) {
            result.success = false;
            result.details.add('Retry attempts must be between 0 and 5');
        }
        
        result.message = result.success ? 
            'All general settings are valid' : 
            'General settings validation failed';
        
        return result;
    }
    
    private static ValidationResult validateProviderConfiguration() {
        ValidationResult result = new ValidationResult();
        result.details = new List<String>();
        
        List<ProviderSetting> providers = getProviderSettings();
        Integer activeCount = 0;
        
        for (ProviderSetting provider : providers) {
            if (provider.Is_Active__c) {
                activeCount++;
                
                // Validate endpoint
                if (String.isBlank(provider.API_Endpoint__c)) {
                    result.details.add(provider.Provider_Name__c + ': Missing API endpoint');
                }
                
                // Validate timeout
                if (provider.Timeout_ms__c < 1000 || provider.Timeout_ms__c > 120000) {
                    result.details.add(provider.Provider_Name__c + ': Timeout must be between 1-120 seconds');
                }
            }
        }
        
        if (activeCount == 0) {
            result.success = false;
            result.message = 'No active AI providers configured';
        } else {
            result.success = result.details.isEmpty();
            result.message = result.success ? 
                activeCount + ' active providers configured correctly' : 
                'Provider configuration has issues';
        }
        
        return result;
    }
    
    private static ValidationResult validateSecuritySettings() {
        ValidationResult result = new ValidationResult();
        result.success = true;
        result.details = new List<String>();
        
        // Check Named Credentials
        List<NamedCredential> credentials = [
            SELECT DeveloperName, Endpoint
            FROM NamedCredential
            WHERE DeveloperName IN ('Ada_API', 'Intercom_API')
        ];
        
        if (credentials.size() < 2) {
            result.success = false;
            result.details.add('Missing required Named Credentials');
        }
        
        // Check encryption settings
        if (!Schema.sObjectType.AI_Processing_Status__c.fields.Response_Data__c.isEncrypted()) {
            result.details.add('Response data field should be encrypted');
        }
        
        result.message = result.success ? 
            'Security settings are properly configured' : 
            'Security configuration needs attention';
        
        return result;
    }
    
    private static ValidationResult validateIntegrationEndpoints() {
        ValidationResult result = new ValidationResult();
        result.success = true;
        result.details = new List<String>();
        
        // Test each active provider's endpoint accessibility
        List<ProviderSetting> providers = getProviderSettings();
        
        for (ProviderSetting provider : providers) {
            if (provider.Is_Active__c) {
                // Check if Named Credential exists
                try {
                    NamedCredential nc = [
                        SELECT Id, Endpoint 
                        FROM NamedCredential 
                        WHERE DeveloperName = :provider.Named_Credential__c
                        LIMIT 1
                    ];
                } catch (Exception e) {
                    result.success = false;
                    result.details.add(provider.Provider_Name__c + ': Named Credential not found');
                }
            }
        }
        
        result.message = result.success ? 
            'All integration endpoints are configured' : 
            'Some integration endpoints are missing';
        
        return result;
    }
    
    private static ValidationResult validateProcessingLimits() {
        ValidationResult result = new ValidationResult();
        result.success = true;
        result.details = new List<String>();
        
        // Check org limits
        Map<String, System.OrgLimit> limits = OrgLimits.getMap();
        
        // Check async apex jobs limit
        System.OrgLimit asyncLimit = limits.get('DailyAsyncApexExecutions');
        if (asyncLimit.getValue() > asyncLimit.getLimit() * 0.8) {
            result.details.add('Approaching daily async apex execution limit');
        }
        
        // Check API calls limit
        System.OrgLimit apiLimit = limits.get('DailyApiRequests');
        if (apiLimit.getValue() > apiLimit.getLimit() * 0.8) {
            result.details.add('Approaching daily API request limit');
        }
        
        result.message = result.details.isEmpty() ? 
            'Processing limits are within safe thresholds' : 
            'Some limits need monitoring';
        
        return result;
    }
    
    // Inner classes
    
    public class ProviderSetting {
        @AuraEnabled public String Id { get; set; }
        @AuraEnabled public String DeveloperName { get; set; }
        @AuraEnabled public String Provider_Name__c { get; set; }
        @AuraEnabled public Boolean Is_Active__c { get; set; }
        @AuraEnabled public String API_Endpoint__c { get; set; }
        @AuraEnabled public Integer Max_Batch_Size__c { get; set; }
        @AuraEnabled public Integer Timeout_ms__c { get; set; }
        @AuraEnabled public Integer Priority__c { get; set; }
        @AuraEnabled public String Authentication_Type__c { get; set; }
        @AuraEnabled public String Named_Credential__c { get; set; }
    }
    
    public class ConnectionTestResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String responseTime { get; set; }
        @AuraEnabled public String errorDetails { get; set; }
    }
    
    public class ValidationResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public List<String> details { get; set; }
    }
}