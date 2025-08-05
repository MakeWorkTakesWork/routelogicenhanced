/**
 * @description Security utility class for RouteLogic Enhanced v4.0.0
 * @author RouteLogic Team
 * @date 2025-01-21
 * @version 4.0.0
 * 
 * This class provides comprehensive security utilities including:
 * - Field-Level Security validation
 * - Input sanitization and XSS prevention
 * - Cryptographic utilities
 * - Access control validation
 */
public with sharing class RouteLogicSecurityUtils {
    
    // Security constants
    private static final String XSS_PATTERN = '(?i)<script[^>]*>.*?</script>|javascript:|on\\w+\\s*=';
    private static final String SQL_INJECTION_PATTERN = '(?i)(union|select|insert|update|delete|drop|create|alter|exec|execute)\\s';
    private static final Integer MAX_INPUT_LENGTH = 32768; // 32KB max input
    
    // Cache for field accessibility checks
    private static Map<String, Map<String, Boolean>> fieldAccessibilityCache = new Map<String, Map<String, Boolean>>();
    
    /**
     * @description Validate field-level security for object fields
     * @param objectName The SObject API name
     * @param fieldNames Set of field API names to validate
     * @param accessType The type of access (READ, CREATE, UPDATE)
     * @return Map of field name to accessibility boolean
     * @throws SecurityException if any field is not accessible
     */
    public static Map<String, Boolean> validateFieldAccess(String objectName, Set<String> fieldNames, AccessType accessType) {
        if (String.isBlank(objectName) || fieldNames == null || fieldNames.isEmpty()) {
            throw new IllegalArgumentException('Object name and field names cannot be null or empty');
        }
        
        Map<String, Boolean> accessibilityMap = new Map<String, Boolean>();
        String cacheKey = objectName + '_' + accessType.name();
        
        // Check cache first
        if (fieldAccessibilityCache.containsKey(cacheKey)) {
            Map<String, Boolean> cachedAccess = fieldAccessibilityCache.get(cacheKey);
            for (String fieldName : fieldNames) {
                if (cachedAccess.containsKey(fieldName)) {
                    accessibilityMap.put(fieldName, cachedAccess.get(fieldName));
                }
            }
            
            // If all fields found in cache, return
            if (accessibilityMap.size() == fieldNames.size()) {
                return accessibilityMap;
            }
        }
        
        try {
            // Get object describe
            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
            if (objectType == null) {
                throw new SecurityException('Object not found or not accessible: ' + objectName);
            }
            
            Schema.DescribeSObjectResult objectDescribe = objectType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();
            
            // Validate each field
            for (String fieldName : fieldNames) {
                Schema.SObjectField field = fieldMap.get(fieldName);
                if (field == null) {
                    accessibilityMap.put(fieldName, false);
                    continue;
                }
                
                Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
                Boolean isAccessible = false;
                
                switch on accessType {
                    when READABLE {
                        isAccessible = fieldDescribe.isAccessible();
                    }
                    when CREATABLE {
                        isAccessible = fieldDescribe.isCreateable();
                    }
                    when UPDATABLE {
                        isAccessible = fieldDescribe.isUpdateable();
                    }
                }
                
                accessibilityMap.put(fieldName, isAccessible);
                
                // Cache the result
                if (!fieldAccessibilityCache.containsKey(cacheKey)) {
                    fieldAccessibilityCache.put(cacheKey, new Map<String, Boolean>());
                }
                fieldAccessibilityCache.get(cacheKey).put(fieldName, isAccessible);
            }
            
            // Check for any inaccessible fields
            List<String> inaccessibleFields = new List<String>();
            for (String fieldName : fieldNames) {
                if (!accessibilityMap.get(fieldName)) {
                    inaccessibleFields.add(fieldName);
                }
            }
            
            if (!inaccessibleFields.isEmpty()) {
                throw new SecurityException('Insufficient permissions for fields: ' + String.join(inaccessibleFields, ', ') + 
                                          ' on object: ' + objectName + ' for access type: ' + accessType.name());
            }
            
            return accessibilityMap;
            
        } catch (Exception e) {
            if (e instanceof SecurityException) {
                throw e;
            }
            throw new SecurityException('Field access validation failed: ' + e.getMessage());
        }
    }
    
    /**
     * @description Sanitize input to prevent XSS and injection attacks
     * @param input The input string to sanitize
     * @return Sanitized input string
     */
    public static String sanitizeInput(String input) {
        if (String.isBlank(input)) {
            return input;
        }
        
        // Check input length
        if (input.length() > MAX_INPUT_LENGTH) {
            throw new SecurityException('Input exceeds maximum allowed length: ' + MAX_INPUT_LENGTH);
        }
        
        String sanitized = input;
        
        // Remove potential XSS patterns
        sanitized = sanitized.replaceAll(XSS_PATTERN, '');
        
        // Remove potential SQL injection patterns
        sanitized = sanitized.replaceAll(SQL_INJECTION_PATTERN, '');
        
        // HTML encode special characters
        sanitized = sanitized.replace('&', '&amp;')
                            .replace('<', '&lt;')
                            .replace('>', '&gt;')
                            .replace('"', '&quot;')
                            .replace('\'', '&#x27;')
                            .replace('/', '&#x2F;');
        
        return sanitized;
    }
    
    /**
     * @description Validate and sanitize SOQL query parameters
     * @param queryParams Map of parameter names to values
     * @return Map of sanitized parameters
     */
    public static Map<String, Object> sanitizeQueryParameters(Map<String, Object> queryParams) {
        if (queryParams == null || queryParams.isEmpty()) {
            return queryParams;
        }
        
        Map<String, Object> sanitizedParams = new Map<String, Object>();
        
        for (String paramName : queryParams.keySet()) {
            Object paramValue = queryParams.get(paramName);
            
            if (paramValue instanceof String) {
                sanitizedParams.put(paramName, sanitizeInput((String) paramValue));
            } else if (paramValue instanceof List<String>) {
                List<String> stringList = (List<String>) paramValue;
                List<String> sanitizedList = new List<String>();
                for (String str : stringList) {
                    sanitizedList.add(sanitizeInput(str));
                }
                sanitizedParams.put(paramName, sanitizedList);
            } else {
                // For non-string types, validate they are safe types
                if (paramValue instanceof Id || paramValue instanceof Integer || 
                    paramValue instanceof Decimal || paramValue instanceof Boolean || 
                    paramValue instanceof Date || paramValue instanceof DateTime) {
                    sanitizedParams.put(paramName, paramValue);
                } else {
                    throw new SecurityException('Unsupported parameter type for: ' + paramName);
                }
            }
        }
        
        return sanitizedParams;
    }
    
    /**
     * @description Generate secure hash for data integrity
     * @param data The data to hash
     * @param salt Optional salt for additional security
     * @return SHA-256 hash as hex string
     */
    public static String generateSecureHash(String data, String salt) {
        if (String.isBlank(data)) {
            throw new IllegalArgumentException('Data cannot be null or empty');
        }
        
        String hashInput = data;
        if (String.isNotBlank(salt)) {
            hashInput = salt + data + salt;
        }
        
        Blob hashBlob = Crypto.generateDigest('SHA-256', Blob.valueOf(hashInput));
        return EncodingUtil.convertToHex(hashBlob);
    }
    
    /**
     * @description Validate HMAC signature for webhook security
     * @param payload The webhook payload
     * @param signature The provided signature
     * @param secret The webhook secret
     * @return True if signature is valid
     */
    public static Boolean validateHMACSignature(String payload, String signature, String secret) {
        if (String.isBlank(payload) || String.isBlank(signature) || String.isBlank(secret)) {
            return false;
        }
        
        try {
            Blob hmac = Crypto.generateMac('HmacSHA256', Blob.valueOf(payload), Blob.valueOf(secret));
            String expectedSignature = EncodingUtil.convertToHex(hmac);
            
            return Crypto.equals(signature, expectedSignature);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'HMAC validation failed: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * @description Check if current user has object-level access
     * @param objectName The SObject API name
     * @param accessType The type of access required
     * @return True if user has access
     */
    public static Boolean hasObjectAccess(String objectName, AccessType accessType) {
        if (String.isBlank(objectName)) {
            return false;
        }
        
        try {
            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
            if (objectType == null) {
                return false;
            }
            
            Schema.DescribeSObjectResult objectDescribe = objectType.getDescribe();
            
            switch on accessType {
                when READABLE {
                    return objectDescribe.isAccessible();
                }
                when CREATABLE {
                    return objectDescribe.isCreateable();
                }
                when UPDATABLE {
                    return objectDescribe.isUpdateable();
                }
                when DELETABLE {
                    return objectDescribe.isDeletable();
                }
            }
            
            return false;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Object access check failed: ' + e.getMessage());
            return false;
        }
    }    /**
     * @description Check if user has read access to object
     * @param objectName The SObject API name
     * @return True if user has read access
     */
    public static Boolean hasReadAccess(String objectName) {
        return hasObjectAccess(objectName, AccessType.READABLE);
    }
    
    /**
     * @description Check if user has create access to object
     * @param objectName The SObject API name
     * @return True if user has create access
     */
    public static Boolean hasCreateAccess(String objectName) {
        return hasObjectAccess(objectName, AccessType.CREATABLE);
    }
    
    /**
     * @description Check if user has update access to object
     * @param objectName The SObject API name
     * @return True if user has update access
     */
    public static Boolean hasUpdateAccess(String objectName) {
        return hasObjectAccess(objectName, AccessType.UPDATABLE);
    }
    
    /**
     * @description Check if user has delete access to object
     * @param objectName The SObject API name
     * @return True if user has delete access
     */
    public static Boolean hasDeleteAccess(String objectName) {
        return hasObjectAccess(objectName, AccessType.DELETABLE);
    }
    
    /**
     * @description Strip inaccessible fields from SObject records
     * @param accessType The type of access being performed
     * @param records List of SObject records to strip
     * @return List of records with inaccessible fields removed
     */
    public static List<SObject> stripInaccessibleFields(AccessType accessType, List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return records;
        }
        
        try {
            return Security.stripInaccessible(accessType, records).getRecords();
        } catch (Exception e) {
            throw new SecurityException('Failed to strip inaccessible fields: ' + e.getMessage());
        }
    }
    
    /**
     * @description Clear security cache (useful for testing)
     */
    @TestVisible
    private static void clearSecurityCache() {
        fieldAccessibilityCache.clear();
    }
    
    /**
     * @description Custom exception for security violations
     */
    public class SecurityException extends Exception {}
    
    /**
     * @description Enum for access types
     */
    public enum AccessType {
        READABLE,
        CREATABLE, 
        UPDATABLE,
        DELETABLE
    }
}

