/**
 * @description Minimal query optimization service with security validation
 * @author RouteLogic Team
 * @date 2025-01-20
 */
public with sharing class AIQueryOptimizationServiceMinimal {
    
    private static final Integer DEFAULT_LIMIT = 200;
    private static final Integer MAX_LIMIT = 2000;
    
    /**
     * @description Execute a secure SOQL query with validation
     * @param objectName The API name of the object to query
     * @param fields List of field API names to retrieve
     * @param whereClause Optional WHERE clause (without the WHERE keyword)
     * @param orderBy Optional ORDER BY field (without the ORDER BY keywords)
     * @param limitSize Maximum number of records to return
     * @return List of SObjects matching the query
     */
    public static List<SObject> executeSecureQuery(
        String objectName, 
        List<String> fields, 
        String whereClause, 
        String orderBy, 
        Integer limitSize
    ) {
        // Validate object name
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        Schema.SObjectType sObjectType = globalDescribe.get(objectName);
        
        if (sObjectType == null) {
            throw new IllegalArgumentException('sObject type ' + objectName + ' does not exist');
        }
        
        // Get field map for validation
        Map<String, Schema.SObjectField> fieldMap = getFieldMap(objectName);
        
        // Validate fields
        if (fields == null || fields.isEmpty()) {
            throw new IllegalArgumentException('Field list cannot be empty for object ' + objectName);
        }
        
        for (String field : fields) {
            if (!isValidFieldName(field, fieldMap)) {
                throw new IllegalArgumentException('Invalid field ' + field + ' for object ' + objectName);
            }
        }
        
        // Validate WHERE clause
        if (String.isNotBlank(whereClause) && !isSafeWhereClause(whereClause)) {
            throw new SecurityException('Invalid WHERE clause: not allowed keywords or characters');
        }
        
        // Validate ORDER BY
        if (String.isNotBlank(orderBy)) {
            // Check if it's a valid field
            if (!isValidFieldName(orderBy, fieldMap)) {
                throw new SecurityException('Invalid order by field: ' + orderBy);
            }
            
            // Check if it contains only allowed characters (letters, digits, underscore)
            if (!Pattern.matches('^[a-zA-Z0-9_]+$', orderBy)) {
                throw new SecurityException('Invalid order by field: ' + orderBy);
            }
        }
        
        // Validate and adjust LIMIT
        if (limitSize == null || limitSize <= 0) {
            limitSize = DEFAULT_LIMIT;
        } else if (limitSize > MAX_LIMIT) {
            limitSize = MAX_LIMIT;
        }
        
        // Build the SOQL query
        String soql = 'SELECT ' + String.join(fields, ', ') + 
                      ' FROM ' + objectName;
        
        if (String.isNotBlank(whereClause)) {
            soql += ' WHERE ' + whereClause;
        }
        
        soql += ' WITH SECURITY_ENFORCED';
        
        if (String.isNotBlank(orderBy)) {
            soql += ' ORDER BY ' + orderBy;
        }
        
        soql += ' LIMIT ' + limitSize;
        
        // Execute the query
        return Database.query(soql);
    }
    
    /**
     * @description Validate if a WHERE clause is safe from SQL injection
     * @param whereClause The WHERE clause to validate
     * @return True if the clause is safe, false otherwise
     */
    private static Boolean isSafeWhereClause(String whereClause) {
        if (String.isBlank(whereClause)) {
            return true;
        }
        
        // Check for disallowed characters
        if (whereClause.contains(';') || 
            whereClause.contains('--') || 
            whereClause.contains('/*') || 
            whereClause.contains('*/')) {
            return false;
        }
        
        // Check for disallowed keywords
        String lowerClause = whereClause.toLowerCase();
        List<String> disallowedKeywords = new List<String>{
            'drop', 'delete', 'insert', 'update', 'execute', 'union', 'alter'
        };
        
        for (String keyword : disallowedKeywords) {
            if (lowerClause.contains(keyword)) {
                return false;
            }
        }
        
        // Check for safe character whitelist
        // Allow: letters, digits, underscore, space, parentheses, quotes, colon, comma, dot, comparison operators
        String safePattern = '^[a-zA-Z0-9_\\s\\(\\)\'":,.=!<>|&]+$';
        return Pattern.matches(safePattern, whereClause);
    }
    
    /**
     * @description Check if a field name is valid for an object
     * @param fieldName The field API name to check
     * @param fieldMap The field map for the object
     * @return True if the field is valid, false otherwise
     */
    private static Boolean isValidFieldName(String fieldName, Map<String, Schema.SObjectField> fieldMap) {
        return fieldMap.containsKey(fieldName);
    }
    
    /**
     * @description Get the field map for an object
     * @param objectName The API name of the object
     * @return Map of field API names to SObjectField
     */
    private static Map<String, Schema.SObjectField> getFieldMap(String objectName) {
        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectName);
        if (sObjectType == null) {
            throw new IllegalArgumentException('sObject type ' + objectName + ' does not exist');
        }
        
        return sObjectType.getDescribe().fields.getMap();
    }
}
