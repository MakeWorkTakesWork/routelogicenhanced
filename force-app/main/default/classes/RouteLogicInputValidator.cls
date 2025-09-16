/**
 * @description Centralized input validation utility for RouteLogic application
 * Provides comprehensive validation methods for all input types
 * @author RouteLogic Team
 * @date 2025-01-31
 * @group Best Practices
 */
public with sharing class RouteLogicInputValidator {
    
    // Validation result class
    public class ValidationResult {
        public Boolean isValid { get; set; }
        public String errorMessage { get; set; }
        
        public ValidationResult(Boolean isValid, String errorMessage) {
            this.isValid = isValid;
            this.errorMessage = errorMessage;
        }
    }
    
    /**
     * @description Validates string input with various checks
     * @param input The string to validate
     * @param fieldName The field name for error messages
     * @param maxLength Maximum allowed length
     * @param required Whether the field is required
     * @return ValidationResult indicating if input is valid
     */
    public static ValidationResult validateString(String input, String fieldName, Integer maxLength, Boolean required) {
        // Check required field
        if (required && String.isBlank(input)) {
            return new ValidationResult(false, fieldName + ' is required and cannot be empty');
        }
        
        // Check null for optional fields
        if (!required && input == null) {
            return new ValidationResult(true, null);
        }
        
        // Check length
        if (input != null && maxLength != null && input.length() > maxLength) {
            return new ValidationResult(false, fieldName + ' cannot exceed ' + maxLength + ' characters');
        }
        
        return new ValidationResult(true, null);
    }
    
    /**
     * @description Validates email format
     * @param email The email to validate
     * @return ValidationResult indicating if email is valid
     */
    public static ValidationResult validateEmail(String email) {
        if (String.isBlank(email)) {
            return new ValidationResult(false, 'Email is required');
        }
        
        // Email regex pattern
        String emailRegex = '^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$';
        Pattern emailPattern = Pattern.compile(emailRegex);
        Matcher matcher = emailPattern.matcher(email);
        
        if (!matcher.matches()) {
            return new ValidationResult(false, 'Invalid email format');
        }
        
        return new ValidationResult(true, null);
    }
    
    /**
     * @description Validates Salesforce record ID
     * @param recordId The ID to validate
     * @param objectType Expected object type
     * @return ValidationResult indicating if ID is valid
     */
    public static ValidationResult validateId(Id recordId, String objectType) {
        if (recordId == null) {
            return new ValidationResult(false, 'Record ID is required');
        }
        
        // Verify object type matches
        Schema.SObjectType actualType = recordId.getSObjectType();
        if (actualType == null) {
            return new ValidationResult(false, 'Invalid record ID');
        }
        
        if (objectType != null && actualType.getDescribe().getName() != objectType) {
            return new ValidationResult(false, 'ID must be for ' + objectType + ' object');
        }
        
        return new ValidationResult(true, null);
    }
    
    /**
     * @description Validates numeric input
     * @param value The number to validate
     * @param fieldName The field name for error messages
     * @param minValue Minimum allowed value
     * @param maxValue Maximum allowed value
     * @return ValidationResult indicating if number is valid
     */
    public static ValidationResult validateNumber(Decimal value, String fieldName, Decimal minValue, Decimal maxValue) {
        if (value == null) {
            return new ValidationResult(false, fieldName + ' is required');
        }
        
        if (minValue != null && value < minValue) {
            return new ValidationResult(false, fieldName + ' must be at least ' + minValue);
        }
        
        if (maxValue != null && value > maxValue) {
            return new ValidationResult(false, fieldName + ' cannot exceed ' + maxValue);
        }
        
        return new ValidationResult(true, null);
    }
    
    /**
     * @description Validates date input
     * @param dateValue The date to validate
     * @param fieldName The field name for error messages
     * @param allowPast Whether past dates are allowed
     * @param allowFuture Whether future dates are allowed
     * @return ValidationResult indicating if date is valid
     */
    public static ValidationResult validateDate(Date dateValue, String fieldName, Boolean allowPast, Boolean allowFuture) {
        if (dateValue == null) {
            return new ValidationResult(false, fieldName + ' is required');
        }
        
        Date today = Date.today();
        
        if (!allowPast && dateValue < today) {
            return new ValidationResult(false, fieldName + ' cannot be in the past');
        }
        
        if (!allowFuture && dateValue > today) {
            return new ValidationResult(false, fieldName + ' cannot be in the future');
        }
        
        return new ValidationResult(true, null);
    }
    
    /**
     * @description Sanitizes user input to prevent injection attacks
     * @param input The string to sanitize
     * @return Sanitized string safe for use in queries
     */
    public static String sanitizeInput(String input) {
        if (String.isBlank(input)) {
            return input;
        }
        return String.escapeSingleQuotes(input);
    }
    
    /**
     * @description Validates collection size
     * @param collection The collection to validate
     * @param fieldName The field name for error messages
     * @param maxSize Maximum allowed size
     * @return ValidationResult indicating if collection size is valid
     */
    public static ValidationResult validateCollectionSize(List<Object> collection, String fieldName, Integer maxSize) {
        if (collection == null) {
            return new ValidationResult(false, fieldName + ' cannot be null');
        }
        
        if (collection.isEmpty()) {
            return new ValidationResult(false, fieldName + ' cannot be empty');
        }
        
        if (maxSize != null && collection.size() > maxSize) {
            return new ValidationResult(false, fieldName + ' cannot contain more than ' + maxSize + ' items');
        }
        
        return new ValidationResult(true, null);
    }
    
    /**
     * @description Validates URL format
     * @param url The URL to validate
     * @return ValidationResult indicating if URL is valid
     */
    public static ValidationResult validateUrl(String url) {
        if (String.isBlank(url)) {
            return new ValidationResult(false, 'URL is required');
        }
        
        // URL must start with http:// or https://
        if (!url.startsWith('http://') && !url.startsWith('https://')) {
            return new ValidationResult(false, 'URL must start with http:// or https://');
        }
        
        // Basic URL pattern validation
        String urlRegex = '^https?://[\\w\\-]+(\\.[\\w\\-]+)+[/#?]?.*$';
        Pattern urlPattern = Pattern.compile(urlRegex);
        Matcher matcher = urlPattern.matcher(url);
        
        if (!matcher.matches()) {
            return new ValidationResult(false, 'Invalid URL format');
        }
        
        return new ValidationResult(true, null);
    }
    
    /**
     * @description Validates phone number format
     * @param phone The phone number to validate
     * @return ValidationResult indicating if phone is valid
     */
    public static ValidationResult validatePhone(String phone) {
        if (String.isBlank(phone)) {
            return new ValidationResult(false, 'Phone number is required');
        }
        
        // Remove common formatting characters
        String cleanPhone = phone.replaceAll('[\\s\\-\\(\\)\\.]', '');
        
        // Check if it contains only digits and optional + at start
        String phoneRegex = '^\\+?\\d{10,15}$';
        Pattern phonePattern = Pattern.compile(phoneRegex);
        Matcher matcher = phonePattern.matcher(cleanPhone);
        
        if (!matcher.matches()) {
            return new ValidationResult(false, 'Invalid phone number format');
        }
        
        return new ValidationResult(true, null);
    }
}