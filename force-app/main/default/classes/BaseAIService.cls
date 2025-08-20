/**
 * @description Abstract base class for all AI services with enhanced security validation
 * @author RouteLogic Security Team
 * @date 2025-01-30
 * @version 4.0.0
 * 
 * This class provides comprehensive input validation, sanitization, and security
 * features that all AI service implementations must inherit.
 */
public abstract class BaseAIService {
    
    // Security constants
    private static final Integer MAX_INPUT_LENGTH = 32768; // 32KB max input
    private static final Set<String> BLOCKED_PATTERNS = new Set<String>{
        '<script', 'javascript:', 'onerror=', 'onclick=', 'onload=',
        'eval(', 'expression(', 'vbscript:', 'data:text/html',
        'UNION SELECT', 'DROP TABLE', 'INSERT INTO', 'DELETE FROM'
    };
    
    // Null byte pattern for detection
    private static final Pattern NULL_BYTE_PATTERN = Pattern.compile('\\x00');
    private static final Pattern CONTROL_CHAR_PATTERN = Pattern.compile('[\\x00-\\x1F\\x7F]');
    
    /**
     * @description Validates and sanitizes input before processing
     * @param input The raw input string
     * @param fieldName The field name for error reporting
     * @return Sanitized input string
     * @throws ValidationException if input is invalid
     */
    protected String validateAndSanitizeInput(String input, String fieldName) {
        // Null check
        if (input == null) {
            return null;
        }
        
        // Length validation
        if (input.length() > MAX_INPUT_LENGTH) {
            throw new ValidationException(
                fieldName + ' exceeds maximum length of ' + MAX_INPUT_LENGTH + ' characters'
            );
        }
        
        // UTF-8 validation
        if (!isValidUTF8(input)) {
            throw new ValidationException(
                fieldName + ' contains invalid UTF-8 characters'
            );
        }
        
        // Null byte detection
        if (containsNullBytes(input)) {
            throw new ValidationException(
                fieldName + ' contains null bytes which are not allowed'
            );
        }
        
        // Check for malicious patterns
        String lowerInput = input.toLowerCase();
        for (String pattern : BLOCKED_PATTERNS) {
            if (lowerInput.contains(pattern)) {
                throw new ValidationException(
                    fieldName + ' contains potentially malicious content'
                );
            }
        }
        
        // Sanitize control characters (except newlines and tabs)
        String sanitized = sanitizeControlCharacters(input);
        
        // Additional HTML encoding for display safety
        sanitized = sanitized.escapeHtml4();
        
        return sanitized;
    }
    
