/**
 * @description Minimal service for mobile performance optimization with enhanced security
 * @author RouteLogic Team
 * @date 2025-02-05
 * @security Fixed SQL injection vulnerability with enum-based type safety - AppExchange compliance
 */
public with sharing class AIMobilePerformanceServiceMinimal {
    
    // Security: Allowed performance data types with enum-based type safety
    public enum AllowedPerformanceTypes {
        ROUTES,
        STATUS,
        ANALYTICS,
        CONFIG,
        SYNC_DATA
    }
    
    // Security: Allowed objects for mobile queries
    private static final Set<String> ALLOWED_MOBILE_OBJECTS = new Set<String>{
        'AI_Processing_Status__c',
        'Error_Log__c',
        'Case',
        'Contact',
        'Account'
    };
    
    // Security: Allowed fields per object for mobile access
    private static final Map<String, Set<String>> ALLOWED_MOBILE_FIELDS = new Map<String, Set<String>>{
        'AI_Processing_Status__c' => new Set<String>{
            'Id', 'Name', 'Status__c', 'AI_Provider__c', 'CreatedDate'
        },
        'Error_Log__c' => new Set<String>{
            'Id', 'Name', 'Error_Type__c', 'Timestamp__c', 'CreatedDate'
        },
        'Case' => new Set<String>{
            'Id', 'CaseNumber', 'Subject', 'Status', 'Priority'
        }
    };
    
    // Mobile optimization settings
    public class MobileConfig {
        public Boolean enableDataCompression { get; set; }
        public Integer maxPayloadSize { get; set; }
        public Boolean enableOfflineMode { get; set; }
        public Integer syncBatchSize { get; set; }
        
        public MobileConfig() {
            this.enableDataCompression = true;
            this.maxPayloadSize = 100000; // 100KB
            this.enableOfflineMode = true;
            this.syncBatchSize = 50;
        }
    }
    
    // Mobile response wrapper
    public class MobileResponse {
        public Boolean success { get; set; }
        public Object data { get; set; }
        public String message { get; set; }
        public Long timestamp { get; set; }
        
        public MobileResponse() {
            this.success = false;
            this.timestamp = System.currentTimeMillis();
        }
    }
    
    /**
     * @description Get mobile data with security validation using enum-based type safety
     * @param dataType The type of data to retrieve (must be from AllowedPerformanceTypes enum)
     * @param objectName The object to query (must be in whitelist)
     * @param limitCount Optional limit for results
     * @return MobileResponse with requested data
     */
    public static MobileResponse getMobileData(AllowedPerformanceTypes dataType, String objectName, Integer limitCount) {
        MobileResponse response = new MobileResponse();
        
        try {
            // Security: Validate object name against whitelist
            if (!ALLOWED_MOBILE_OBJECTS.contains(objectName)) {
                response.message = 'Object not allowed for mobile access: ' + objectName;
                return response;
            }
            
            // Security: Validate data type using enum (prevents injection)
            if (dataType == null) {
                response.message = 'Data type must be specified from allowed types';
                return response;
            }
            
            // Security: Get allowed fields for the object
            Set<String> allowedFields = ALLOWED_MOBILE_FIELDS.get(objectName);
            if (allowedFields == null || allowedFields.isEmpty()) {
                response.message = 'No fields allowed for mobile access on object: ' + objectName;
                return response;
            }
            
            // Security: Build query with validated components
            List<String> fieldList = new List<String>(allowedFields);
            String query = 'SELECT ' + String.join(fieldList, ', ') + ' FROM ' + objectName;
            
            // Add data type specific filtering
            switch on dataType {
                when STATUS {
                    if (objectName == 'AI_Processing_Status__c') {
                        query += ' WHERE Status__c != null';
                    }
                }
                when ANALYTICS {
                    query += ' ORDER BY CreatedDate DESC';
                }
                when CONFIG {
                    if (objectName == 'AI_Processing_Status__c') {
                        query += ' WHERE AI_Provider__c != null';
                    }
                }
            }
            
            // Apply limit if specified
            if (limitCount != null && limitCount > 0) {
                if (limitCount > 1000) {
                    limitCount = 1000; // Security: Cap at reasonable limit
                }
                query += ' LIMIT ' + limitCount;
            } else {
                query += ' LIMIT 100'; // Default limit for mobile
            }
            
            query += ' WITH SECURITY_ENFORCED';
            
            System.debug(LoggingLevel.INFO, 'Mobile query: ' + query);
            
            List<SObject> results = Database.query(query);
            
            response.success = true;
            response.data = results;
            response.message = 'Data retrieved successfully for type: ' + dataType.name();
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Mobile data retrieval failed: ' + e.getMessage());
            response.message = 'Data retrieval failed: ' + e.getMessage();
        }
        
        return response;
    }
    
    /**
     * @description Get mobile configuration with security validation
     * @return MobileConfig with optimized settings
     */
    public static MobileConfig getMobileConfig() {
        MobileConfig config = new MobileConfig();
        
        try {
            // Security: Only return safe configuration values
            // No dynamic configuration that could be exploited
            System.debug(LoggingLevel.INFO, 'Mobile configuration retrieved');
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Mobile config retrieval failed: ' + e.getMessage());
            // Return default config on error
        }
        
        return config;
    }
    
    /**
     * @description Validate mobile request parameters
     * @param dataType The requested data type
     * @param objectName The requested object
     * @return Boolean indicating if request is valid
     */
    public static Boolean validateMobileRequest(AllowedPerformanceTypes dataType, String objectName) {
        // Security: Enum-based validation prevents injection
        if (dataType == null) {
            return false;
        }
        
        // Security: Object whitelist validation
        if (!ALLOWED_MOBILE_OBJECTS.contains(objectName)) {
            return false;
        }
        
        // Security: Field availability check
        Set<String> allowedFields = ALLOWED_MOBILE_FIELDS.get(objectName);
        if (allowedFields == null || allowedFields.isEmpty()) {
            return false;
        }
        
        return true;
    }
}

