/**
 * @description Security utility class for RouteLogic Enhanced v4.0.0
 * @author RouteLogic Team
 * @date 2025-01-21
 * @version 4.0.0
 * 
 * SECURITY FIXES APPLIED (2025-01-31):
 * - Fix #2: Removed flawed regex-based sanitizeInput method, replaced with preventXSS and sanitizeForSOQL
 * - Fix #3: Added enforceUpdateSecurity method using Security.stripInaccessible
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
     * @description Prevent XSS attacks by properly escaping HTML characters
     * @param input The input string to escape
     * @return HTML-escaped string safe for display
     */
    public static String preventXSS(String input) {
        if (String.isBlank(input)) {
            return input;
        }
        
        // SECURITY FIX #2: Use String.escapeHtml4() for proper XSS prevention
        // This is the Salesforce-recommended approach for HTML escaping
        return input.escapeHtml4();
    }
    
    /**
     * @description Sanitize input for use in dynamic SOQL queries
     * @param input The input string to sanitize for SOQL
     * @return String with single quotes escaped for SOQL safety
     * 
     * WARNING: Using bind variables is always preferred over this method.
     * Use this only when absolutely necessary, such as when building dynamic
     * field lists or object names that cannot be parameterized.
     */
    public static String sanitizeForSOQL(String input) {
        if (String.isBlank(input)) {
            return input;
        }
        
        // SECURITY FIX #2: Use String.escapeSingleQuotes() for SOQL injection prevention
        // This escapes single quotes to prevent SOQL injection
        return String.escapeSingleQuotes(input);
    }
    
    /**
     * @description DEPRECATED - Use preventXSS() or sanitizeForSOQL() instead
     * @param input The input string
     * @return The input string unmodified
     * @deprecated This method has been replaced by preventXSS() and sanitizeForSOQL()
     */
    @Deprecated
    public static String sanitizeInput(String input) {
        // SECURITY FIX #2: This method is deprecated and should not be used
        // Redirect to preventXSS for backward compatibility
        return preventXSS(input);
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
     * @description Timing-safe string comparison to prevent timing attacks
     * @param a First string
     * @param b Second string
     * @return True if strings are equal, false otherwise, evaluated in constant time
     */
    public static Boolean timingSafeEquals(String a, String b) {
        String left = a == null ? '' : a;
        String right = b == null ? '' : b;

        Integer leftLen = left.length();
        Integer rightLen = right.length();
        Integer maxLen = Math.max(leftLen, rightLen);
        Integer diff = leftLen ^ rightLen;

        for (Integer i = 0; i < maxLen; i++) {
            String la = (i < leftLen) ? left.substring(i, i + 1) : '\u0000';
            String rb = (i < rightLen) ? right.substring(i, i + 1) : '\u0000';
            diff = diff | (la == rb ? 0 : 1);
        }

        return diff == 0;
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
            
            return timingSafeEquals(signature, expectedSignature);
        } catch (Exception e) {
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
            System.AccessType systemAccessType;
            switch on accessType {
                when READABLE { systemAccessType = System.AccessType.READABLE; }
                when CREATABLE { systemAccessType = System.AccessType.CREATABLE; }
                when UPDATABLE { systemAccessType = System.AccessType.UPDATABLE; }
                when DELETABLE { systemAccessType = System.AccessType.DELETABLE; }
            }
            return Security.stripInaccessible(systemAccessType, records).getRecords();
        } catch (Exception e) {
            throw new SecurityException('Failed to strip inaccessible fields: ' + e.getMessage());
        }
    }
    
    /**
     * @description Enforce field-level security for update operations
     * @param records List of SObject records to sanitize before DML update
     * @return List of records with fields removed that the current user cannot update
     * 
     * SECURITY FIX #3: This method ensures consistent FLS enforcement across all update operations.
     * It removes any fields from the records that the current user does not have permission to update,
     * preventing unauthorized field modifications and ensuring compliance with the security model.
     */
    public static List<SObject> enforceUpdateSecurity(List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return records;
        }
        
        try {
            // Use Security.stripInaccessible with UPDATABLE access type
            // This removes all fields that the current user cannot update
            SObjectAccessDecision decision = Security.stripInaccessible(
                System.AccessType.UPDATABLE, 
                records
            );
            
            // Return the sanitized records
            return decision.getRecords();
            
        } catch (NoAccessException e) {
            // Handle the case where the user has no access to the object at all
            throw new SecurityException('User does not have update access to the object: ' + e.getMessage());
        } catch (Exception e) {
            // Handle any other exceptions that might occur
            throw new SecurityException('Failed to enforce update security: ' + e.getMessage());
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

