/**
 * @description DEPRECATED - Factory class for creating AI provider security implementations
 * @author RouteLogic Team
 * @date 2025-01-17
 * @deprecated This class is deprecated as of RouteLogic v3.3.0. Use AIProviderAdapterFactory instead.
 * 
 * MIGRATION NOTICE:
 * This factory has been replaced by AIProviderAdapterFactory which implements the adapter pattern
 * for better separation of concerns between routing logic and provider-specific implementations.
 * 
 * To migrate:
 * 1. Replace calls to getSecurityProvider() with AIProviderAdapterFactory.getAdapter()
 * 2. Update interface references from IAIProviderSecurity to IAIProviderAdapter
 * 3. Use the new adapter methods for provider-specific operations
 */
@Deprecated
public with sharing class AISecurityProviderFactory {
    
    // Cache providers for performance
    private static Map<String, IAIProviderSecurity> providerCache = new Map<String, IAIProviderSecurity>();
    
    /**
     * @description Get security provider for specified AI provider
     * @param providerName Name of the AI provider
     * @return IAIProviderSecurity implementation
     * @deprecated Use AIProviderAdapterFactory.getAdapter() instead
     */
    @Deprecated
    public static IAIProviderSecurity getSecurityProvider(String providerName) {
        if (String.isBlank(providerName)) {
            throw new AIException('Provider name cannot be blank');
        }
        
        String normalizedName = providerName.toLowerCase();
        
        // Check cache first
        if (providerCache.containsKey(normalizedName)) {
            return providerCache.get(normalizedName);
        }
        
        // Create new provider instance - delegate to adapter factory for new implementations
        IAIProviderSecurity provider;
        
        switch on normalizedName {
            when 'ada' {
                // Legacy support - wrap new adapter in old interface
                provider = new AdaSecurityProviderWrapper();
            }
            when 'intercom' {
                // Legacy support - wrap new adapter in old interface
                provider = new IntercomSecurityProviderWrapper();
            }
            when else {
                throw new AIException('Unknown AI provider: ' + providerName);
            }
        }
        
        // Cache the provider
        providerCache.put(normalizedName, provider);
        
        return provider;
    }
    
    /**
     * @description Clear provider cache (useful for testing)
     */
    @TestVisible
    private static void clearCache() {
        providerCache.clear();
    }
    
    /**
     * @description Get all available providers
     * @return List of provider names
     */
    public static List<String> getAvailableProviders() {
        return new List<String>{'Ada', 'Intercom'};
    }
    
    /**
     * @description Check if provider is supported
     * @param providerName Name of the provider
     * @return Boolean indicating if provider is supported
     */
    public static Boolean isProviderSupported(String providerName) {
        if (String.isBlank(providerName)) {
            return false;
        }
        
        Set<String> supportedProviders = new Set<String>{'ada', 'intercom'};
        return supportedProviders.contains(providerName.toLowerCase());
    }
    
    /**
     * @description Validate webhook signature for any provider
     * @param providerName Name of the provider
     * @param payload Webhook payload
     * @param signature Signature to validate
     * @return Boolean indicating if signature is valid
     */
    public static Boolean validateWebhookSignature(String providerName, String payload, String signature) {
        try {
            IAIProviderSecurity provider = getSecurityProvider(providerName);
            return provider.validateWebhookSignature(payload, signature);
        } catch (Exception e) {
            ErrorLogService.logError('Webhook validation failed', e, providerName);
            return false;
        }
    }
    
    /**
     * @description Sanitize request for any provider
     * @param providerName Name of the provider
     * @param input Input to sanitize
     * @return Sanitized input
     */
    public static String sanitizeRequest(String providerName, String input) {
        try {
            IAIProviderSecurity provider = getSecurityProvider(providerName);
            return provider.sanitizeRequest(input);
        } catch (Exception e) {
            ErrorLogService.logError('Request sanitization failed', e, providerName);
            // Return original input if sanitization fails
            return input;
        }
    }
}