/**
 * @description Adapter implementation for Ada.cx AI provider
 * @author RouteLogic Team
 * @date 2025-01-21
 * @version 2.0
 * 
 * This adapter implements the provider-specific logic for integrating with Ada.cx
 * while maintaining separation from the core routing engine.
 */
public with sharing class AdaAdapter implements IAIProviderAdapter {
    
    private static final String PROVIDER_NAME = 'Ada';
    private static final Integer RATE_LIMIT_REQUESTS = 100;
    private static final Integer RATE_LIMIT_WINDOW = 3600; // 1 hour
    
    /**
     * @description Prepare Ada-specific request based on routing decision
     * @param decision The routing decision from AgnosticRoutingEngine
     * @return Ada-specific request object
     */
    public Object prepareProviderRequest(AgnosticRoutingEngine.RoutingDecision decision) {
        if (decision == null) {
            throw new IllegalArgumentException('Routing decision cannot be null');
        }
        
        AdaHandoffRequest request = new AdaHandoffRequest();
        
        // Map routing decision to Ada's handoff format
        request.caseId = decision.caseId;
        request.targetSkillGroup = mapToAdaSkillGroup(decision.targetSkillGroup);
        request.priority = mapToAdaPriority(decision.suggestedPriority);
        request.escalationReason = decision.escalationReason;
        request.agentSummary = decision.summaryForAgent;
        request.confidenceScore = decision.confidenceScore;
        request.immediateHandoff = decision.requiresImmediateHandoff;
        request.timestamp = decision.routingTimestamp;
        
        // Ada-specific metadata
        request.providerMetadata = new Map<String, Object>{
            'handoff_type' => decision.requiresImmediateHandoff ? 'immediate' : 'queued',
            'routing_confidence' => decision.confidenceScore,
            'escalation_level' => determineEscalationLevel(decision),
            'ada_conversation_id' => generateAdaConversationId(decision.caseId)
        };
        
        return request;
    }
    
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
        
        // Authentication
        // Authorization header is automatically added by Named Credentials
        // headers.put('Authorization', 'Bearer ' + getAccessToken());
        
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
        headers.put('User-Agent', 'RouteLogic/3.3.0 (Salesforce)');
        
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
            'conversation_summary' => true,
            'handoff_orchestration' => true
        });
        
        return config;
    }
    
    // Ada-specific helper methods
    
    /**
     * @description Map RouteLogic skill groups to Ada skill groups
     */
    private String mapToAdaSkillGroup(String routeLogicSkillGroup) {
        Map<String, String> skillGroupMapping = new Map<String, String>{
            'Technical Support - Tier 1' => 'ada_tech_support_l1',
            'Technical Support - Tier 2' => 'ada_tech_support_l2',
            'Enterprise Billing Support' => 'ada_enterprise_billing',
            'Billing Support' => 'ada_billing',
            'Account Management' => 'ada_account_mgmt',
            'Sales Support' => 'ada_sales',
            'Escalation Team' => 'ada_escalation',
            'VIP Support' => 'ada_vip',
            'General Support' => 'ada_general'
        };
        
        return skillGroupMapping.get(routeLogicSkillGroup) != null ? 
               skillGroupMapping.get(routeLogicSkillGroup) : 'ada_general';
    }
    
    /**
     * @description Map RouteLogic priority to Ada priority
     */
    private String mapToAdaPriority(String routeLogicPriority) {
        Map<String, String> priorityMapping = new Map<String, String>{
            'High' => 'urgent',
            'Medium' => 'normal',
            'Low' => 'low'
        };
        
        return priorityMapping.get(routeLogicPriority) != null ? 
               priorityMapping.get(routeLogicPriority) : 'normal';
    }
    
    /**
     * @description Determine Ada escalation level
     */
    private String determineEscalationLevel(AgnosticRoutingEngine.RoutingDecision decision) {
        if (decision.requiresImmediateHandoff) {
            return 'immediate';
        } else if (decision.escalationReason != null) {
            return 'standard';
        }
        return 'none';
    }
    
    /**
     * @description Generate Ada conversation ID
     */
    private String generateAdaConversationId(Id caseId) {
        return 'ada_conv_' + String.valueOf(caseId).substring(0, 15) + '_' + 
               String.valueOf(DateTime.now().getTime()).substring(7);
    }
    
    // Private helper methods (inherited from original implementation)
    
    private String getWebhookSecret() {
        String cacheKey = 'ada_webhook_secret';
        
        // Check Platform Cache first for performance
        Cache.OrgPartition orgCache = Cache.Org.getPartition('RouteLogic');
        if (orgCache != null && orgCache.contains(cacheKey)) {
            return (String) orgCache.get(cacheKey);
        }
        
        // Retrieve from secure storage with multiple fallbacks
        String secret = retrieveSecretSecurely('Ada', 'webhook');
        
        // Cache the secret for performance (5 minutes TTL)
        if (String.isNotBlank(secret) && orgCache != null) {
            orgCache.put(cacheKey, secret, 300);
        }
        
        return secret;
    }
    
    /**
     * @description Retrieve secret securely with multiple fallback options
     */
    private String retrieveSecretSecurely(String provider, String secretType) {
        String secretKey = provider + '_' + secretType;
        
        // Try SecureKeyVault first (most secure)
        try {
            String vaultSecret = SecureKeyVault.getSecret(secretKey);
            if (String.isNotBlank(vaultSecret)) {
                return vaultSecret;
            }
        } catch (Exception e) {
            // Log but continue to fallback
            ErrorLogService.logSecurityWarning('SecureKeyVault retrieval failed for ' + secretKey, e);
        }
        
        // Try Protected Custom Metadata
        try {
            AI_Provider_Settings__mdt settings = AI_Provider_Settings__mdt.getInstance(provider);
            if (settings != null) {
                String metadataSecret = null;
                if (secretType == 'webhook' && String.isNotBlank(settings.Webhook_Secret__c)) {
                    metadataSecret = settings.Webhook_Secret__c;
                } else if (secretType == 'signing' && String.isNotBlank(settings.Signing_Secret__c)) {
                    metadataSecret = settings.Signing_Secret__c;
                }
                
                if (String.isNotBlank(metadataSecret)) {
                    // Decrypt if encrypted
                    if (metadataSecret.startsWith('ENC:')) {
                        return RouteLogicEncryptionUtility.decrypt(metadataSecret.substring(4));
                    }
                    return metadataSecret;
                }
            }
        } catch (Exception e) {
            ErrorLogService.logSecurityWarning('Metadata retrieval failed for ' + secretKey, e);
        }
        
        // Log security event for missing secret
        SecurityAuditService.logSecurityEvent(
            SecurityAuditService.SecurityEventType.MISSING_SECRET,
            new Map<String, Object>{
                'provider' => provider,
                'secretType' => secretType,
                'userId' => UserInfo.getUserId()
            }
        );
        
        throw new AIException(
            'Unable to retrieve ' + secretType + ' secret for provider: ' + provider + 
            '. Please ensure secrets are properly configured in SecureKeyVault or Custom Metadata.',
            AIException.SECURITY_ERROR
        );
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
        // Use the same secure retrieval mechanism
        return retrieveSecretSecurely('Ada', 'signing');
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
        // Use Custom Metadata for flexible PII pattern management
        // This approach allows admins to update patterns without code changes
        List<PII_Pattern__mdt> namePatterns = getPIIPatterns('PersonName');
        
        String masked = input;
        
        // Apply each pattern from metadata
        for (PII_Pattern__mdt pattern : namePatterns) {
            if (pattern.Is_Active__c && String.isNotBlank(pattern.Pattern__c)) {
                String replacement = String.isNotBlank(pattern.Replacement_Pattern__c) ? 
                                   pattern.Replacement_Pattern__c : '[NAME_MASKED]';
                masked = masked.replaceAll(pattern.Pattern__c, replacement);
            }
        }
        
        // If Einstein Platform Services available, use advanced NLP
        if (AIProviderHealthCheckService.isServiceAvailable('Einstein')) {
            try {
                masked = applyEinsteinEntityRecognition(masked, 'PERSON');
            } catch (Exception e) {
                // Log but don't fail - fallback to pattern matching
                ErrorLogService.logWarning('Einstein entity recognition unavailable', e);
            }
        }
        
        return masked;
    }
    
    // Cache PII patterns for performance
    private static Map<String, List<PII_Pattern__mdt>> piiPatternCache = new Map<String, List<PII_Pattern__mdt>>();
    
    private List<PII_Pattern__mdt> getPIIPatterns(String patternType) {
        if (piiPatternCache.containsKey(patternType)) {
            return piiPatternCache.get(patternType);
        }
        
        List<PII_Pattern__mdt> patterns = [
            SELECT Pattern__c, Replacement_Pattern__c, Pattern_Type__c, 
                   Is_Active__c, Priority__c, Description__c
            FROM PII_Pattern__mdt
            WHERE Pattern_Type__c = :patternType
            AND Is_Active__c = true
            WITH SECURITY_ENFORCED
            ORDER BY Priority__c DESC
            LIMIT 100
        ];
        
        piiPatternCache.put(patternType, patterns);
        return patterns;
    }
    
    private String applyEinsteinEntityRecognition(String text, String entityType) {
        // This would integrate with Einstein Language APIs
        // Placeholder for actual implementation
        return text;
    }
    
    // Inner classes
    
    /**
     * @description Ada-specific handoff request structure
     */
    public class AdaHandoffRequest {
        public Id caseId;
        public String targetSkillGroup;
        public String priority;
        public String escalationReason;
        public String agentSummary;
        public Integer confidenceScore;
        public Boolean immediateHandoff;
        public DateTime timestamp;
        public Map<String, Object> providerMetadata;
    }
}

