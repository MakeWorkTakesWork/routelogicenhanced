/**
 * @description Security provider implementation for Ada.cx
 * @author RouteLogic Team
 * @date 2025-01-17
 */
public with sharing class AdaSecurityProvider implements IAIProviderSecurity {
    
    private static final String PROVIDER_NAME = 'Ada';
    private static final Integer RATE_LIMIT_REQUESTS = 100;
    private static final Integer RATE_LIMIT_WINDOW = 3600; // 1 hour
    
    /**
     * @description Validate Ada webhook signature
     */
    public Boolean validateWebhookSignature(String payload, String signature) {
        if (String.isBlank(payload) || String.isBlank(signature)) {
            return false;
        }
        
        try {
            // Get webhook secret from settings
            String webhookSecret = getWebhookSecret();
            if (String.isBlank(webhookSecret)) {
                throw new SecurityException('Ada webhook secret not configured');
            }
            
            // Generate expected signature
            Blob hmac = Crypto.generateMac(
                'HmacSHA256',
                Blob.valueOf(payload),
                Blob.valueOf(webhookSecret)
            );
            String expectedSignature = EncodingUtil.convertToHex(hmac);
            
            // Timing-safe comparison
            return Crypto.equals(signature, expectedSignature);
            
        } catch (Exception e) {
            ErrorLogService.logError('Ada webhook validation failed', e, signature);
            return false;
        }
    }
    
    /**
     * @description Sanitize request before sending to Ada
     */
    public String sanitizeRequest(String input) {
        if (String.isBlank(input)) {
            return input;
        }
        
        String sanitized = input;
        
        // Remove common PII patterns
        sanitized = removeSocialSecurityNumbers(sanitized);
        sanitized = removeCreditCardNumbers(sanitized);
        sanitized = removePhoneNumbers(sanitized);
        
        // Ada-specific sanitization
        sanitized = removeEmailAddresses(sanitized); // Ada policy
        sanitized = removeIPAddresses(sanitized);
        
        // Remove any potential script injections
        sanitized = removeScriptTags(sanitized);
        
        return sanitized;
    }
    
    /**
     * @description Mask sensitive data for Ada
     */
    public String maskSensitiveData(String input) {
        if (String.isBlank(input)) {
            return input;
        }
        
        String masked = input;
        
        // Mask but preserve format for Ada's NLP
        masked = maskEmails(masked);
        masked = maskPhoneNumbers(masked);
        masked = maskAccountNumbers(masked);
        masked = maskPersonNames(masked); // Uses Ada's entity recognition
        
        return masked;
    }
    
    /**
     * @description Check Ada rate limits
     */
    public Boolean checkRateLimit(String operation) {
        String identifier = 'ada_' + operation;
        return AIRateLimiter.checkRateLimit(identifier, RATE_LIMIT_REQUESTS, RATE_LIMIT_WINDOW);
    }
    
    /**
     * @description Get security headers for Ada API
     */
    public Map<String, String> getSecurityHeaders() {
        Map<String, String> headers = new Map<String, String>();
        
        // CRITICAL FIX: Named Credentials handle Authorization automatically
        // No need to manually add Authorization header
        // Named Credential should be configured as: callout:Ada_API/endpoint
        
        // Ada-specific headers
        headers.put('X-Ada-Client-Id', getClientId());
        headers.put('X-Ada-Timestamp', String.valueOf(DateTime.now().getTime()));
        headers.put('X-Ada-Nonce', generateNonce());
        
        // Request signing
        String signature = generateRequestSignature(headers);
        headers.put('X-Ada-Signature', signature);
        
        // Standard headers
        headers.put('Content-Type', 'application/json');
        headers.put('Accept', 'application/json');
        headers.put('User-Agent', 'RouteLogic/4.0.0 (Salesforce)');
        
        return headers;
    }
    
    /**
     * @description Validate Ada API response
     */
    public Boolean validateResponse(HttpResponse response) {
        if (response == null) {
            return false;
        }
        
        // Check status code
        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            return false;
        }
        
        // Validate response signature
        String responseSignature = response.getHeader('X-Ada-Response-Signature');
        if (String.isNotBlank(responseSignature)) {
            String body = response.getBody();
            return validateResponseSignature(body, responseSignature);
        }
        
        // Validate response format
        try {
            Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            return jsonResponse != null && jsonResponse.containsKey('data');
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
     * @description Get Ada provider configuration
     */
    public Map<String, Object> getProviderConfig() {
        Map<String, Object> config = new Map<String, Object>();
        
        AI_Provider_Settings__c settings = AI_Provider_Settings__c.getInstance();
        
        config.put('endpoint', settings.Ada_Endpoint__c);
        config.put('timeout', 30000); // 30 seconds
        config.put('retryEnabled', true);
        config.put('maxRetries', 3);
        config.put('supportedLanguages', new List<String>{'en', 'fr', 'es', 'de'});
        config.put('features', new Map<String, Boolean>{
            'sentiment' => true,
            'intent' => true,
            'entities' => true,
            'language_detection' => true,
            'conversation_summary' => true
        });
        
        return config;
    }
    
    // Private helper methods
    
    private String getWebhookSecret() {
        // Retrieve from protected custom metadata
        AI_Provider_Settings__mdt settings = AI_Provider_Settings__mdt.getInstance('Ada');
        if (settings == null || String.isBlank(settings.Webhook_Secret__c)) {
            throw new AIException('Ada webhook secret not configured in metadata', AIException.CONFIGURATION_ERROR);
        }
        return settings.Webhook_Secret__c;
    }
    
    @Deprecated
    private String getAccessToken() {
        // CRITICAL FIX: This method is deprecated
        // Named Credentials handle OAuth tokens automatically
        // Usage: HttpRequest.setEndpoint('callout:Ada_API/your/endpoint')
        // The Named Credential 'Ada_API' must be configured in Setup
        throw new AIException('DEPRECATED: Use Named Credentials for API calls. Configure "Ada_API" Named Credential in Setup.', AIException.CONFIGURATION_ERROR);
    }
    
    private String getClientId() {
        AI_Provider_Settings__c settings = AI_Provider_Settings__c.getInstance();
        return settings.Ada_Client_Id__c;
    }
    
    private String generateNonce() {
        return EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-512', 
                Blob.valueOf(String.valueOf(DateTime.now().getTime()) + Crypto.getRandomLong())
            )
        ).substring(0, 16);
    }
    
    private String generateRequestSignature(Map<String, String> headers) {
        // Create signature base string
        List<String> signatureParts = new List<String>{
            headers.get('X-Ada-Client-Id'),
            headers.get('X-Ada-Timestamp'),
            headers.get('X-Ada-Nonce')
        };
        
        String signatureBase = String.join(signatureParts, ':');
        
        // Sign with secret
        Blob hmac = Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(signatureBase),
            Blob.valueOf(getSigningSecret())
        );
        
        return EncodingUtil.convertToHex(hmac);
    }
    
    private String getSigningSecret() {
        // Retrieve from protected custom metadata
        AI_Provider_Settings__mdt settings = AI_Provider_Settings__mdt.getInstance('Ada');
        if (settings == null || String.isBlank(settings.Webhook_Secret__c)) {
            throw new AIException('Ada signing secret not configured in metadata', AIException.CONFIGURATION_ERROR);
        }
        // Using same secret for webhook and signing
        return settings.Webhook_Secret__c;
    }
    
    private Boolean validateResponseSignature(String body, String signature) {
        String expectedSignature = EncodingUtil.convertToHex(
            Crypto.generateMac(
                'HmacSHA256',
                Blob.valueOf(body),
                Blob.valueOf(getSigningSecret())
            )
        );
        
        return Crypto.equals(signature, expectedSignature);
    }
    
    // PII removal methods
    
    private String removeSocialSecurityNumbers(String input) {
        // Pattern: ###-##-#### or #########
        return input.replaceAll('\\b\\d{3}-\\d{2}-\\d{4}\\b', '[SSN_REMOVED]')
                   .replaceAll('\\b\\d{9}\\b', '[SSN_REMOVED]');
    }
    
    private String removeCreditCardNumbers(String input) {
        // Pattern: #### #### #### #### or ################
        return input.replaceAll('\\b\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}\\b', '[CC_REMOVED]');
    }
    
    private String removePhoneNumbers(String input) {
        // Pattern: (###) ###-#### or ###-###-#### or ##########
        return input.replaceAll('\\(\\d{3}\\)\\s?\\d{3}-\\d{4}', '[PHONE_REMOVED]')
                   .replaceAll('\\b\\d{3}-\\d{3}-\\d{4}\\b', '[PHONE_REMOVED]')
                   .replaceAll('\\b\\d{10}\\b', '[PHONE_REMOVED]');
    }
    
    private String removeEmailAddresses(String input) {
        // Ada requires email removal for certain use cases
        return input.replaceAll('[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}', '[EMAIL_REMOVED]');
    }
    
    private String removeIPAddresses(String input) {
        // IPv4 pattern
        return input.replaceAll('\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b', '[IP_REMOVED]');
    }
    
    private String removeScriptTags(String input) {
        return input.replaceAll('<script[^>]*>.*?</script>', '[SCRIPT_REMOVED]')
                   .replaceAll('javascript:', '[JS_REMOVED]');
    }
    
    // Masking methods (preserve format for NLP)
    
    private String maskEmails(String input) {
        // Mask but keep domain for context
        return input.replaceAll('([a-zA-Z0-9._%+-]+)@([a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})', 
                               '[MASKED]@$2');
    }
    
    private String maskPhoneNumbers(String input) {
        // Mask but keep area code
        return input.replaceAll('\\b(\\d{3})[-.\\s]?\\d{3}[-.\\s]?\\d{4}\\b', 
                               '$1-XXX-XXXX');
    }
    
    private String maskAccountNumbers(String input) {
        // Mask but keep last 4 digits
        return input.replaceAll('\\b(\\d{4,12})(\\d{4})\\b', 
                               'XXXX$2');
    }
    
    private String maskPersonNames(String input) {
        // This would integrate with Ada's entity recognition
        // For now, use simple pattern matching
        List<String> commonNames = new List<String>{
            'John', 'Jane', 'Smith', 'Johnson', 'Williams'
            // In production, this would use a more sophisticated approach
        };
        
        String masked = input;
        for (String name : commonNames) {
            masked = masked.replaceAll('\\b' + name + '\\b', '[NAME]');
        }
        
        return masked;
    }
}