    /**
     * @description Validates UTF-8 encoding
     * @param input String to validate
     * @return True if valid UTF-8
     */
    private Boolean isValidUTF8(String input) {
        try {
            // Attempt to encode and decode as UTF-8
            Blob utf8Blob = Blob.valueOf(input);
            String decoded = utf8Blob.toString();
            return decoded.equals(input);
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
     * @description Checks for null bytes in input
     * @param input String to check
     * @return True if contains null bytes
     */
    private Boolean containsNullBytes(String input) {
        return NULL_BYTE_PATTERN.matcher(input).find();
    }
    
    /**
     * @description Sanitizes control characters while preserving newlines and tabs
     * @param input String to sanitize
     * @return Sanitized string
     */
    private String sanitizeControlCharacters(String input) {
        // Preserve newlines (\n), carriage returns (\r), and tabs (\t)
        List<String> lines = input.split('\n');
        List<String> sanitizedLines = new List<String>();
        
        for (String line : lines) {
            // Remove control characters except \r and \t
            String sanitizedLine = '';
            for (Integer i = 0; i < line.length(); i++) {
                Integer charCode = line.charAt(i);
                if (charCode == 9 || charCode == 13 || charCode >= 32) {
                    sanitizedLine += line.substring(i, i + 1);
                }
            }
            sanitizedLines.add(sanitizedLine);
        }
        
        return String.join(sanitizedLines, '\n');
    }
    
    /**
     * @description Validates a map of inputs
     * @param inputs Map of field names to values
     * @return Map of sanitized inputs
     */
    protected Map<String, String> validateAndSanitizeInputs(Map<String, String> inputs) {
        Map<String, String> sanitized = new Map<String, String>();
        
        for (String fieldName : inputs.keySet()) {
            String value = inputs.get(fieldName);
            sanitized.put(fieldName, validateAndSanitizeInput(value, fieldName));
        }
        
        return sanitized;
    }
    
    /**
     * @description Validates JSON input
     * @param jsonInput JSON string to validate
     * @param fieldName Field name for error reporting
     * @return Parsed JSON object
     */
    protected Map<String, Object> validateAndParseJSON(String jsonInput, String fieldName) {
        // First sanitize the input
        String sanitized = validateAndSanitizeInput(jsonInput, fieldName);
        
        if (String.isBlank(sanitized)) {
            return new Map<String, Object>();
        }
        
        try {
            // Parse JSON with type checking
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(sanitized);
            
            // Recursively validate nested values
            return sanitizeJSONObject(parsed);
            
        } catch (Exception e) {
            throw new ValidationException(
                fieldName + ' contains invalid JSON: ' + e.getMessage()
            );
        }
    }
    
    /**
     * @description Recursively sanitizes JSON object values
     * @param obj Object to sanitize
     * @return Sanitized object
     */
    private Object sanitizeJSONObject(Object obj) {
        if (obj instanceof String) {
            return validateAndSanitizeInput((String) obj, 'JSON value');
        } else if (obj instanceof Map<String, Object>) {
            Map<String, Object> sanitizedMap = new Map<String, Object>();
            Map<String, Object> originalMap = (Map<String, Object>) obj;
            
            for (String key : originalMap.keySet()) {
                // Validate key
                String sanitizedKey = validateAndSanitizeInput(key, 'JSON key');
                // Recursively sanitize value
                sanitizedMap.put(sanitizedKey, sanitizeJSONObject(originalMap.get(key)));
            }
            return sanitizedMap;
        } else if (obj instanceof List<Object>) {
            List<Object> sanitizedList = new List<Object>();
            for (Object item : (List<Object>) obj) {
                sanitizedList.add(sanitizeJSONObject(item));
            }
            return sanitizedList;
        }
        
        // Return primitive types as-is
        return obj;
    }
    
    /**
     * @description Validates email address
     * @param email Email to validate
     * @return True if valid email
     */
    protected Boolean isValidEmail(String email) {
        if (String.isBlank(email)) {
            return false;
        }
        
        // RFC-compliant email regex
        String emailRegex = '^[a-zA-Z0-9._%-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$';
        Pattern emailPattern = Pattern.compile(emailRegex);
        
        return emailPattern.matcher(email).matches() && 
               email.length() <= 254 && // Max email length per RFC
               !email.contains('..') && // No consecutive dots
               !email.startsWith('.') && // No leading dot
               !email.endsWith('.'); // No trailing dot
    }
    
    /**
     * @description Validates URL
     * @param url URL to validate
     * @return True if valid URL
     */
    protected Boolean isValidURL(String url) {
        if (String.isBlank(url)) {
            return false;
        }
        
        try {
            // Check URL format
            if (!url.startsWith('https://') && !url.startsWith('http://')) {
                return false;
            }
            
            // Validate URL structure
            String urlRegex = '^https?://[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}(/.*)?$';
            Pattern urlPattern = Pattern.compile(urlRegex);
            
            return urlPattern.matcher(url).matches();
            
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
     * @description Validates and sanitizes file content
     * @param content File content as base64
     * @param fileName File name
     * @param maxSizeBytes Maximum allowed size
     * @return Validated content
     */
    protected String validateFileContent(String content, String fileName, Integer maxSizeBytes) {
        if (String.isBlank(content)) {
            throw new ValidationException('File content cannot be empty');
        }
        
        // Validate base64 encoding
        try {
            Blob fileBlob = EncodingUtil.base64Decode(content);
            
            // Check file size
            if (fileBlob.size() > maxSizeBytes) {
                throw new ValidationException(
                    'File size exceeds maximum allowed size of ' + 
                    (maxSizeBytes / 1048576) + 'MB'
                );
            }
            
            // Validate file extension
            validateFileExtension(fileName);
            
            return content;
            
        } catch (Exception e) {
            throw new ValidationException('Invalid file content: ' + e.getMessage());
        }
    }
    
    /**
     * @description Validates file extension against whitelist
     * @param fileName File name to validate
     */
    private void validateFileExtension(String fileName) {
        Set<String> allowedExtensions = new Set<String>{
            'txt', 'pdf', 'doc', 'docx', 'png', 'jpg', 'jpeg', 'gif',
            'csv', 'xlsx', 'xls', 'json', 'xml'
        };
        
        String extension = fileName.substringAfterLast('.').toLowerCase();
        
        if (!allowedExtensions.contains(extension)) {
            throw new ValidationException(
                'File type .' + extension + ' is not allowed'
            );
        }
    }
    
    /**
     * @description Logs security-relevant events
     * @param eventType Type of security event
     * @param details Event details
     */
    protected void logSecurityEvent(String eventType, Map<String, Object> details) {
        // This will be implemented by SecurityAuditService
        try {
            SecurityAuditService.logEvent(
                eventType,
                this.getClassName(),
                details
            );
        } catch (Exception e) {
            // Don't let logging failures break the flow
            
        }
    }
    
    /**
     * @description Gets the current class name for logging
     * @return Class name
     */
    private String getClassName() {
        return String.valueOf(this).split(':')[0];
    }
    
    /**
     * @description Abstract method that child classes must implement
     * @param request The validated request object
     * @return Response object
     */
    public abstract Object processRequest(Object request);
    
    /**
     * @description Custom exception for validation errors
     */
    public class ValidationException extends Exception {}
}