/**
 * @description Service class for comprehensive AI configuration validation
 * Validates settings, provider configurations, and system readiness
 * @author RouteLogic Team
 * @date 2025-01-20
 * @group Configuration Management
 */
public with sharing class AIConfigurationValidationService {
    
    // Validation error codes
    public static final String ERROR_NO_ACTIVE_PROVIDER = 'NO_ACTIVE_PROVIDER';
    public static final String ERROR_INVALID_BATCH_SIZE = 'INVALID_BATCH_SIZE';
    public static final String ERROR_INVALID_TIMEOUT = 'INVALID_TIMEOUT';
    public static final String ERROR_MISSING_CREDENTIAL = 'MISSING_CREDENTIAL';
    public static final String ERROR_INVALID_ENDPOINT = 'INVALID_ENDPOINT';
    public static final String ERROR_PERMISSION_MISSING = 'PERMISSION_MISSING';
    public static final String ERROR_LIMIT_EXCEEDED = 'LIMIT_EXCEEDED';
    
    /**
     * @description Performs complete configuration validation
     * @return Comprehensive validation report
     */
    public static ValidationReport validateCompleteConfiguration() {
        ValidationReport report = new ValidationReport();
        report.timestamp = DateTime.now();
        report.validatedBy = UserInfo.getUserName();
        
        try {
            // Run all validation checks
            report.generalSettingsValidation = validateGeneralSettings();
            report.providerValidation = validateProviders();
            report.securityValidation = validateSecurity();
            report.integrationValidation = validateIntegrations();
            report.performanceValidation = validatePerformance();
            report.dataIntegrityValidation = validateDataIntegrity();
            
            // Calculate overall status
            report.overallStatus = calculateOverallStatus(report);
            report.isValid = report.overallStatus == 'PASSED';
            
            // Generate recommendations
            report.recommendations = generateRecommendations(report);
            
            // Log validation execution
            logValidationExecution(report);
            
        } catch (Exception e) {
            report.overallStatus = 'ERROR';
            report.isValid = false;
            report.errorMessage = e.getMessage();
            
            ErrorLogService.logError(
                'AIConfigurationValidationService.validateCompleteConfiguration',
                e.getMessage(),
                e.getStackTraceString(),
                null
            );
        }
        
        return report;
    }
    
    /**
     * @description Validates general AI processing settings
     * @return Validation result for general settings
     */
    public static ValidationCategory validateGeneralSettings() {
        ValidationCategory category = new ValidationCategory('General Settings');
        
        try {
            Map<String, Object> settings = AIConfigurationController.getConfigurationSettings();
            
            // Validate batch size
            ValidationItem batchSizeCheck = new ValidationItem('Batch Size Configuration');
            Integer batchSize = Integer.valueOf(settings.get('Default_Batch_Size__c'));
            if (batchSize >= 1 && batchSize <= 200) {
                batchSizeCheck.status = 'PASSED';
                batchSizeCheck.message = 'Batch size (' + batchSize + ') is within valid range';
            } else {
                batchSizeCheck.status = 'FAILED';
                batchSizeCheck.message = 'Batch size must be between 1 and 200';
                batchSizeCheck.errorCode = ERROR_INVALID_BATCH_SIZE;
            }
            category.items.add(batchSizeCheck);
            
            // Validate retry configuration
            ValidationItem retryCheck = new ValidationItem('Retry Configuration');
            Integer maxRetries = Integer.valueOf(settings.get('Max_Retry_Attempts__c'));
            if (maxRetries >= 0 && maxRetries <= 5) {
                retryCheck.status = 'PASSED';
                retryCheck.message = 'Retry attempts (' + maxRetries + ') configured correctly';
            } else {
                retryCheck.status = 'FAILED';
                retryCheck.message = 'Max retry attempts must be between 0 and 5';
            }
            category.items.add(retryCheck);
            
            // Validate circuit breaker
            ValidationItem circuitBreakerCheck = new ValidationItem('Circuit Breaker Configuration');
            Integer cbThreshold = Integer.valueOf(settings.get('Circuit_Breaker_Threshold__c'));
            Integer cbTimeout = Integer.valueOf(settings.get('Circuit_Breaker_Timeout__c'));
            if (cbThreshold > 0 && cbTimeout > 0) {
                circuitBreakerCheck.status = 'PASSED';
                circuitBreakerCheck.message = 'Circuit breaker configured with threshold=' + 
                    cbThreshold + ', timeout=' + cbTimeout + ' minutes';
            } else {
                circuitBreakerCheck.status = 'WARNING';
                circuitBreakerCheck.message = 'Circuit breaker settings may need adjustment';
            }
            category.items.add(circuitBreakerCheck);
            
            // Validate timeout settings
            ValidationItem timeoutCheck = new ValidationItem('API Timeout Configuration');
            Integer apiTimeout = Integer.valueOf(settings.get('API_Timeout__c'));
            if (apiTimeout >= 10 && apiTimeout <= 120) {
                timeoutCheck.status = 'PASSED';
                timeoutCheck.message = 'API timeout (' + apiTimeout + ' seconds) is appropriate';
            } else {
                timeoutCheck.status = 'FAILED';
                timeoutCheck.message = 'API timeout must be between 10 and 120 seconds';
                timeoutCheck.errorCode = ERROR_INVALID_TIMEOUT;
            }
            category.items.add(timeoutCheck);
            
        } catch (Exception e) {
            category.status = 'ERROR';
            category.errorMessage = e.getMessage();
        }
        
        category.calculateStatus();
        return category;
    }
    
    /**
     * @description Validates AI provider configurations
     * @return Validation result for providers
     */
    public static ValidationCategory validateProviders() {
        ValidationCategory category = new ValidationCategory('AI Provider Configuration');
        
        try {
            List<AIConfigurationController.ProviderSetting> providers = 
                AIConfigurationController.getProviderSettings();
            
            // Check for active providers
            ValidationItem activeProviderCheck = new ValidationItem('Active Provider Check');
            Integer activeCount = 0;
            for (AIConfigurationController.ProviderSetting provider : providers) {
                if (provider.Is_Active__c) {
                    activeCount++;
                }
            }
            
            if (activeCount > 0) {
                activeProviderCheck.status = 'PASSED';
                activeProviderCheck.message = activeCount + ' active provider(s) configured';
            } else {
                activeProviderCheck.status = 'FAILED';
                activeProviderCheck.message = 'No active AI providers found';
                activeProviderCheck.errorCode = ERROR_NO_ACTIVE_PROVIDER;
            }
            category.items.add(activeProviderCheck);
            
            // Validate each active provider
            for (AIConfigurationController.ProviderSetting provider : providers) {
                if (provider.Is_Active__c) {
                    ValidationItem providerCheck = new ValidationItem(
                        provider.Provider_Name__c + ' Configuration'
                    );
                    
                    List<String> issues = new List<String>();
                    
                    // Check endpoint
                    if (String.isBlank(provider.API_Endpoint__c)) {
                        issues.add('Missing API endpoint');
                    }
                    
                    // Check batch size
                    if (provider.Max_Batch_Size__c < 1 || provider.Max_Batch_Size__c > 200) {
                        issues.add('Invalid batch size');
                    }
                    
                    // Check timeout
                    if (provider.Timeout_ms__c < 1000 || provider.Timeout_ms__c > 120000) {
                        issues.add('Invalid timeout value');
                    }
                    
                    // Check Named Credential
                    if (String.isBlank(provider.Named_Credential__c)) {
                        issues.add('Missing Named Credential');
                    }
                    
                    if (issues.isEmpty()) {
                        providerCheck.status = 'PASSED';
                        providerCheck.message = 'Provider configured correctly';
                    } else {
                        providerCheck.status = 'FAILED';
                        providerCheck.message = 'Issues: ' + String.join(issues, ', ');
                    }
                    
                    category.items.add(providerCheck);
                }
            }
            
        } catch (Exception e) {
            category.status = 'ERROR';
            category.errorMessage = e.getMessage();
        }
        
        category.calculateStatus();
        return category;
    }
    
    /**
     * @description Validates security configurations
     * @return Validation result for security
     */
    public static ValidationCategory validateSecurity() {
        ValidationCategory category = new ValidationCategory('Security Configuration');
        
        try {
            // Check Named Credentials
            ValidationItem credentialCheck = new ValidationItem('Named Credentials');
            List<NamedCredential> credentials = [
                SELECT DeveloperName, Endpoint
                FROM NamedCredential
                WHERE DeveloperName IN ('Ada_API', 'Intercom_API')
            ];
            
            if (credentials.size() >= 1) {
                credentialCheck.status = 'PASSED';
                credentialCheck.message = credentials.size() + ' Named Credential(s) configured';
            } else {
                credentialCheck.status = 'FAILED';
                credentialCheck.message = 'Required Named Credentials not found';
                credentialCheck.errorCode = ERROR_MISSING_CREDENTIAL;
            }
            category.items.add(credentialCheck);
            
            // Check user permissions
            ValidationItem permissionCheck = new ValidationItem('User Permissions');
            Boolean hasConfigPermission = FeatureManagement.checkPermission('AI_Configuration_Manager');
            Boolean hasProcessingPermission = FeatureManagement.checkPermission('AI_Bulk_Processing');
            
            if (hasConfigPermission || hasProcessingPermission) {
                permissionCheck.status = 'PASSED';
                permissionCheck.message = 'Required permissions are assigned';
            } else {
                permissionCheck.status = 'WARNING';
                permissionCheck.message = 'Some permissions may be missing';
            }
            category.items.add(permissionCheck);
            
            // Check field encryption
            ValidationItem encryptionCheck = new ValidationItem('Data Encryption');
            Boolean isEncrypted = Schema.sObjectType.AI_Processing_Status__c
                .fields.Response_Data__c.isEncrypted();
            
            if (isEncrypted) {
                encryptionCheck.status = 'PASSED';
                encryptionCheck.message = 'Sensitive data fields are encrypted';
            } else {
                encryptionCheck.status = 'WARNING';
                encryptionCheck.message = 'Consider enabling encryption for sensitive fields';
            }
            category.items.add(encryptionCheck);
            
        } catch (Exception e) {
            category.status = 'ERROR';
            category.errorMessage = e.getMessage();
        }
        
        category.calculateStatus();
        return category;
    }
    
    /**
     * @description Validates integration endpoints
     * @return Validation result for integrations
     */
    public static ValidationCategory validateIntegrations() {
        ValidationCategory category = new ValidationCategory('Integration Endpoints');
        
        try {
            List<AIConfigurationController.ProviderSetting> providers = 
                AIConfigurationController.getProviderSettings();
            
            for (AIConfigurationController.ProviderSetting provider : providers) {
                if (provider.Is_Active__c) {
                    ValidationItem endpointCheck = new ValidationItem(
                        provider.Provider_Name__c + ' Endpoint'
                    );
                    
                    // Validate endpoint format
                    if (String.isNotBlank(provider.API_Endpoint__c)) {
                        if (provider.API_Endpoint__c.startsWith('https://')) {
                            endpointCheck.status = 'PASSED';
                            endpointCheck.message = 'Endpoint uses secure HTTPS protocol';
                        } else {
                            endpointCheck.status = 'WARNING';
                            endpointCheck.message = 'Endpoint should use HTTPS for security';
                        }
                    } else {
                        endpointCheck.status = 'FAILED';
                        endpointCheck.message = 'Endpoint URL is missing';
                        endpointCheck.errorCode = ERROR_INVALID_ENDPOINT;
                    }
                    
                    category.items.add(endpointCheck);
                }
            }
            
        } catch (Exception e) {
            category.status = 'ERROR';
            category.errorMessage = e.getMessage();
        }
        
        category.calculateStatus();
        return category;
    }
    
    /**
     * @description Validates performance and limits
     * @return Validation result for performance
     */
    public static ValidationCategory validatePerformance() {
        ValidationCategory category = new ValidationCategory('Performance & Limits');
        
        try {
            // Check async apex limit
            ValidationItem asyncLimitCheck = new ValidationItem('Async Apex Capacity');
            System.OrgLimit asyncLimit = OrgLimits.getMap().get('DailyAsyncApexExecutions');
            Decimal usagePercent = (asyncLimit.getValue() * 100.0) / asyncLimit.getLimit();
            
            if (usagePercent < 80) {
                asyncLimitCheck.status = 'PASSED';
                asyncLimitCheck.message = String.format('Using {0}% of daily async limit', 
                    new List<Object>{usagePercent.setScale(1)});
            } else if (usagePercent < 90) {
                asyncLimitCheck.status = 'WARNING';
                asyncLimitCheck.message = 'Approaching async apex limit (' + 
                    usagePercent.setScale(1) + '% used)';
            } else {
                asyncLimitCheck.status = 'FAILED';
                asyncLimitCheck.message = 'Async apex limit nearly exhausted';
                asyncLimitCheck.errorCode = ERROR_LIMIT_EXCEEDED;
            }
            category.items.add(asyncLimitCheck);
            
            // Check API call limit
            ValidationItem apiLimitCheck = new ValidationItem('API Call Capacity');
            System.OrgLimit apiLimit = OrgLimits.getMap().get('DailyApiRequests');
            Decimal apiUsagePercent = (apiLimit.getValue() * 100.0) / apiLimit.getLimit();
            
            if (apiUsagePercent < 80) {
                apiLimitCheck.status = 'PASSED';
                apiLimitCheck.message = String.format('Using {0}% of daily API limit', 
                    new List<Object>{apiUsagePercent.setScale(1)});
            } else {
                apiLimitCheck.status = 'WARNING';
                apiLimitCheck.message = 'High API usage (' + apiUsagePercent.setScale(1) + '%)';
            }
            category.items.add(apiLimitCheck);
            
            // Check Platform Cache
            ValidationItem cacheCheck = new ValidationItem('Platform Cache Configuration');
            try {
                Cache.OrgPartition orgPart = Cache.Org.getPartition('AIProcessing');
                if (orgPart != null) {
                    cacheCheck.status = 'PASSED';
                    cacheCheck.message = 'Platform cache partition configured';
                } else {
                    cacheCheck.status = 'WARNING';
                    cacheCheck.message = 'Platform cache not configured';
                }
            } catch (Exception e) {
                cacheCheck.status = 'WARNING';
                cacheCheck.message = 'Platform cache partition not found';
            }
            category.items.add(cacheCheck);
            
        } catch (Exception e) {
            category.status = 'ERROR';
            category.errorMessage = e.getMessage();
        }
        
        category.calculateStatus();
        return category;
    }
    
    /**
     * @description Validates data integrity
     * @return Validation result for data integrity
     */
    public static ValidationCategory validateDataIntegrity() {
        ValidationCategory category = new ValidationCategory('Data Integrity');
        
        try {
            // Check for orphaned records
            ValidationItem orphanCheck = new ValidationItem('Orphaned Records Check');
            Integer orphanedStatuses = [
                SELECT COUNT()
                FROM AI_Processing_Status__c
                WHERE Case__c = null
                AND CreatedDate < :DateTime.now().addDays(-7)
            ];
            
            if (orphanedStatuses == 0) {
                orphanCheck.status = 'PASSED';
                orphanCheck.message = 'No orphaned processing records found';
            } else {
                orphanCheck.status = 'WARNING';
                orphanCheck.message = orphanedStatuses + ' orphaned records detected';
            }
            category.items.add(orphanCheck);
            
            // Check stuck processing records
            ValidationItem stuckRecordsCheck = new ValidationItem('Stuck Processing Records');
            Integer stuckRecords = [
                SELECT COUNT()
                FROM AI_Processing_Status__c
                WHERE Status__c = 'Processing'
                AND LastModifiedDate < :DateTime.now().addHours(-2)
            ];
            
            if (stuckRecords == 0) {
                stuckRecordsCheck.status = 'PASSED';
                stuckRecordsCheck.message = 'No stuck processing records';
            } else {
                stuckRecordsCheck.status = 'WARNING';
                stuckRecordsCheck.message = stuckRecords + ' records stuck in processing';
            }
            category.items.add(stuckRecordsCheck);
            
            // Check error log size
            ValidationItem errorLogCheck = new ValidationItem('Error Log Management');
            Integer errorLogCount = [
                SELECT COUNT()
                FROM Error_Log__c
                WHERE CreatedDate >= :DateTime.now().addDays(-30)
            ];
            
            if (errorLogCount < 1000) {
                errorLogCheck.status = 'PASSED';
                errorLogCheck.message = 'Error log size is manageable';
            } else {
                errorLogCheck.status = 'WARNING';
                errorLogCheck.message = 'High error log volume (' + errorLogCount + ' in 30 days)';
            }
            category.items.add(errorLogCheck);
            
        } catch (Exception e) {
            category.status = 'ERROR';
            category.errorMessage = e.getMessage();
        }
        
        category.calculateStatus();
        return category;
    }
    
    /**
     * @description Calculates overall validation status
     * @param report The validation report
     * @return Overall status string
     */
    private static String calculateOverallStatus(ValidationReport report) {
        Boolean hasFailures = false;
        Boolean hasWarnings = false;
        Boolean hasErrors = false;
        
        List<ValidationCategory> allCategories = new List<ValidationCategory>{
            report.generalSettingsValidation,
            report.providerValidation,
            report.securityValidation,
            report.integrationValidation,
            report.performanceValidation,
            report.dataIntegrityValidation
        };
        
        for (ValidationCategory category : allCategories) {
            if (category != null) {
                if (category.status == 'FAILED') hasFailures = true;
                if (category.status == 'WARNING') hasWarnings = true;
                if (category.status == 'ERROR') hasErrors = true;
            }
        }
        
        if (hasErrors) return 'ERROR';
        if (hasFailures) return 'FAILED';
        if (hasWarnings) return 'WARNING';
        return 'PASSED';
    }
    
    /**
     * @description Generates recommendations based on validation results
     * @param report The validation report
     * @return List of recommendations
     */
    private static List<String> generateRecommendations(ValidationReport report) {
        List<String> recommendations = new List<String>();
        
        // Check each category for specific recommendations
        if (report.providerValidation != null) {
            for (ValidationItem item : report.providerValidation.items) {
                if (item.errorCode == ERROR_NO_ACTIVE_PROVIDER) {
                    recommendations.add('Activate at least one AI provider to enable processing');
                }
            }
        }
        
        if (report.performanceValidation != null) {
            for (ValidationItem item : report.performanceValidation.items) {
                if (item.status == 'WARNING' && item.name.contains('Async Apex')) {
                    recommendations.add('Consider scheduling bulk processing during off-peak hours');
                }
            }
        }
        
        if (report.dataIntegrityValidation != null) {
            for (ValidationItem item : report.dataIntegrityValidation.items) {
                if (item.status == 'WARNING' && item.name.contains('Orphaned')) {
                    recommendations.add('Run data cleanup job to remove orphaned records');
                }
            }
        }
        
        return recommendations;
    }
    
    /**
     * @description Logs validation execution for audit
     * @param report The validation report
     */
    private static void logValidationExecution(ValidationReport report) {
        MetricsLogger.logEvent('CONFIG_VALIDATION_EXECUTED', new Map<String, Object>{
            'status' => report.overallStatus,
            'isValid' => report.isValid,
            'categoriesChecked' => 6,
            'recommendationCount' => report.recommendations.size(),
            'executedBy' => UserInfo.getUserId(),
            'timestamp' => report.timestamp
        });
    }
    
    // Inner classes
    
    public class ValidationReport {
        @AuraEnabled public DateTime timestamp { get; set; }
        @AuraEnabled public String validatedBy { get; set; }
        @AuraEnabled public String overallStatus { get; set; }
        @AuraEnabled public Boolean isValid { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public ValidationCategory generalSettingsValidation { get; set; }
        @AuraEnabled public ValidationCategory providerValidation { get; set; }
        @AuraEnabled public ValidationCategory securityValidation { get; set; }
        @AuraEnabled public ValidationCategory integrationValidation { get; set; }
        @AuraEnabled public ValidationCategory performanceValidation { get; set; }
        @AuraEnabled public ValidationCategory dataIntegrityValidation { get; set; }
        @AuraEnabled public List<String> recommendations { get; set; }
        
        public ValidationReport() {
            this.recommendations = new List<String>();
        }
    }
    
    public class ValidationCategory {
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public List<ValidationItem> items { get; set; }
        
        public ValidationCategory(String name) {
            this.name = name;
            this.items = new List<ValidationItem>();
            this.status = 'PENDING';
        }
        
        public void calculateStatus() {
            if (items.isEmpty()) {
                status = 'PASSED';
                return;
            }
            
            Boolean hasFailures = false;
            Boolean hasWarnings = false;
            
            for (ValidationItem item : items) {
                if (item.status == 'FAILED') hasFailures = true;
                if (item.status == 'WARNING') hasWarnings = true;
            }
            
            if (hasFailures) {
                status = 'FAILED';
            } else if (hasWarnings) {
                status = 'WARNING';
            } else {
                status = 'PASSED';
            }
        }
    }
    
    public class ValidationItem {
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String errorCode { get; set; }
        
        public ValidationItem(String name) {
            this.name = name;
            this.status = 'PENDING';
        }
    }
}