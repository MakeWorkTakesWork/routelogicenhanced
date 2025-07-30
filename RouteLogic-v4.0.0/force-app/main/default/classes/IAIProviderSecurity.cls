/**
 * @description Interface for AI provider-specific security implementations
 * @author RouteLogic Team
 * @date 2025-01-17
 */
public interface IAIProviderSecurity {
    
    /**
     * @description Validate webhook signature
     * @param payload The webhook payload
     * @param signature The signature to validate
     * @return Boolean indicating if signature is valid
     */
    Boolean validateWebhookSignature(String payload, String signature);
    
    /**
     * @description Sanitize request before sending to AI provider
     * @param input The input to sanitize
     * @return Sanitized input
     */
    String sanitizeRequest(String input);
    
    /**
     * @description Mask sensitive data in the input
     * @param input The input containing sensitive data
     * @return Input with sensitive data masked
     */
    String maskSensitiveData(String input);
    
    /**
     * @description Check rate limit for specific operation
     * @param operation The operation to check
     * @return Boolean indicating if request is allowed
     */
    Boolean checkRateLimit(String operation);
    
    /**
     * @description Get security headers for API request
     * @return Map of header name to value
     */
    Map<String, String> getSecurityHeaders();
    
    /**
     * @description Validate API response
     * @param response The API response to validate
     * @return Boolean indicating if response is valid
     */
    Boolean validateResponse(HttpResponse response);
    
    /**
     * @description Get provider-specific configuration
     * @return Map of configuration parameters
     */
    Map<String, Object> getProviderConfig();
}