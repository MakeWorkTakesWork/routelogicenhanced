/**
 * @description Security provider implementation for Intercom Fin.ai
 * @author RouteLogic Team
 * @date 2025-01-17
 */
public with sharing class IntercomSecurityProvider implements IAIProviderSecurity {
    
    private static final String PROVIDER_NAME = 'Intercom';
    private static final Integer RATE_LIMIT_REQUESTS = 83;
    private static final Integer RATE_LIMIT_WINDOW = 10; // 10 seconds (Intercom limit: 83 req/10s)
    
    /**
     * @description Validate Intercom webhook signature
     */
    public Boolean validateWebhookSignature(String payload, String signature) {
        if (String.isBlank(payload) || String.isBlank(signature)) {
            return false;
        }
        
        try {
            // Get webhook secret from settings
            String webhookSecret = getWebhookSecret();
            if (String.isBlank(webhookSecret)) {
                throw new SecurityException('Intercom webhook secret not configured');
            }
            
            // Intercom uses sha256= prefix
            if (!signature.startsWith('sha256=')) {
                return false;
            }
            
            String providedHash = signature.substring(7); // Remove 'sha256=' prefix
            
            // Generate expected signature
            Blob hmac = Crypto.generateMac(
                'HmacSHA256',
                Blob.valueOf(payload),
                Blob.valueOf(webhookSecret)
            );
            String expectedHash = EncodingUtil.convertToHex(hmac);
            
            // Timing-safe comparison
            return RouteLogicSecurityUtils.timingSafeEquals(providedHash, expectedHash);
            
        } catch (Exception e) {
            ErrorLogService.logError('Intercom webhook validation failed', e, signature);
            return false;
        }
    }
    
    /**
     * @description Sanitize request before sending to Intercom
     */
    public String sanitizeRequest(String input) {
        if (String.isBlank(input)) {
            return input;
        }
        
        String sanitized = input;
        
        // Remove PII based on Intercom's data policies
        sanitized = removeSocialSecurityNumbers(sanitized);
        sanitized = removeCreditCardNumbers(sanitized);
        sanitized = removeHealthInformation(sanitized); // HIPAA compliance
        
        // Intercom-specific sanitization
        sanitized = sanitizeForIntercomMessenger(sanitized);
        sanitized = removeInternalUrls(sanitized);
        
        // Remove any potential XSS attempts
        sanitized = removeScriptContent(sanitized);
        
        return sanitized;
    }
    
    /**
     * @description Mask sensitive data for Intercom
     */
    public String maskSensitiveData(String input) {
        if (String.isBlank(input)) {
            return input;
        }
        
        String masked = input;
        
        // Intercom-specific masking rules
        masked = maskUserIds(masked);
        masked = maskApiKeys(masked);
        masked = maskInvoiceNumbers(masked);
        masked = maskTrackingNumbers(masked);
        
        // Standard masking
        masked = maskEmails(masked, true); // Keep domain for Intercom routing
        masked = maskPhoneNumbers(masked);
        
        return masked;
    }
    
    /**
     * @description Check Intercom rate limits
     */
    public Boolean checkRateLimit(String operation) {
        // Intercom has different rate limits for different operations
        Integer limit = getRateLimitForOperation(operation);
        Integer window = getRateWindowForOperation(operation);
        
        String identifier = 'intercom_' + operation;
        return AIRateLimiter.checkRateLimit(identifier, limit, window);
    }
    
    /**
     * @description Get security headers for Intercom API
     */
    public Map<String, String> getSecurityHeaders() {
        Map<String, String> headers = new Map<String, String>();
        
        // Authentication
        // Authorization header is automatically added by Named Credentials
        // headers.put('Authorization', 'Bearer ' + getAccessToken());
        
        // Intercom-specific headers
        headers.put('Intercom-Version', '2.10'); // API version
        headers.put('Accept', 'application/json');
        headers.put('Content-Type', 'application/json');
        
        // Request ID for tracking
        String requestId = generateRequestId();
        headers.put('X-Request-ID', requestId);
        
        // HMAC signature for request integrity
        String timestamp = String.valueOf(DateTime.now().getTime());
        headers.put('X-Intercom-Timestamp', timestamp);
        
        // Add signature if request body exists
        if (hasRequestBody()) {
            String signature = generateRequestSignature(getRequestBody(), timestamp);
            headers.put('X-Hub-Signature-256', 'sha256=' + signature);
        }
        
        // User agent
        headers.put('User-Agent', 'RouteLogic/3.1.0 (Salesforce; Intercom-Integration)');
        
        return headers;
    }
    
    /**
     * @description Validate Intercom API response
     */
    public Boolean validateResponse(HttpResponse response) {
        if (response == null) {
            return false;
        }
        
        // Check status code
        Integer statusCode = response.getStatusCode();
        if (statusCode < 200 || statusCode >= 300) {
            logIntercomError(response);
            return false;
        }
        
        // Validate rate limit headers
        if (!validateRateLimitHeaders(response)) {
            return false;
        }
        
        // Validate response format
        try {
            String contentType = response.getHeader('Content-Type');
            if (contentType == null || !contentType.contains('application/json')) {
                return false;
            }
            
            // Parse and validate JSON structure
            Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            
            // Check for error response
            if (jsonResponse.containsKey('errors')) {
                logIntercomErrors(jsonResponse);
                return false;
            }
            
            return true;
            
        } catch (Exception e) {
            ErrorLogService.logError('Intercom response validation failed', e, response.getBody());
            return false;
        }
    }
    
    /**
     * @description Get Intercom provider configuration
     */
    public Map<String, Object> getProviderConfig() {
        Map<String, Object> config = new Map<String, Object>();
        
        AI_Provider_Settings__mdt settings = AI_Provider_Settings__mdt.getInstance('Intercom');
        
        config.put('endpoint', settings.Endpoint__c);
        config.put('timeout', 30000); // 30 seconds
        config.put('retryEnabled', true);
        config.put('maxRetries', 3);
        config.put('backoffMultiplier', 2);
        
        // Intercom-specific features
        config.put('features', new Map<String, Boolean>{
            'fin_ai_agent' => true,
            'resolution_bot' => true,
            'custom_actions' => true,
            'conversation_routing' => true,
            'multilingual' => true,
            'custom_attributes' => true
        });
        
        // Supported operations
        config.put('operations', new List<String>{
            'conversation.create',
            'conversation.reply',
            'conversation.close',
            'contact.update',
            'event.track',
            'article.search'
        });
        
        return config;
    }
    
    // Private helper methods
    
    private String getWebhookSecret() {
        // Retrieve from protected custom metadata
        AI_Provider_Settings__mdt settings = AI_Provider_Settings__mdt.getInstance('Intercom');
        if (settings == null || String.isBlank(settings.Webhook_Secret__c)) {
            throw new AIException('Intercom webhook secret not configured in metadata', AIException.CONFIGURATION_ERROR);
        }
        return settings.Webhook_Secret__c;
    }
    
    private String getAccessToken() {
        // Using Named Credentials for OAuth - token is handled automatically
        // This method is no longer needed when using Named Credentials
        throw new AIException('Use Named Credentials for API calls', AIException.CONFIGURATION_ERROR);
    }
    
    private String generateRequestId() {
        return 'rl_' + EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-512', 
                Blob.valueOf(UserInfo.getOrganizationId() + DateTime.now().getTime() + Crypto.getRandomLong())
            )
        ).substring(0, 16);
    }
    
    private String generateRequestSignature(String body, String timestamp) {
        String signatureBase = timestamp + '.' + body;
        
        Blob hmac = Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(signatureBase),
            Blob.valueOf(getAppSecret())
        );
        
        return EncodingUtil.convertToHex(hmac);
    }
    
    private String getAppSecret() {
        // Retrieve from protected custom metadata
        AI_Provider_Settings__mdt settings = AI_Provider_Settings__mdt.getInstance('Intercom');
        if (settings == null || String.isBlank(settings.App_Secret__c)) {
            throw new AIException('Intercom app secret not configured in metadata', AIException.CONFIGURATION_ERROR);
        }
        return settings.App_Secret__c;
    }
    
    private Boolean hasRequestBody() {
        // This would check if current request has a body
        // Implementation depends on context
        return false;
    }
    
    private String getRequestBody() {
        // This would return current request body
        // Implementation depends on context
        return '';
    }
    
    private Integer getRateLimitForOperation(String operation) {
        // Intercom has different rate limits per endpoint
        Map<String, Integer> operationLimits = new Map<String, Integer>{
            'conversation.create' => 83,
            'conversation.reply' => 83,
            'contact.search' => 50,
            'bulk.operations' => 10
        };
        
        return operationLimits.get(operation) != null ? 
               operationLimits.get(operation) : RATE_LIMIT_REQUESTS;
    }
    
    private Integer getRateWindowForOperation(String operation) {
        // Most Intercom endpoints use 10 second windows
        // Bulk operations use 60 second windows
        return operation.contains('bulk') ? 60 : RATE_LIMIT_WINDOW;
    }
    
    private Boolean validateRateLimitHeaders(HttpResponse response) {
        String remaining = response.getHeader('X-RateLimit-Remaining');
        String limit = response.getHeader('X-RateLimit-Limit');
        
        if (remaining != null && Integer.valueOf(remaining) <= 5) {
            // Log warning when approaching rate limit
        }
        
        return true;
    }
    
    private void logIntercomError(HttpResponse response) {
        Map<String, Object> errorDetails = new Map<String, Object>{
            'statusCode' => response.getStatusCode(),
            'status' => response.getStatus(),
            'headers' => response.getHeaderKeys(),
            'body' => response.getBody()
        };
        
        ErrorLogService.logError(
            'Intercom API Error',
            null,
            JSON.serialize(errorDetails)
        );
    }
    
    private void logIntercomErrors(Map<String, Object> jsonResponse) {
        List<Object> errors = (List<Object>) jsonResponse.get('errors');
        for (Object error : errors) {
            Map<String, Object> errorMap = (Map<String, Object>) error;
            ErrorLogService.logError(
                'Intercom API Error: ' + errorMap.get('code'),
                null,
                (String) errorMap.get('message')
            );
        }
    }
    
    // Sanitization methods
    
    private String removeSocialSecurityNumbers(String input) {
        return input.replaceAll('\\b\\d{3}-\\d{2}-\\d{4}\\b', '[SSN_REMOVED]')
                   .replaceAll('\\b\\d{9}\\b', '[SSN_REMOVED]');
    }
    
    private String removeCreditCardNumbers(String input) {
        // Remove various credit card formats
        return input.replaceAll('\\b\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}\\b', '[CC_REMOVED]')
                   .replaceAll('\\b\\d{15,16}\\b', '[CC_REMOVED]');
    }
    
    private String removeHealthInformation(String input) {
        // Remove potential PHI/health information
        List<String> healthKeywords = new List<String>{
            'diagnosis', 'prescription', 'medical', 'health condition'
        };
        
        String sanitized = input;
        for (String keyword : healthKeywords) {
            // Remove sentences containing health keywords
            sanitized = sanitized.replaceAll(
                '[^.!?]*\\b' + keyword + '\\b[^.!?]*[.!?]', 
                '[HEALTH_INFO_REMOVED]'
            );
        }
        
        return sanitized;
    }
    
    private String sanitizeForIntercomMessenger(String input) {
        // Remove Intercom-specific sensitive data
        return input.replaceAll('intercom_user_id=[^\\s]+', '[USER_ID_REMOVED]')
                   .replaceAll('intercom_session=[^\\s]+', '[SESSION_REMOVED]');
    }
    
    private String removeInternalUrls(String input) {
        // Remove internal Salesforce URLs
        return input.replaceAll('https?://[^\\s]*\\.salesforce\\.com[^\\s]*', '[INTERNAL_URL]')
                   .replaceAll('https?://[^\\s]*\\.force\\.com[^\\s]*', '[INTERNAL_URL]');
    }
    
    private String removeScriptContent(String input) {
        return input.replaceAll('<script[^>]*>.*?</script>', '')
                   .replaceAll('on\\w+\\s*=\\s*["\'][^"\']*["\']', '');
    }
    
    // Masking methods
    
    private String maskUserIds(String input) {
        // Mask Salesforce IDs but keep prefix for type identification
        return input.replaceAll('\\b([0-9a-zA-Z]{3})[0-9a-zA-Z]{12,15}\\b', '$1XXXXXXXXXXXX');
    }
    
    private String maskApiKeys(String input) {
        // Mask potential API keys
        return input.replaceAll('\\b[a-fA-F0-9]{32,}\\b', '[API_KEY_MASKED]')
                   .replaceAll('\\bsk_[a-zA-Z0-9]{20,}\\b', 'sk_[MASKED]');
    }
    
    private String maskInvoiceNumbers(String input) {
        // Mask invoice numbers but keep prefix
        return input.replaceAll('\\b(INV-?)\\d{4,}\\b', '$1XXXX');
    }
    
    private String maskTrackingNumbers(String input) {
        // Mask shipping tracking numbers
        return input.replaceAll('\\b1Z[0-9A-Z]{16}\\b', '1Z[TRACKING_MASKED]') // UPS
                   .replaceAll('\\b\\d{20,22}\\b', '[TRACKING_MASKED]'); // FedEx
    }
    
    private String maskEmails(String input, Boolean keepDomain) {
        if (keepDomain) {
            // Keep domain for Intercom routing rules
            return input.replaceAll(
                '([a-zA-Z0-9._%+-]+)@([a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})', 
                '[EMAIL]@$2'
            );
        } else {
            return input.replaceAll(
                '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}', 
                '[EMAIL_MASKED]'
            );
        }
    }
    
    private String maskPhoneNumbers(String input) {
        // Mask but keep country/area code for routing
        return input.replaceAll(
            '\\+?(\\d{1,3})[-.\\s]?(\\d{3})[-.\\s]?\\d{3}[-.\\s]?\\d{4}', 
            '+$1 $2-XXX-XXXX'
        );
    }
}