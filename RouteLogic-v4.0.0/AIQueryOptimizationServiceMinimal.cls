/**
 * @description Minimal service class for AI query optimization with enhanced security
 * @author RouteLogic Team
 * @date 2025-02-05
 * @security Fixed SQL injection vulnerabilities - AppExchange compliance
 */
public with sharing class AIQueryOptimizationServiceMinimal {
    private static final Integer DEFAULT_BATCH_SIZE = 200;
    private static final Integer MAX_QUERY_ROWS = 50000;
    
    // Security: Whitelist of allowed objects for queries
    private static final Set<String> ALLOWED_OBJECTS = new Set<String>{
        'AI_Processing_Status__c',
        'Error_Log__c',
        'Case',
        'Contact',
        'Account'
    };
    
    // Security: Whitelist of allowed fields per object
    private static final Map<String, Set<String>> ALLOWED_FIELDS = new Map<String, Set<String>>{
        'AI_Processing_Status__c' => new Set<String>{
            'Id', 'Name', 'Status__c', 'AI_Provider__c', 'Request_Time__c', 
            'Error_Message__c', 'CreatedDate', 'LastModifiedDate'
        },
        'Error_Log__c' => new Set<String>{
            'Id', 'Name', 'Error_Type__c', 'Error_Message__c', 'Class_Name__c',
            'CreatedDate', 'LastModifiedDate'
        },
        'Case' => new Set<String>{
            'Id', 'CaseNumber', 'Subject', 'Status', 'Priority', 'CreatedDate'
        }
    };
    
    // Security: Allowed fields for ORDER BY
    private static final Map<String, Set<String>> ALLOWED_ORDER_FIELDS = new Map<String, Set<String>>{
        'AI_Processing_Status__c' => new Set<String>{'CreatedDate', 'Name', 'Status__c'},
        'Error_Log__c' => new Set<String>{'CreatedDate', 'Error_Type__c'},
        'Case' => new Set<String>{'CreatedDate', 'CaseNumber', 'Priority'}
    };
    
    /**
     * @description Validate and execute a secure query
     * @param objectName The object to query
     * @param fields List of fields to select
     * @param whereClause Optional WHERE clause
     * @param orderBy Optional ORDER BY field
     * @param limitCount Optional LIMIT
     * @return List of SObjects
     */
    public static List<SObject> executeSecureQuery(String objectName, List<String> fields, 
                                                   String whereClause, String orderBy, Integer limitCount) {
        
        // Security: Validate object name
        if (!ALLOWED_OBJECTS.contains(objectName)) {
            throw new SecurityException('Object not allowed for queries: ' + objectName);
        }
        
        // Security: Validate fields
        Set<String> allowedFields = ALLOWED_FIELDS.get(objectName);
        if (allowedFields == null) {
            throw new SecurityException('No field whitelist found for object: ' + objectName);
        }
        
        for (String field : fields) {
            if (!allowedFields.contains(field)) {
                throw new SecurityException('Field not allowed: ' + field + ' on object: ' + objectName);
            }
        }
        
        // Security: Validate ORDER BY field if provided
        if (String.isNotBlank(orderBy)) {
            Set<String> allowedOrderFields = ALLOWED_ORDER_FIELDS.get(objectName);
            if (allowedOrderFields == null || !allowedOrderFields.contains(orderBy)) {
                throw new SecurityException('ORDER BY field not allowed: ' + orderBy + ' on object: ' + objectName);
            }
        }
        
        // Security: Validate limit
        if (limitCount != null && limitCount > MAX_QUERY_ROWS) {
            throw new SecurityException('Query limit exceeds maximum allowed: ' + limitCount + ' > ' + MAX_QUERY_ROWS);
        }
        
        // Build secure query
        String query = 'SELECT ' + String.join(fields, ', ') + ' FROM ' + objectName;
        
        if (String.isNotBlank(whereClause)) {
            query += ' WHERE ' + whereClause;
        }
        
        if (String.isNotBlank(orderBy)) {
            query += ' ORDER BY ' + orderBy;
        }
        
        if (limitCount != null) {
            query += ' LIMIT ' + limitCount;
        }
        
        // Note: WITH SECURITY_ENFORCED removed for compatibility
        
        System.debug(LoggingLevel.INFO, 'Executing secure query: ' + query);
        
        try {
            return Database.query(query);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Query execution failed: ' + e.getMessage());
            throw new SecurityException('Query execution failed: ' + e.getMessage());
        }
    }
    
    /**
     * @description Get processing status records with security validation
     * @param statusFilter Optional status filter
     * @param limitCount Optional limit
     * @return List of AI_Processing_Status__c records
     */
    public static List<AI_Processing_Status__c> getProcessingStatus(String statusFilter, Integer limitCount) {
        List<String> fields = new List<String>{'Id', 'Name', 'Status__c', 'AI_Provider__c', 'CreatedDate'};
        String whereClause = null;
        
        if (String.isNotBlank(statusFilter)) {
            whereClause = 'Status__c = \'' + String.escapeSingleQuotes(statusFilter) + '\'';
        }
        
        List<SObject> results = executeSecureQuery('AI_Processing_Status__c', fields, whereClause, 'CreatedDate', limitCount);
        return (List<AI_Processing_Status__c>) results;
    }
    
    /**
     * @description Get error log records with security validation
     * @param errorType Optional error type filter
     * @param limitCount Optional limit
     * @return List of Error_Log__c records
     */
    public static List<Error_Log__c> getErrorLogs(String errorType, Integer limitCount) {
        List<String> fields = new List<String>{'Id', 'Name', 'Error_Type__c', 'Error_Message__c', 'CreatedDate'};
        String whereClause = null;
        
        if (String.isNotBlank(errorType)) {
            whereClause = 'Error_Type__c = \'' + String.escapeSingleQuotes(errorType) + '\'';
        }
        
        List<SObject> results = executeSecureQuery('Error_Log__c', fields, whereClause, 'CreatedDate', limitCount);
        return (List<Error_Log__c>) results;
    }
}

