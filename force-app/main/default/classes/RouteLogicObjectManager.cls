/**
 * @description Multi-object support manager for RouteLogic Enhanced v4.0.0
 * @author RouteLogic Team
 * @date 2025-01-21
 * @version 4.0.0
 * 
 * This class provides multi-object routing capabilities including:
 * - Support for Cases, Leads, and custom objects
 * - Object-agnostic routing logic
 * - Dynamic field mapping
 * - Flexible trigger framework
 * - Universal handoff orchestration
 */
public with sharing class RouteLogicObjectManager {
    
    // Supported object types
    public static final String OBJECT_TYPE_CASE = 'Case';
    public static final String OBJECT_TYPE_LEAD = 'Lead';
    public static final String OBJECT_TYPE_CUSTOM = 'Custom';
    
    // Standard field mappings
    private static final Map<String, String> CASE_FIELD_MAPPINGS = new Map<String, String>{
        'subject' => 'Subject',
        'description' => 'Description',
        'priority' => 'Priority',
        'status' => 'Status',
        'origin' => 'Origin',
        'contactId' => 'ContactId',
        'accountId' => 'AccountId',
        'ownerId' => 'OwnerId'
    };
    
    private static final Map<String, String> LEAD_FIELD_MAPPINGS = new Map<String, String>{
        'subject' => 'Company',
        'description' => 'Description',
        'priority' => 'Rating',
        'status' => 'Status',
        'origin' => 'LeadSource',
        'contactId' => 'ConvertedContactId',
        'accountId' => 'ConvertedAccountId',
        'ownerId' => 'OwnerId'
    };
    
    // Object configuration cache
    private static Map<String, ObjectConfiguration> objectConfigCache = new Map<String, ObjectConfiguration>();
    private static Boolean cacheInitialized = false;
    
    /**
     * @description Get supported object types
     * @return List of supported object API names
     */
    public static List<String> getSupportedObjectTypes() {
        List<String> supportedTypes = new List<String>();
        
        // Add standard objects
        supportedTypes.add(OBJECT_TYPE_CASE);
        supportedTypes.add(OBJECT_TYPE_LEAD);
        
        // Add configured custom objects
        List<ObjectConfiguration> customObjects = getCustomObjectConfigurations();
        for (ObjectConfiguration config : customObjects) {
            supportedTypes.add(config.objectApiName);
        }
        
        return supportedTypes;
    }
    
    /**
     * @description Check if object type is supported
     * @param objectApiName The object API name
     * @return True if object is supported
     */
    public static Boolean isObjectSupported(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return false;
        }
        
        return getSupportedObjectTypes().contains(objectApiName);
    }
    
    /**
     * @description Get object configuration
     * @param objectApiName The object API name
     * @return Object configuration or null if not supported
     */
    public static ObjectConfiguration getObjectConfiguration(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return null;
        }
        
        // Initialize cache if needed
        if (!cacheInitialized) {
            initializeObjectConfigurations();
        }
        
        return objectConfigCache.get(objectApiName);
    }
    
    /**
     * @description Process records for routing
     * @param records List of SObject records
     * @param objectApiName The object API name
     * @return List of routing contexts
     */
    public static List<RoutingContext> processRecordsForRouting(List<SObject> records, String objectApiName) {
        if (records == null || records.isEmpty() || String.isBlank(objectApiName)) {
            return new List<RoutingContext>();
        }
        
        // Validate object support
        if (!isObjectSupported(objectApiName)) {
            throw new UnsupportedObjectException('Object type not supported: ' + objectApiName);
        }
        
        // Get object configuration
        ObjectConfiguration config = getObjectConfiguration(objectApiName);
        if (config == null) {
            throw new ConfigurationException('Object configuration not found: ' + objectApiName);
        }
        
        List<RoutingContext> routingContexts = new List<RoutingContext>();
        
        try {
            for (SObject record : records) {
                RoutingContext context = createRoutingContext(record, config);
                if (context != null) {
                    routingContexts.add(context);
                }
            }
            
        } catch (Exception e) {
            throw new ProcessingException('Failed to process records: ' + e.getMessage());
        }
        
        return routingContexts;
    }
    
    /**
     * @description Create routing context from record
     * @param record The SObject record
     * @param config Object configuration
     * @return Routing context
     */
    private static RoutingContext createRoutingContext(SObject record, ObjectConfiguration config) {
        if (record == null || config == null) {
            return null;
        }
        
        try {
            RoutingContext context = new RoutingContext();
            context.recordId = (Id) record.get('Id');
            context.objectApiName = config.objectApiName;
            context.objectType = config.objectType;
            
            // Map standard fields
            context.subject = getFieldValue(record, config.subjectField);
            context.description = getFieldValue(record, config.descriptionField);
            context.priority = getFieldValue(record, config.priorityField);
            context.status = getFieldValue(record, config.statusField);
            context.origin = getFieldValue(record, config.originField);
            context.ownerId = (Id) record.get(config.ownerField);
            
            // Map relationship fields
            if (String.isNotBlank(config.contactField)) {
                context.contactId = (Id) record.get(config.contactField);
            }
            if (String.isNotBlank(config.accountField)) {
                context.accountId = (Id) record.get(config.accountField);
            }
            
            // Map custom fields
            context.customFields = new Map<String, Object>();
            if (config.customFieldMappings != null) {
                for (String fieldName : config.customFieldMappings.keySet()) {
                    String sourceField = config.customFieldMappings.get(fieldName);
                    Object fieldValue = record.get(sourceField);
                    context.customFields.put(fieldName, fieldValue);
                }
            }
            
            // Set routing metadata
            context.routingEnabled = config.routingEnabled;
            context.handoffEnabled = config.handoffEnabled;
            context.aiProviders = config.supportedProviders;
            
            return context;
            
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * @description Update record after routing
     * @param recordId The record ID
     * @param objectApiName The object API name
     * @param routingResult The routing result
     * @return True if update was successful
     */
    public static Boolean updateRecordAfterRouting(Id recordId, String objectApiName, RoutingResult routingResult) {
        if (recordId == null || String.isBlank(objectApiName) || routingResult == null) {
            return false;
        }
        
        try {
            // Get object configuration
            ObjectConfiguration config = getObjectConfiguration(objectApiName);
            if (config == null) {
                return false;
            }
            
            // Create update record
            SObject updateRecord = Schema.getGlobalDescribe().get(objectApiName).newSObject();
            updateRecord.put('Id', recordId);
            
            // Update routing fields
            if (String.isNotBlank(config.routingStatusField)) {
                updateRecord.put(config.routingStatusField, routingResult.status);
            }
            
            if (String.isNotBlank(config.aiProviderField)) {
                updateRecord.put(config.aiProviderField, routingResult.selectedProvider);
            }
            
            if (String.isNotBlank(config.handoffTimestampField)) {
                updateRecord.put(config.handoffTimestampField, routingResult.handoffTimestamp);
            }
            
            if (String.isNotBlank(config.routingScoreField)) {
                updateRecord.put(config.routingScoreField, routingResult.routingScore);
            }
            
            // Update owner if specified
            if (routingResult.newOwnerId != null && String.isNotBlank(config.ownerField)) {
                updateRecord.put(config.ownerField, routingResult.newOwnerId);
            }
            
            // Perform security check
            if (!RouteLogicSecurityUtils.hasUpdateAccess(objectApiName)) {
                return false;
            }
            
            // Update the record
            update updateRecord;
            
            return true;
            
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
     * @description Get custom object configurations
     * @return List of custom object configurations
     */
    private static List<ObjectConfiguration> getCustomObjectConfigurations() {
        List<ObjectConfiguration> customConfigs = new List<ObjectConfiguration>();
        
        try {
            // Query custom metadata for object configurations
            List<RouteLogic_Configuration__mdt> objectConfigs = [
                SELECT DeveloperName, Configuration_Value__c
                FROM RouteLogic_Configuration__mdt
                WHERE Configuration_Type__c = 'Custom_Object_Config'
                AND Environment__c IN ('All', :getCurrentEnvironment())
                WITH SECURITY_ENFORCED
            ];
            
            for (RouteLogic_Configuration__mdt config : objectConfigs) {
                try {
                    ObjectConfiguration objConfig = (ObjectConfiguration) JSON.deserialize(
                        config.Configuration_Value__c, ObjectConfiguration.class);
                    customConfigs.add(objConfig);
                } catch (Exception e) {
                }
            }
            
        } catch (Exception e) {
        }
        
        return customConfigs;
    }
    
    /**
     * @description Initialize object configurations
     */
    private static void initializeObjectConfigurations() {
        try {
            // Initialize standard object configurations
            initializeStandardObjectConfigurations();
            
            // Initialize custom object configurations
            List<ObjectConfiguration> customConfigs = getCustomObjectConfigurations();
            for (ObjectConfiguration config : customConfigs) {
                objectConfigCache.put(config.objectApiName, config);
            }
            
            cacheInitialized = true;
            
        } catch (Exception e) {
            cacheInitialized = true; // Prevent infinite retry
        }
    }
    
    /**
     * @description Initialize standard object configurations
     */
    private static void initializeStandardObjectConfigurations() {
        // Case configuration
        ObjectConfiguration caseConfig = new ObjectConfiguration();
        caseConfig.objectApiName = 'Case';
        caseConfig.objectType = OBJECT_TYPE_CASE;
        caseConfig.subjectField = 'Subject';
        caseConfig.descriptionField = 'Description';
        caseConfig.priorityField = 'Priority';
        caseConfig.statusField = 'Status';
        caseConfig.originField = 'Origin';
        caseConfig.ownerField = 'OwnerId';
        caseConfig.contactField = 'ContactId';
        caseConfig.accountField = 'AccountId';
        caseConfig.routingEnabled = true;
        caseConfig.handoffEnabled = true;
        caseConfig.supportedProviders = new List<String>{'Ada', 'Intercom'};
        caseConfig.routingStatusField = 'RouteLogic_Status__c';
        caseConfig.aiProviderField = 'RouteLogic_AI_Provider__c';
        caseConfig.handoffTimestampField = 'RouteLogic_Handoff_Timestamp__c';
        caseConfig.routingScoreField = 'RouteLogic_Score__c';
        
        objectConfigCache.put('Case', caseConfig);
        
        // Lead configuration
        ObjectConfiguration leadConfig = new ObjectConfiguration();
        leadConfig.objectApiName = 'Lead';
        leadConfig.objectType = OBJECT_TYPE_LEAD;
        leadConfig.subjectField = 'Company';
        leadConfig.descriptionField = 'Description';
        leadConfig.priorityField = 'Rating';
        leadConfig.statusField = 'Status';
        leadConfig.originField = 'LeadSource';
        leadConfig.ownerField = 'OwnerId';
        leadConfig.contactField = 'ConvertedContactId';
        leadConfig.accountField = 'ConvertedAccountId';
        leadConfig.routingEnabled = true;
        leadConfig.handoffEnabled = true;
        leadConfig.supportedProviders = new List<String>{'Ada', 'Intercom'};
        leadConfig.routingStatusField = 'RouteLogic_Status__c';
        leadConfig.aiProviderField = 'RouteLogic_AI_Provider__c';
        leadConfig.handoffTimestampField = 'RouteLogic_Handoff_Timestamp__c';
        leadConfig.routingScoreField = 'RouteLogic_Score__c';
        
        objectConfigCache.put('Lead', leadConfig);
    }
    
    /**
     * @description Get field value safely
     * @param record The SObject record
     * @param fieldName The field name
     * @return Field value as string
     */
    private static String getFieldValue(SObject record, String fieldName) {
        if (record == null || String.isBlank(fieldName)) {
            return null;
        }
        
        try {
            Object fieldValue = record.get(fieldName);
            return fieldValue != null ? String.valueOf(fieldValue) : null;
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * @description Get current environment
     * @return Environment name
     */
    private static String getCurrentEnvironment() {
        Boolean isSandbox = false;
        if (RouteLogicSecurityUtils.hasReadAccess('Organization')) {
            Organization org = [SELECT IsSandbox FROM Organization WITH SECURITY_ENFORCED LIMIT 1];
            isSandbox = org.IsSandbox;
        }
        return isSandbox ? 'Sandbox' : 'Production';
    }
    
    /**
     * @description Refresh object configuration cache
     */
    public static void refreshObjectConfigurations() {
        objectConfigCache.clear();
        cacheInitialized = false;
        initializeObjectConfigurations();
    }
    
    /**
     * @description Clear object configuration cache (for testing)
     */
    @TestVisible
    private static void clearCache() {
        objectConfigCache.clear();
        cacheInitialized = false;
    }
    
    /**
     * @description Get cache size for monitoring
     * @return Number of object configurations in cache
     */
    public static Integer getCacheSize() {
        return objectConfigCache.size();
    }
    
    // Inner classes
    
    /**
     * @description Object configuration container
     */
    public class ObjectConfiguration {
        public String objectApiName;
        public String objectType;
        public String subjectField;
        public String descriptionField;
        public String priorityField;
        public String statusField;
        public String originField;
        public String ownerField;
        public String contactField;
        public String accountField;
        public Boolean routingEnabled;
        public Boolean handoffEnabled;
        public List<String> supportedProviders;
        public String routingStatusField;
        public String aiProviderField;
        public String handoffTimestampField;
        public String routingScoreField;
        public Map<String, String> customFieldMappings;
    }
    
    /**
     * @description Routing context container
     */
    public class RoutingContext {
        public Id recordId;
        public String objectApiName;
        public String objectType;
        public String subject;
        public String description;
        public String priority;
        public String status;
        public String origin;
        public Id ownerId;
        public Id contactId;
        public Id accountId;
        public Boolean routingEnabled;
        public Boolean handoffEnabled;
        public List<String> aiProviders;
        public Map<String, Object> customFields;
    }
    
    /**
     * @description Routing result container
     */
    public class RoutingResult {
        public String status;
        public String selectedProvider;
        public DateTime handoffTimestamp;
        public Decimal routingScore;
        public Id newOwnerId;
        public String routingReason;
        public Map<String, Object> additionalData;
    }
    
    // Custom exceptions
    public class UnsupportedObjectException extends Exception {}
    public class ConfigurationException extends Exception {}
    public class ProcessingException extends Exception {}
}

