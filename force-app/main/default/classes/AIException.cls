/**
 * @description Custom exception class for AI-related errors
 * @author RouteLogic Team
 * @date 2025-01-17
 */
@namespaceAccessible
public class AIException extends Exception {
    
    private String errorCode;
    private Map<String, Object> details;
    
    /**
     * @description Constructor with message
     * @param message Error message
     */
    public AIException(String message) {
        this(message, null, null);
    }
    
    /**
     * @description Constructor with message and error code
     * @param message Error message
     * @param errorCode Error code for categorization
     */
    public AIException(String message, String errorCode) {
        this(message, errorCode, null);
    }
    
    /**
     * @description Constructor with message, error code, and details
     * @param message Error message
     * @param errorCode Error code for categorization
     * @param details Additional error details
     */
    public AIException(String message, String errorCode, Map<String, Object> details) {
        this.setMessage(message);
        this.errorCode = errorCode;
        this.details = details;
    }
    
    /**
     * @description Get error code
     * @return Error code
     */
    public String getErrorCode() {
        return this.errorCode;
    }
    
    /**
     * @description Get error details
     * @return Error details map
     */
    public Map<String, Object> getDetails() {
        return this.details;
    }
    
    /**
     * @description Get formatted error message
     * @return Formatted error message
     */
    public String getFormattedMessage() {
        String formattedMessage = this.getMessage();
        
        if (String.isNotBlank(this.errorCode)) {
            formattedMessage = '[' + this.errorCode + '] ' + formattedMessage;
        }
        
        if (this.details != null && !this.details.isEmpty()) {
            formattedMessage += ' | Details: ' + JSON.serialize(this.details);
        }
        
        return formattedMessage;
    }
    
    /**
     * @description Common error codes
     */
    public static final String RATE_LIMIT_ERROR = 'AI_RATE_LIMIT';
    public static final String AUTHENTICATION_ERROR = 'AI_AUTH_ERROR';
    public static final String VALIDATION_ERROR = 'AI_VALIDATION_ERROR';
    public static final String PROVIDER_ERROR = 'AI_PROVIDER_ERROR';
    public static final String CONFIGURATION_ERROR = 'AI_CONFIG_ERROR';
    public static final String SECURITY_ERROR = 'AI_SECURITY_ERROR';
    public static final String PROCESSING_ERROR = 'AI_PROCESSING_ERROR';
    public static final String TIMEOUT_ERROR = 'AI_TIMEOUT_ERROR';
}