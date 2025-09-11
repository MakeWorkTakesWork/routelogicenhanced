/**
 * @description Service class for AI query optimization with enhanced security
 * @author RouteLogic Team
 * @date 2025-01-20
 * @security Fixed SQL injection vulnerabilities - February 5, 2025
 */
public with sharing class AIQueryOptimizationService {
    private static final Integer DEFAULT_BATCH_SIZE = 200;
    private static final Integer MAX_QUERY_ROWS = 50000;
    
    // Security: Whitelist of allowed objects for queries
    private static final Set<String> ALLOWED_OBJECTS = new Set<String>{
        'AI_Processing_Status__c',
        'AI_Provider_Configuration__c',
        'AI_Audit_Event__c',
        'AI_Bulk_Processing_Metrics__c',
        'Error_Log__c',
        'Case',
        'Contact',
        'Account',
        'Lead',
        'Opportunity'
    };
    
    // Security: Whitelist of allowed fields per object
    private static final Map<String, Set<String>> ALLOWED_FIELDS = new Map<String, Set<String>>{
        'AI_Processing_Status__c' => new Set<String>{
            'Id', 'Name', 'Status__c', 'Provider_Type__c', 'Processing_Time__c', 
            'Error_Message__c', 'CreatedDate', 'LastModifiedDate'
        },
        'AI_Provider_Configuration__c' => new Set<String>{
            'Id', 'Name', 'Provider_Type__c', 'API_Endpoint__c', 'API_Key__c',
            'Is_Active__c', 'Priority_Level__c', 'Rate_Limit__c', 'Timeout_Seconds__c'
        },
        'AI_Audit_Event__c' => new Set<String>{
            'Id', 'Event_Type__c', 'Timestamp__c', 'Category__c', 'Details__c'
        },
        'Case' => new Set<String>{
            'Id', 'CaseNumber', 'Subject', 'Status', 'Priority', 'CreatedDate'
        },
        'Account' => new Set<String>{
            'Id', 'Name', 'AccountNumber', 'Type', 'Industry', 'CreatedDate'
        },
        'Contact' => new Set<String>{
            'Id', 'FirstName', 'LastName', 'Email', 'Phone', 'CreatedDate'
        },
        'Lead' => new Set<String>{
            'Id', 'FirstName', 'LastName', 'Company', 'Status', 'CreatedDate'
        },
        'Opportunity' => new Set<String>{
            'Id', 'Name', 'Amount', 'StageName', 'CloseDate', 'CreatedDate'
        }
    };
    
    // Security: Allowed fields for ORDER BY
    private static final Map<String, Set<String>> ALLOWED_ORDER_FIELDS = new Map<String, Set<String>>{
        'AI_Processing_Status__c' => new Set<String>{'CreatedDate', 'Name', 'Status__c'},
        'AI_Provider_Configuration__c' => new Set<String>{'Name', 'Priority_Level__c'},
        'AI_Audit_Event__c' => new Set<String>{'Timestamp__c', 'Event_Type__c'},
        'Case' => new Set<String>{'CreatedDate', 'CaseNumber'},
        'Account' => new Set<String>{'CreatedDate', 'Name'},
        'Contact' => new Set<String>{'CreatedDate', 'LastName'},
        'Lead' => new Set<String>{'CreatedDate', 'LastName'},
        'Opportunity' => new Set<String>{'CreatedDate', 'CloseDate', 'Amount'}
    };
    
    // Query performance metrics
    public class QueryMetrics {
        public Long executionTime { get; set; }
        public Integer rowsProcessed { get; set; }
        public Integer queryCount { get; set; }
        public Boolean isOptimized { get; set; }
        public List<String> optimizationSuggestions { get; set; }
        
        public QueryMetrics() {
            this.executionTime = 0;
            this.rowsProcessed = 0;
            this.queryCount = 0;
            this.isOptimized = false;
            this.optimizationSuggestions = new List<String>();
        }
    }
    
    // Query optimizer configuration
    public class OptimizerConfig {
        public Boolean enableIndexHints { get; set; }
        public Boolean useSelectiveFilters { get; set; }
        public Boolean enableQueryBatching { get; set; }
        public Integer batchSize { get; set; }
        public Boolean enableParallelProcessing { get; set; }
        
        public OptimizerConfig() {
            this.enableIndexHints = true;
            this.useSelectiveFilters = true;
            this.enableQueryBatching = true;
            this.batchSize = DEFAULT_BATCH_SIZE;
            this.enableParallelProcessing = false;
        }
    }
    
    // Optimized query methods with security validation
    public static List<AI_Processing_Status__c> getProcessingStatusOptimized(
        DateTime startDate, 
        DateTime endDate,
        Set<String> providerTypes,
        OptimizerConfig config
    ) {
        Long startTime = DateTime.now().getTime();
        QueryMetrics metrics = new QueryMetrics();
        
        try {
            // Security: Validate object and fields
            String objectName = 'AI_Processing_Status__c';
            List<String> fields = new List<String>{
                'Id', 'Name', 'Status__c', 'Provider_Type__c',
                'Processing_Time__c', 'Error_Message__c', 'CreatedDate'
            };
            
            validateObjectAndFields(objectName, fields);
            
            // Build query with validated components
            String query = 'SELECT ' + String.join(fields, ', ') + 
                          ' FROM ' + objectName +
                          ' WHERE CreatedDate >= :startDate' +
                          ' AND CreatedDate <= :endDate' +
                          ' AND Provider_Type__c IN :providerTypes' +
                          ' WITH SECURITY_ENFORCED' +
                          ' ORDER BY CreatedDate DESC' +
                          ' LIMIT ' + MAX_QUERY_ROWS;
            
            // Execute with proper limits
            List<AI_Processing_Status__c> results = Database.query(query);
            
            // Update metrics
            metrics.executionTime = DateTime.now().getTime() - startTime;
            metrics.rowsProcessed = results.size();
            metrics.queryCount = 1;
            metrics.isOptimized = true;
            
            // Cache results if appropriate
            if (config.enableQueryBatching && results.size() < 1000) {
                cacheQueryResults('processing_status_' + String.valueOf(startDate), results);
            }
            
            return results;
            
        } catch (Exception e) {
            
            throw e;
        } finally {
            logQueryMetrics(metrics);
        }
    }
    
    // Bulk query operations
    public static Map<Id, AI_Provider_Configuration__c> getProviderConfigsBulk(
        Set<Id> configIds
    ) {
        if (configIds.isEmpty()) {
            return new Map<Id, AI_Provider_Configuration__c>();
        }
        
        // Check cache first
        Map<Id, AI_Provider_Configuration__c> cachedResults = 
            getCachedProviderConfigs(configIds);
        
        // Find missing IDs
        Set<Id> missingIds = new Set<Id>();
        for (Id configId : configIds) {
            if (!cachedResults.containsKey(configId)) {
                missingIds.add(configId);
            }
        }
        
        // Query only missing records with security enforced
        if (!missingIds.isEmpty()) {
            List<AI_Provider_Configuration__c> configs = [
                SELECT Id, Name, Provider_Type__c, API_Endpoint__c,
                       API_Key__c, Is_Active__c, Priority_Level__c,
                       Rate_Limit__c, Timeout_Seconds__c
                FROM AI_Provider_Configuration__c
                WHERE Id IN :missingIds
                AND Is_Active__c = true
                WITH SECURITY_ENFORCED
            ];
            
            // Add to cache and results
            for (AI_Provider_Configuration__c config : configs) {
                cachedResults.put(config.Id, config);
                cacheProviderConfig(config);
            }
        }
        
        return cachedResults;
    }
    
    // Secure aggregation queries
    public static List<AggregateResult> getOptimizedAnalytics(
        String groupByField,
        DateTime startDate,
        DateTime endDate,
        OptimizerConfig config
    ) {
        // Security: Validate group by field
        String objectName = 'AI_Processing_Status__c';
        if (!isFieldAllowed(objectName, groupByField)) {
            throw new SecurityException('Invalid group by field: ' + groupByField);
        }
        
        // Sanitize the groupByField to prevent SOQL injection
        String sanitizedGroupByField = RouteLogicSecurityUtils.sanitizeForSOQL(groupByField);
        
        // Check read access to the object
        if (!RouteLogicSecurityUtils.hasReadAccess(objectName)) {
            throw new RouteLogicSecurityUtils.SecurityException('Insufficient permissions to read ' + objectName);
        }
        
        // Use parameterized query with validated field name
        List<AggregateResult> results;
        if (config.useSelectiveFilters) {
            if (sanitizedGroupByField == 'Provider_Type__c') {
                results = [
                    SELECT Provider_Type__c, COUNT(Id) recordCount,
                           AVG(Processing_Time__c) avgTime,
                           MAX(Processing_Time__c) maxTime,
                           MIN(Processing_Time__c) minTime
                    FROM AI_Processing_Status__c
                    WHERE CreatedDate >= :startDate
                    AND CreatedDate <= :endDate
                    AND Provider_Type__c != null
                    AND Status__c IN ('Completed', 'Failed')
                    WITH SECURITY_ENFORCED
                    GROUP BY Provider_Type__c
                    ORDER BY COUNT(Id) DESC
                    LIMIT 100
                ];
            } else if (sanitizedGroupByField == 'Status__c') {
                results = [
                    SELECT Status__c, COUNT(Id) recordCount,
                           AVG(Processing_Time__c) avgTime,
                           MAX(Processing_Time__c) maxTime,
                           MIN(Processing_Time__c) minTime
                    FROM AI_Processing_Status__c
                    WHERE CreatedDate >= :startDate
                    AND CreatedDate <= :endDate
                    AND Provider_Type__c != null
                    AND Status__c IN ('Completed', 'Failed')
                    WITH SECURITY_ENFORCED
                    GROUP BY Status__c
                    ORDER BY COUNT(Id) DESC
                    LIMIT 100
                ];
            } else {
                throw new SecurityException('Unsupported group by field for selective filters: ' + sanitizedGroupByField);
            }
        } else {
            if (sanitizedGroupByField == 'Provider_Type__c') {
                results = [
                    SELECT Provider_Type__c, COUNT(Id) recordCount,
                           AVG(Processing_Time__c) avgTime,
                           MAX(Processing_Time__c) maxTime,
                           MIN(Processing_Time__c) minTime
                    FROM AI_Processing_Status__c
                    WHERE CreatedDate >= :startDate
                    AND CreatedDate <= :endDate
                    AND Provider_Type__c != null
                    WITH SECURITY_ENFORCED
                    GROUP BY Provider_Type__c
                    ORDER BY COUNT(Id) DESC
                    LIMIT 100
                ];
            } else if (sanitizedGroupByField == 'Status__c') {
                results = [
                    SELECT Status__c, COUNT(Id) recordCount,
                           AVG(Processing_Time__c) avgTime,
                           MAX(Processing_Time__c) maxTime,
                           MIN(Processing_Time__c) minTime
                    FROM AI_Processing_Status__c
                    WHERE CreatedDate >= :startDate
                    AND CreatedDate <= :endDate
                    AND Provider_Type__c != null
                    WITH SECURITY_ENFORCED
                    GROUP BY Status__c
                    ORDER BY COUNT(Id) DESC
                    LIMIT 100
                ];
            } else {
                throw new SecurityException('Unsupported group by field: ' + sanitizedGroupByField);
            }
        }
        
        return results;
    }
    
    // Secure lazy loading implementation
    public static List<SObject> lazyLoadRecords(
        String objectName,
        Integer offset,
        Integer limitSize,
        String orderBy
    ) {
        // Security: Validate object name
        if (!ALLOWED_OBJECTS.contains(objectName)) {
            throw new SecurityException('Invalid object for lazy loading: ' + objectName);
        }
        
        // Security: Validate order by field
        if (!isOrderByAllowed(objectName, orderBy)) {
            throw new SecurityException('Invalid order by field: ' + orderBy);
        }
        
        // Validate offset and limit
        if (offset < 0 || limitSize < 1 || limitSize > 2000) {
            throw new IllegalArgumentException('Invalid offset or limit values');
        }
        
        // Sanitize orderBy field to prevent SOQL injection
        String sanitizedOrderBy = RouteLogicSecurityUtils.sanitizeForSOQL(orderBy);
        
        // Validate that orderBy field is allowed for the object
        if (!isFieldAllowed(objectName, sanitizedOrderBy)) {
            throw new SecurityException('Invalid order by field: ' + sanitizedOrderBy);
        }
        
        // Use parameterized query with validated fields
        List<SObject> results;
        if (objectName == 'Case') {
            results = [
                SELECT Id, CaseNumber
                FROM Case
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate DESC
                LIMIT :limitSize
                OFFSET :offset
            ];
        } else if (objectName == 'AI_Processing_Status__c') {
            results = [
                SELECT Id, Name
                FROM AI_Processing_Status__c
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate DESC
                LIMIT :limitSize
                OFFSET :offset
            ];
        } else {
            throw new SecurityException('Unsupported object for lazy loading: ' + objectName);
        }
        
        return results;
    }
    
    // Secure query builder with optimization
    private static String buildOptimizedQuery(
        String objectName,
        List<String> fields,
        List<String> whereConditions,
        String orderBy,
        OptimizerConfig config
    ) {
        // Security: Validate all components
        validateObjectAndFields(objectName, fields);
        
        if (String.isNotBlank(orderBy) && !isOrderByAllowed(objectName, orderBy)) {
            throw new SecurityException('Invalid order by field: ' + orderBy);
        }
        
        String query = 'SELECT ' + String.join(fields, ', ') + 
                      ' FROM ' + objectName;
        
        if (!whereConditions.isEmpty()) {
            // Validate each where condition for injection patterns
            for (String cond : whereConditions) {
                validateWhereClause(cond);
            }
            query += ' WHERE ' + String.join(whereConditions, ' AND ');
        }
        
        query += ' WITH SECURITY_ENFORCED';
        
        if (String.isNotBlank(orderBy)) {
            query += ' ORDER BY ' + orderBy;
        }
        
        query += ' LIMIT ' + MAX_QUERY_ROWS;
        
        return query;
    }
    
    // Security validation methods
    private static void validateObjectAndFields(String objectName, List<String> fields) {
        if (!ALLOWED_OBJECTS.contains(objectName)) {
            throw new SecurityException('Invalid object: ' + objectName);
        }
        
        Set<String> allowedFields = ALLOWED_FIELDS.get(objectName);
        if (allowedFields == null) {
            throw new SecurityException('No field configuration for object: ' + objectName);
        }
        
        for (String field : fields) {
            if (!allowedFields.contains(field)) {
                throw new SecurityException('Invalid field ' + field + ' for object ' + objectName);
            }
        }
    }
    
    private static Boolean isFieldAllowed(String objectName, String fieldName) {
        Set<String> allowedFields = ALLOWED_FIELDS.get(objectName);
        return allowedFields != null && allowedFields.contains(fieldName);
    }
    
    private static Boolean isOrderByAllowed(String objectName, String orderByField) {
        Set<String> allowedOrderFields = ALLOWED_ORDER_FIELDS.get(objectName);
        return allowedOrderFields != null && allowedOrderFields.contains(orderByField);
    }
    
    /**
     * @description Validate a single WHERE clause segment for common SQL-injection patterns.
     * Throws SecurityException if a dangerous pattern is detected.
     */
    private static void validateWhereClause(String whereClause) {
        if (String.isBlank(whereClause)) return;
        String lower = whereClause.toLowerCase();
        List<String> dangerous = new List<String>{
            ';', '--', '/*', '*/', ' drop ', ' delete ', ' insert ', ' update ',
            ' union ', ' exec ', ' execute ', ' xp_', ' sp_'
        };
        for (String p : dangerous) {
            if (lower.contains(p)) {
                throw new SecurityException('Invalid WHERE clause - potential SQL injection detected');
            }
        }
    }
    
    // Batch processing for large datasets
    public static void processBatchOptimized(
        String query,
        IBatchProcessor processor,
        OptimizerConfig config
    ) {
        // Security: Parse and validate query components
        // This is a simplified implementation - in production, use a proper query parser
        if (!query.containsIgnoreCase('WITH SECURITY_ENFORCED')) {
            throw new SecurityException('Query must include WITH SECURITY_ENFORCED');
        }
        
        Integer offset = 0;
        Integer batchSize = config.batchSize;
        Boolean hasMore = true;
        
        while (hasMore && offset < MAX_QUERY_ROWS) {
            String batchQuery = query + ' LIMIT :batchSize OFFSET :offset';
            List<SObject> batch = Database.query(batchQuery);
            
            if (batch.isEmpty()) {
                hasMore = false;
            } else {
                processor.processBatch(batch);
                offset += batchSize;
                
                // Check governor limits
                if (Limits.getQueries() > 90) {
                    // Queue remaining work
                    queueRemainingWork(query, offset, processor);
                    hasMore = false;
                }
            }
        }
    }
    
    // Interface for batch processing
    public interface IBatchProcessor {
        void processBatch(List<SObject> records);
    }
    
    // Query result caching
    private static void cacheQueryResults(String key, List<SObject> results) {
        AICacheService.CacheConfig cacheConfig = new AICacheService.CacheConfig();
        cacheConfig.ttl = 300; // 5 minutes
        cacheConfig.cacheLevel = 'PARTITION';
        
        AICacheService.put(key, results, cacheConfig);
    }
    
    private static Map<Id, AI_Provider_Configuration__c> getCachedProviderConfigs(
        Set<Id> configIds
    ) {
        Map<Id, AI_Provider_Configuration__c> results = 
            new Map<Id, AI_Provider_Configuration__c>();
        
        AICacheService.CacheConfig cacheConfig = new AICacheService.CacheConfig();
        
        for (Id configId : configIds) {
            AI_Provider_Configuration__c config = (AI_Provider_Configuration__c)
                AICacheService.get('provider_' + configId, cacheConfig);
            
            if (config != null) {
                results.put(configId, config);
            }
        }
        
        return results;
    }
    
    private static void cacheProviderConfig(AI_Provider_Configuration__c config) {
        AICacheService.CacheConfig cacheConfig = new AICacheService.CacheConfig();
        cacheConfig.ttl = 600; // 10 minutes
        
        AICacheService.put('provider_' + config.Id, config, cacheConfig);
    }
    
    // Query monitoring and optimization suggestions
    public static QueryMetrics analyzeQuery(String query) {
        QueryMetrics metrics = new QueryMetrics();
        
        // Security check first
        if (!query.containsIgnoreCase('WITH SECURITY_ENFORCED')) {
            metrics.optimizationSuggestions.add(
                'CRITICAL: Add WITH SECURITY_ENFORCED for security compliance'
            );
        }
        
        // Check for common performance issues
        if (query.containsIgnoreCase('NOT IN')) {
            metrics.optimizationSuggestions.add(
                'Consider using NOT EXISTS instead of NOT IN for better performance'
            );
        }
        
        if (!query.containsIgnoreCase('LIMIT')) {
            metrics.optimizationSuggestions.add(
                'Add LIMIT clause to prevent hitting governor limits'
            );
        }
        
        if (query.containsIgnoreCase('OR')) {
            metrics.optimizationSuggestions.add(
                'Multiple OR conditions can impact performance - consider using IN clause'
            );
        }
        
        if (!query.containsIgnoreCase('WHERE')) {
            metrics.optimizationSuggestions.add(
                'Query without WHERE clause will scan entire table'
            );
        }
        
        metrics.isOptimized = metrics.optimizationSuggestions.isEmpty();
        
        return metrics;
    }
    
    // Async processing for heavy queries
    private static void queueRemainingWork(
        String query, 
        Integer offset, 
        IBatchProcessor processor
    ) {
        // Implementation would queue a platform event or batch job
        
    }
    
    private static void logQueryMetrics(QueryMetrics metrics) {
        if (metrics.executionTime > 1000) { // Log slow queries
            
            
            // Log to monitoring system
            AI_Query_Performance__e perfEvent = new AI_Query_Performance__e(
                Execution_Time__c = metrics.executionTime,
                Rows_Processed__c = metrics.rowsProcessed,
                Is_Slow_Query__c = true
            );
            EventBus.publish(perfEvent);
        }
    }
    
    // Index recommendation with security
    public static List<String> recommendIndexes(String objectName) {
        // Security: Validate object name
        if (!ALLOWED_OBJECTS.contains(objectName)) {
            throw new SecurityException('Invalid object for index recommendation: ' + objectName);
        }
        
        List<String> recommendations = new List<String>();
        
        // Analyze query patterns and recommend indexes
        Map<String, Integer> fieldUsage = analyzeFieldUsage(objectName);
        
        for (String field : fieldUsage.keySet()) {
            if (fieldUsage.get(field) > 100) {
                recommendations.add(
                    'Consider adding index on ' + objectName + '.' + field
                );
            }
        }
        
        return recommendations;
    }
    
    private static Map<String, Integer> analyzeFieldUsage(String objectName) {
        // This would analyze actual query logs in production
        // For now, return common patterns
        Map<String, Map<String, Integer>> usagePatterns = new Map<String, Map<String, Integer>>{
            'AI_Processing_Status__c' => new Map<String, Integer>{
                'CreatedDate' => 500,
                'Status__c' => 300,
                'Provider_Type__c' => 250
            },
            'AI_Provider_Configuration__c' => new Map<String, Integer>{
                'Provider_Type__c' => 200,
                'Is_Active__c' => 150
            }
        };
        
        return usagePatterns.get(objectName) ?? new Map<String, Integer>();
    }
}