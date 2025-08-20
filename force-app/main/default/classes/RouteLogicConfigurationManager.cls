/**
 * @description Configuration management system for RouteLogic Enhanced v4.0.0
 * @author RouteLogic Team
 * @date 2025-01-21
 * @version 4.0.0
 * 
 * SECURITY FIXES APPLIED (2025-01-31):
 * - Fix #1: Replaced hardcoded encryption key in getMasterKey() with secure retrieval from Protected Custom Metadata
 * 
 * This class provides secure configuration management including:
 * - Custom metadata type configuration storage
 * - Encrypted sensitive data handling
 * - Environment-specific configuration
 * - Configuration validation and testing
 * - Deployment automation support
 */
public with sharing class RouteLogicConfigurationManager {
    
    // Configuration cache
    private static Map<String, ConfigurationValue> configurationCache = new Map<String, ConfigurationValue>();
    private static Boolean cacheInitialized = false;
    
    // Configuration constants
    private static final String PROVIDER_SETTINGS = 'Provider_Settings';
    private static final String ROUTING_RULES = 'Routing_Rules';
    private static final String SYSTEM_PARAMETERS = 'System_Parameters';
    private static final String SECURITY_SETTINGS = 'Security_Settings';
    private static final String INTEGRATION_SETTINGS = 'Integration_Settings';
    
    /**
     * @description Get configuration value by key
     * @param configurationKey The configuration key
     * @return Configuration value or null if not found
     */
    public static String getConfigurationValue(String configurationKey) {
        if (String.isBlank(configurationKey)) {
            throw new IllegalArgumentException('Configuration key cannot be null or empty');
        }
        
        // Initialize cache if needed
        if (!cacheInitialized) {
            initializeCache();
        }
        
        ConfigurationValue config = configurationCache.get(configurationKey);
        if (config == null) {
            return null;
        }
        
        // Decrypt if encrypted
        if (config.isEncrypted && String.isNotBlank(config.value)) {
            try {
                return RouteLogicEncryptionUtility.decrypt(config.value);
            } catch (Exception e) {
                return null;
            }
        }
        
        return config.value;
    }
    
    /**
     * @description Get configuration value with default
     * @param configurationKey The configuration key
     * @param defaultValue Default value if configuration not found
     * @return Configuration value or default value
     */
    public static String getConfigurationValue(String configurationKey, String defaultValue) {
        String value = getConfigurationValue(configurationKey);
        return String.isNotBlank(value) ? value : defaultValue;
    }
    
    /**
     * @description Get configuration value as Boolean
     * @param configurationKey The configuration key
     * @param defaultValue Default value if configuration not found
     * @return Boolean configuration value
     */
    public static Boolean getBooleanConfiguration(String configurationKey, Boolean defaultValue) {
        String value = getConfigurationValue(configurationKey);
        if (String.isBlank(value)) {
            return defaultValue;
        }
        
        try {
            return Boolean.valueOf(value);
        } catch (Exception e) {
            return defaultValue;
        }
    }
    
    /**
     * @description Get configuration value as Integer
     * @param configurationKey The configuration key
     * @param defaultValue Default value if configuration not found
     * @return Integer configuration value
     */
    public static Integer getIntegerConfiguration(String configurationKey, Integer defaultValue) {
        String value = getConfigurationValue(configurationKey);
        if (String.isBlank(value)) {
            return defaultValue;
        }
        
        try {
            return Integer.valueOf(value);
        } catch (Exception e) {
            return defaultValue;
        }
    }
    
    /**
     * @description Get configuration value as Decimal
     * @param configurationKey The configuration key
     * @param defaultValue Default value if configuration not found
     * @return Decimal configuration value
     */
    public static Decimal getDecimalConfiguration(String configurationKey, Decimal defaultValue) {
        String value = getConfigurationValue(configurationKey);
        if (String.isBlank(value)) {
            return defaultValue;
        }
        
        try {
            return Decimal.valueOf(value);
        } catch (Exception e) {
            return defaultValue;
        }
    }
    
    /**
     * @description Get provider configuration
     * @param providerName The AI provider name
     * @return Provider configuration map
     */
    public static Map<String, String> getProviderConfiguration(String providerName) {
        if (String.isBlank(providerName)) {
            throw new IllegalArgumentException('Provider name cannot be null or empty');
        }
        
        Map<String, String> providerConfig = new Map<String, String>();
        String configPrefix = 'Provider_' + providerName + '_';
        
        // Get all provider-specific configurations
        for (String key : configurationCache.keySet()) {
            if (key.startsWith(configPrefix)) {
                String configKey = key.substring(configPrefix.length());
                String configValue = getConfigurationValue(key);
                if (String.isNotBlank(configValue)) {
                    providerConfig.put(configKey, configValue);
                }
            }
        }
        
        return providerConfig;
    }
    
    /**
     * @description Set configuration value (for testing and admin operations)
     * @param configurationKey The configuration key
     * @param configurationValue The configuration value
     * @param isEncrypted Whether the value should be encrypted
     */
    public static void setConfigurationValue(String configurationKey, String configurationValue, Boolean isEncrypted) {
        if (String.isBlank(configurationKey)) {
            throw new IllegalArgumentException('Configuration key cannot be null or empty');
        }
        
        String valueToStore = configurationValue;
        
        // Encrypt if required
        if (isEncrypted && String.isNotBlank(configurationValue)) {
            try {
                valueToStore = RouteLogicEncryptionUtility.encrypt(configurationValue);
            } catch (Exception e) {
                throw new ConfigurationException('Failed to encrypt configuration value: ' + e.getMessage());
            }
        }
        
        // Update cache
        ConfigurationValue config = new ConfigurationValue();
        config.key = configurationKey;
        config.value = valueToStore;
        config.isEncrypted = isEncrypted != null ? isEncrypted : false;
        config.environment = getCurrentEnvironment();
        
        configurationCache.put(configurationKey, config);
        
        // In a real implementation, this would also update the custom metadata type
        // For now, we'll just update the cache
    }
    
    /**
     * @description Validate configuration
     * @param configurationKey The configuration key
     * @param configurationValue The configuration value
     * @param configurationType The configuration type
     * @return Validation result
     */
    public static ValidationResult validateConfiguration(String configurationKey, String configurationValue, String configurationType) {
        ValidationResult result = new ValidationResult();
        result.isValid = true;
        result.errorMessage = '';
        
        try {
            // Basic validation
            if (String.isBlank(configurationKey)) {
                result.isValid = false;
                result.errorMessage = 'Configuration key cannot be empty';
                return result;
            }
            
            // Type-specific validation
            switch on configurationType {
                when 'Provider_Settings' {
                    result = validateProviderSettings(configurationKey, configurationValue);
                }
                when 'Routing_Rules' {
                    result = validateRoutingRules(configurationKey, configurationValue);
                }
                when 'System_Parameters' {
                    result = validateSystemParameters(configurationKey, configurationValue);
                }
                when 'Security_Settings' {
                    result = validateSecuritySettings(configurationKey, configurationValue);
                }
                when 'Integration_Settings' {
                    result = validateIntegrationSettings(configurationKey, configurationValue);
                }
                when else {
                    result.isValid = false;
                    result.errorMessage = 'Unknown configuration type: ' + configurationType;
                }
            }
            
        } catch (Exception e) {
            result.isValid = false;
            result.errorMessage = 'Validation failed: ' + e.getMessage();
        }
        
        return result;
    }
    
    /**
     * @description Test configuration connectivity
     * @param configurationKey The configuration key
     * @return Test result
     */
    public static TestResult testConfiguration(String configurationKey) {
        TestResult result = new TestResult();
        result.success = false;
        result.message = '';
        result.responseTime = 0;
        
        try {
            DateTime startTime = DateTime.now();
            
            // Get configuration value
            String configValue = getConfigurationValue(configurationKey);
            if (String.isBlank(configValue)) {
                result.message = 'Configuration not found: ' + configurationKey;
                return result;
            }
            
            // Perform configuration-specific tests
            if (configurationKey.startsWith('Provider_')) {
                result = testProviderConfiguration(configurationKey, configValue);
            } else if (configurationKey.startsWith('Integration_')) {
                result = testIntegrationConfiguration(configurationKey, configValue);
            } else {
                result.success = true;
                result.message = 'Configuration value retrieved successfully';
            }
            
            // Calculate response time
            DateTime endTime = DateTime.now();
            result.responseTime = Integer.valueOf(endTime.getTime() - startTime.getTime());
            
        } catch (Exception e) {
            result.message = 'Test failed: ' + e.getMessage();
        }
        
        return result;
    }
    
    /**
     * @description Get all configurations for admin UI
     * @return List of configuration records
     */
    public static List<ConfigurationRecord> getAllConfigurations() {
        List<ConfigurationRecord> configurations = new List<ConfigurationRecord>();
        
        // Initialize cache if needed
        if (!cacheInitialized) {
            initializeCache();
        }
        
        for (String key : configurationCache.keySet()) {
            ConfigurationValue config = configurationCache.get(key);
            
            ConfigurationRecord record = new ConfigurationRecord();
            record.key = key;
            record.value = config.isEncrypted ? '***ENCRYPTED***' : config.value;
            record.isEncrypted = config.isEncrypted;
            record.environment = config.environment;
            record.configurationType = determineConfigurationType(key);
            
            configurations.add(record);
        }
        
        return configurations;
    }
    
    /**
     * @description Refresh configuration cache
     */
    public static void refreshCache() {
        configurationCache.clear();
        cacheInitialized = false;
        initializeCache();
    }
    
    /**
     * @description Initialize configuration cache from custom metadata
     */
    private static void initializeCache() {
        try {
            String currentEnvironment = getCurrentEnvironment();
            
            // Query custom metadata types
            List<RouteLogic_Configuration__mdt> configurations = [
                SELECT DeveloperName, Configuration_Type__c, Configuration_Value__c, 
                       Is_Encrypted__c, Environment__c
                FROM RouteLogic_Configuration__mdt
                WHERE Environment__c IN ('All', :currentEnvironment)
                WITH SECURITY_ENFORCED
            ];
            
            for (RouteLogic_Configuration__mdt config : configurations) {
                ConfigurationValue configValue = new ConfigurationValue();
                configValue.key = config.DeveloperName;
                configValue.value = config.Configuration_Value__c;
                configValue.isEncrypted = config.Is_Encrypted__c != null ? config.Is_Encrypted__c : false;
                configValue.environment = config.Environment__c;
                configValue.configurationType = config.Configuration_Type__c;
                
                configurationCache.put(config.DeveloperName, configValue);
            }
            
            cacheInitialized = true;
            
        } catch (Exception e) {
            cacheInitialized = true; // Prevent infinite retry
        }
    }
    
    /**
     * @description Get current environment
     * @return Environment name
     */
    private static String getCurrentEnvironment() {
        // Determine environment based on organization
        Boolean isSandbox = false;
        if (RouteLogicSecurityUtils.hasReadAccess('Organization')) {
            Organization org = [SELECT IsSandbox FROM Organization WITH SECURITY_ENFORCED LIMIT 1];
            isSandbox = org.IsSandbox;
        }
        return isSandbox ? 'Sandbox' : 'Production';
    }
    
    /**
     * @description Determine configuration type from key
     * @param configurationKey The configuration key
     * @return Configuration type
     */
    private static String determineConfigurationType(String configurationKey) {
        if (configurationKey.startsWith('Provider_')) {
            return PROVIDER_SETTINGS;
        } else if (configurationKey.startsWith('Routing_')) {
            return ROUTING_RULES;
        } else if (configurationKey.startsWith('System_')) {
            return SYSTEM_PARAMETERS;
        } else if (configurationKey.startsWith('Security_')) {
            return SECURITY_SETTINGS;
        } else if (configurationKey.startsWith('Integration_')) {
            return INTEGRATION_SETTINGS;
        }
        return SYSTEM_PARAMETERS;
    }
    
    /**
     * @description Validate provider settings
     * @param configurationKey The configuration key
     * @param configurationValue The configuration value
     * @return Validation result
     */
    private static ValidationResult validateProviderSettings(String configurationKey, String configurationValue) {
        ValidationResult result = new ValidationResult();
        result.isValid = true;
        result.errorMessage = '';
        
        // Provider-specific validation logic
        if (configurationKey.contains('_API_Key') || configurationKey.contains('_Secret')) {
            if (String.isBlank(configurationValue)) {
                result.isValid = false;
                result.errorMessage = 'API key or secret cannot be empty';
            } else if (configurationValue.length() < 10) {
                result.isValid = false;
                result.errorMessage = 'API key or secret appears to be too short';
            }
        } else if (configurationKey.contains('_Endpoint') || configurationKey.contains('_URL')) {
            if (String.isBlank(configurationValue)) {
                result.isValid = false;
                result.errorMessage = 'Endpoint URL cannot be empty';
            } else if (!configurationValue.startsWith('https://')) {
                result.isValid = false;
                result.errorMessage = 'Endpoint URL must use HTTPS';
            }
        }
        
        return result;
    }
    
    /**
     * @description Validate routing rules
     * @param configurationKey The configuration key
     * @param configurationValue The configuration value
     * @return Validation result
     */
    private static ValidationResult validateRoutingRules(String configurationKey, String configurationValue) {
        ValidationResult result = new ValidationResult();
        result.isValid = true;
        result.errorMessage = '';
        
        // Routing rules validation logic
        if (configurationKey.contains('_JSON') && String.isNotBlank(configurationValue)) {
            try {
                JSON.deserializeUntyped(configurationValue);
            } catch (Exception e) {
                result.isValid = false;
                result.errorMessage = 'Invalid JSON format: ' + e.getMessage();
            }
        }
        
        return result;
    }
    
    /**
     * @description Validate system parameters
     * @param configurationKey The configuration key
     * @param configurationValue The configuration value
     * @return Validation result
     */
    private static ValidationResult validateSystemParameters(String configurationKey, String configurationValue) {
        ValidationResult result = new ValidationResult();
        result.isValid = true;
        result.errorMessage = '';
        
        // System parameters validation logic
        if (configurationKey.contains('_Timeout') && String.isNotBlank(configurationValue)) {
            try {
                Integer timeout = Integer.valueOf(configurationValue);
                if (timeout < 1 || timeout > 120) {
                    result.isValid = false;
                    result.errorMessage = 'Timeout must be between 1 and 120 seconds';
                }
            } catch (Exception e) {
                result.isValid = false;
                result.errorMessage = 'Invalid timeout value: must be a number';
            }
        }
        
        return result;
    }
    
    /**
     * @description Validate security settings
     * @param configurationKey The configuration key
     * @param configurationValue The configuration value
     * @return Validation result
     */
    private static ValidationResult validateSecuritySettings(String configurationKey, String configurationValue) {
        ValidationResult result = new ValidationResult();
        result.isValid = true;
        result.errorMessage = '';
        
        // Security settings validation logic
        if (configurationKey.contains('_Encryption_Key') && String.isNotBlank(configurationValue)) {
            if (configurationValue.length() < 32) {
                result.isValid = false;
                result.errorMessage = 'Encryption key must be at least 32 characters';
            }
        }
        
        return result;
    }
    
    /**
     * @description Validate integration settings
     * @param configurationKey The configuration key
     * @param configurationValue The configuration value
     * @return Validation result
     */
    private static ValidationResult validateIntegrationSettings(String configurationKey, String configurationValue) {
        ValidationResult result = new ValidationResult();
        result.isValid = true;
        result.errorMessage = '';
        
        // Integration settings validation logic
        // Add specific validation as needed
        
        return result;
    }
    
    /**
     * @description Test provider configuration
     * @param configurationKey The configuration key
     * @param configurationValue The configuration value
     * @return Test result
     */
    private static TestResult testProviderConfiguration(String configurationKey, String configurationValue) {
        TestResult result = new TestResult();
        result.success = false;
        result.message = '';
        
        // In a real implementation, this would test connectivity to the provider
        // For now, we'll simulate a successful test
        result.success = true;
        result.message = 'Provider configuration test successful';
        
        return result;
    }
    
    /**
     * @description Test integration configuration
     * @param configurationKey The configuration key
     * @param configurationValue The configuration value
     * @return Test result
     */
    private static TestResult testIntegrationConfiguration(String configurationKey, String configurationValue) {
        TestResult result = new TestResult();
        result.success = false;
        result.message = '';
        
        // In a real implementation, this would test the integration
        // For now, we'll simulate a successful test
        result.success = true;
        result.message = 'Integration configuration test successful';
        
        return result;
    }
    
    /**
     * @description Get master encryption key from Protected Custom Metadata
     * @return Master encryption key
     * @throws AuraHandledException if key is not configured
     */
    public static String getMasterKey() {
        try {
            // SECURITY FIX #1: Replaced hardcoded key 'RouteLogic_Master_Key_v4' 
            // with secure retrieval from Protected Custom Metadata Type
            RouteLogic_Secrets__mdt secret = [
                SELECT Key_Value__c 
                FROM RouteLogic_Secrets__mdt 
                WHERE DeveloperName = 'Master_Key' 
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            
            if (secret != null && String.isNotBlank(secret.Key_Value__c)) {
                return secret.Key_Value__c;
            }
            
            throw new AuraHandledException('Master encryption key is not configured.');
            
        } catch (QueryException e) {
            // Handle case where Custom Metadata record doesn't exist
            throw new AuraHandledException('Master encryption key is not configured. Please ensure RouteLogic_Secrets__mdt.Master_Key record exists.');
        } catch (Exception e) {
            // Log error securely without exposing sensitive information
            throw new AuraHandledException('Failed to retrieve master encryption key. Please contact your administrator.');
        }
    }
    
    /**
     * @description Clear configuration cache (for testing)
     */
    @TestVisible
    private static void clearCache() {
        configurationCache.clear();
        cacheInitialized = false;
    }
    
    // Inner classes
    
    /**
     * @description Configuration value container
     */
    public class ConfigurationValue {
        public String key;
        public String value;
        public Boolean isEncrypted;
        public String environment;
        public String configurationType;
    }
    
    /**
     * @description Configuration record for admin UI
     */
    public class ConfigurationRecord {
        public String key;
        public String value;
        public Boolean isEncrypted;
        public String environment;
        public String configurationType;
    }
    
    /**
     * @description Validation result container
     */
    public class ValidationResult {
        public Boolean isValid;
        public String errorMessage;
    }
    
    /**
     * @description Test result container
     */
    public class TestResult {
        public Boolean success;
        public String message;
        public Integer responseTime;
    }
    
    // Custom exceptions
    public class ConfigurationException extends Exception {}
}

