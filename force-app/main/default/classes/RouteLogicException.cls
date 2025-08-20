/**
 * @description Base exception class for all RouteLogic-specific errors
 * Provides structured error handling throughout the application
 * @author RouteLogic Team
 * @date 2025-01-31
 * @group Exception Handling
 */
public virtual class RouteLogicException extends Exception {
    
    private String errorCode;
    private Map<String, Object> errorDetails;
    
    /**
     * @description Constructor with message only
     * @param message The error message
     */
    public RouteLogicException(String message) {
        this(message, null, null);
    }
    
    /**
     * @description Constructor with message and error code
     * @param message The error message
     * @param errorCode The error code for categorization
     */
    public RouteLogicException(String message, String errorCode) {
        this(message, errorCode, null);
    }
    
    /**
     * @description Constructor with message, error code, and details
     * @param message The error message
     * @param errorCode The error code for categorization
     * @param errorDetails Additional error details
     */
    public RouteLogicException(String message, String errorCode, Map<String, Object> errorDetails) {
        this.setMessage(message);
        this.errorCode = errorCode;
        this.errorDetails = errorDetails != null ? errorDetails : new Map<String, Object>();
    }
    
    /**
     * @description Get the error code
     * @return The error code
     */
    public String getErrorCode() {
        return this.errorCode;
    }
    
    /**
     * @description Get error details
     * @return Map of error details
     */
    public Map<String, Object> getErrorDetails() {
        return this.errorDetails;
    }
    
    /**
     * @description Add error detail
     * @param key The detail key
     * @param value The detail value
     */
    public void addErrorDetail(String key, Object value) {
        if (this.errorDetails == null) {
            this.errorDetails = new Map<String, Object>();
        }
        this.errorDetails.put(key, value);
    }
    
    /**
     * @description Get formatted error message for logging
     * @return Formatted error message
     */
    public String getFormattedMessage() {
        String formatted = this.getMessage();
        if (String.isNotBlank(this.errorCode)) {
            formatted = '[' + this.errorCode + '] ' + formatted;
        }
        if (!this.errorDetails.isEmpty()) {
            formatted += ' | Details: ' + JSON.serialize(this.errorDetails);
        }
        return formatted;
    }
}

/**
 * @description Exception for security-related errors
 */
public class RouteLogicSecurityException extends RouteLogicException {
    public RouteLogicSecurityException(String message) {
        super(message, 'SECURITY_ERROR');
    }
    
    public RouteLogicSecurityException(String message, Map<String, Object> details) {
        super(message, 'SECURITY_ERROR', details);
    }
}

/**
 * @description Exception for configuration-related errors
 */
public class RouteLogicConfigurationException extends RouteLogicException {
    public RouteLogicConfigurationException(String message) {
        super(message, 'CONFIG_ERROR');
    }
    
    public RouteLogicConfigurationException(String message, Map<String, Object> details) {
        super(message, 'CONFIG_ERROR', details);
    }
}

/**
 * @description Exception for integration-related errors
 */
public class RouteLogicIntegrationException extends RouteLogicException {
    public RouteLogicIntegrationException(String message) {
        super(message, 'INTEGRATION_ERROR');
    }
    
    public RouteLogicIntegrationException(String message, Map<String, Object> details) {
        super(message, 'INTEGRATION_ERROR', details);
    }
}

/**
 * @description Exception for validation errors
 */
public class RouteLogicValidationException extends RouteLogicException {
    public RouteLogicValidationException(String message) {
        super(message, 'VALIDATION_ERROR');
    }
    
    public RouteLogicValidationException(String message, Map<String, Object> details) {
        super(message, 'VALIDATION_ERROR', details);
    }
}

/**
 * @description Exception for rate limiting errors
 */
public class RouteLogicRateLimitException extends RouteLogicException {
    private Integer retryAfterSeconds;
    
    public RouteLogicRateLimitException(String message, Integer retryAfterSeconds) {
        super(message, 'RATE_LIMIT_ERROR');
        this.retryAfterSeconds = retryAfterSeconds;
        this.addErrorDetail('retryAfterSeconds', retryAfterSeconds);
    }
    
    public Integer getRetryAfterSeconds() {
        return this.retryAfterSeconds;
    }
}

/**
 * @description Exception for bulk processing errors
 */
public class RouteLogicBulkProcessingException extends RouteLogicException {
    private List<Database.Error> dmlErrors;
    
    public RouteLogicBulkProcessingException(String message, List<Database.Error> dmlErrors) {
        super(message, 'BULK_PROCESSING_ERROR');
        this.dmlErrors = dmlErrors;
        if (dmlErrors != null && !dmlErrors.isEmpty()) {
            this.addErrorDetail('errorCount', dmlErrors.size());
            this.addErrorDetail('firstError', dmlErrors[0].getMessage());
        }
    }
    
    public List<Database.Error> getDmlErrors() {
        return this.dmlErrors;
    }
}