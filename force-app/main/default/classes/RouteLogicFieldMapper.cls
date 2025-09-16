/**
 * @description Flexible field mapping system for RouteLogic Enhanced v4.0.0
 * @author RouteLogic Team
 * @date 2025-01-21
 * @version 4.0.0
 * 
 * This class provides flexible field mapping capabilities including:
 * - Dynamic field mapping between objects
 * - Field type conversion and validation
 * - Custom field mapping rules
 * - Schema introspection and validation
 * - Cross-object field synchronization
 */
public with sharing class RouteLogicFieldMapper {
    
    // Field mapping cache
    private static Map<String, Map<String, FieldMapping>> fieldMappingCache = new Map<String, Map<String, FieldMapping>>();
    private static Map<String, Schema.SObjectType> schemaCache = new Map<String, Schema.SObjectType>();
    private static Boolean cacheInitialized = false;
    
    // Standard field types
    public static final String FIELD_TYPE_TEXT = 'TEXT';
    public static final String FIELD_TYPE_NUMBER = 'NUMBER';
    public static final String FIELD_TYPE_DATE = 'DATE';
    public static final String FIELD_TYPE_DATETIME = 'DATETIME';
    public static final String FIELD_TYPE_BOOLEAN = 'BOOLEAN';
    public static final String FIELD_TYPE_PICKLIST = 'PICKLIST';
    public static final String FIELD_TYPE_REFERENCE = 'REFERENCE';
    
    /**
     * @description Map fields from source object to target object
     * @param sourceRecord Source SObject record
     * @param targetObjectType Target object API name
     * @param mappingRules Custom mapping rules
     * @return Mapped field values
     */
    public static Map<String, Object> mapFields(SObject sourceRecord, String targetObjectType, 
                                               Map<String, String> mappingRules) {
        if (sourceRecord == null || String.isBlank(targetObjectType)) {
            throw new IllegalArgumentException('Source record and target object type cannot be null');
        }
        
        Map<String, Object> mappedFields = new Map<String, Object>();
        
        try {
            // Initialize cache if needed
            if (!cacheInitialized) {
                initializeCache();
            }
            
            // Get source object type
            String sourceObjectType = String.valueOf(sourceRecord.getSObjectType());
            
            // Get field mappings
            Map<String, FieldMapping> objectMappings = getFieldMappings(sourceObjectType, targetObjectType);
            
            // Apply custom mapping rules if provided
            if (mappingRules != null && !mappingRules.isEmpty()) {
                objectMappings = applyCustomMappingRules(objectMappings, mappingRules);
            }
            
            // Map each field
            for (String targetField : objectMappings.keySet()) {
                FieldMapping mapping = objectMappings.get(targetField);
                Object mappedValue = mapFieldValue(sourceRecord, mapping);
                
                if (mappedValue != null) {
                    mappedFields.put(targetField, mappedValue);
                }
            }
            
            // Field mapping completed successfully
            
        } catch (Exception e) {
            ErrorLogService.logError('RouteLogicFieldMapper.mapFields', e, 'Field mapping failed');
            throw new FieldMappingException('Field mapping failed: ' + e.getMessage());
        }
        
        return mappedFields;
    }
    
    /**
     * @description Map field value with type conversion
     * @param sourceRecord Source SObject record
     * @param mapping Field mapping configuration
     * @return Mapped and converted field value
     */
    private static Object mapFieldValue(SObject sourceRecord, FieldMapping mapping) {
        if (sourceRecord == null || mapping == null || String.isBlank(mapping.sourceField)) {
            return null;
        }
        
        try {
            // Get source value
            Object sourceValue = sourceRecord.get(mapping.sourceField);
            if (sourceValue == null) {
                return mapping.defaultValue;
            }
            
            // Apply transformation if specified
            if (String.isNotBlank(mapping.transformation)) {
                sourceValue = applyTransformation(sourceValue, mapping.transformation);
            }
            
            // Convert to target type
            Object convertedValue = convertFieldValue(sourceValue, mapping.sourceType, mapping.targetType);
            
            // Validate converted value
            if (mapping.validationRules != null && !mapping.validationRules.isEmpty()) {
                if (!validateFieldValue(convertedValue, mapping.validationRules)) {
                    // Field validation failed - returning default value
                    return mapping.defaultValue;
                }
            }
            
            return convertedValue;
            
        } catch (Exception e) {
            // Failed to map field value - returning default
            return mapping.defaultValue;
        }
    }
    
    /**
     * @description Convert field value between types
     * @param value The value to convert
     * @param sourceType Source field type
     * @param targetType Target field type
     * @return Converted value
     */
    private static Object convertFieldValue(Object value, String sourceType, String targetType) {
        if (value == null || sourceType == targetType) {
            return value;
        }
        
        try {
            switch on targetType {
                when 'TEXT' {
                    return String.valueOf(value);
                }
                when 'NUMBER' {
                    if (value instanceof String) {
                        return Decimal.valueOf((String) value);
                    } else if (value instanceof Integer) {
                        return Decimal.valueOf((Integer) value);
                    } else if (value instanceof Decimal) {
                        return value;
                    }
                    return Decimal.valueOf(String.valueOf(value));
                }
                when 'DATE' {
                    if (value instanceof String) {
                        return Date.valueOf((String) value);
                    } else if (value instanceof DateTime) {
                        return ((DateTime) value).date();
                    }
                    return Date.valueOf(String.valueOf(value));
                }
                when 'DATETIME' {
                    if (value instanceof String) {
                        return DateTime.valueOf((String) value);
                    } else if (value instanceof Date) {
                        return DateTime.newInstance((Date) value, Time.newInstance(0, 0, 0, 0));
                    }
                    return DateTime.valueOf(String.valueOf(value));
                }
                when 'BOOLEAN' {
                    if (value instanceof String) {
                        String strValue = ((String) value).toLowerCase();
                        return strValue == 'true' || strValue == '1' || strValue == 'yes';
                    } else if (value instanceof Integer) {
                        return (Integer) value != 0;
                    }
                    return Boolean.valueOf(value);
                }
                when 'PICKLIST' {
                    return String.valueOf(value);
                }
                when 'REFERENCE' {
                    if (value instanceof String) {
                        return Id.valueOf((String) value);
                    }
                    return (Id) value;
                }
                when else {
                    return value;
                }
            }
        } catch (Exception e) {
            // Type conversion failed - returning original value
            return value;
        }
    }
    
    /**
     * @description Apply transformation to field value
     * @param value The value to transform
     * @param transformation Transformation rule
     * @return Transformed value
     */
    private static Object applyTransformation(Object value, String transformation) {
        if (value == null || String.isBlank(transformation)) {
            return value;
        }
        
        String stringValue = String.valueOf(value);
        
        try {
            switch on transformation.toLowerCase() {
                when 'uppercase' {
                    return stringValue.toUpperCase();
                }
                when 'lowercase' {
                    return stringValue.toLowerCase();
                }
                when 'trim' {
                    return stringValue.trim();
                }
                when 'capitalize' {
                    return stringValue.capitalize();
                }
                when 'remove_spaces' {
                    return stringValue.replaceAll('\\s+', '');
                }
                when 'sanitize' {
                    return RouteLogicSecurityUtils.preventXSS(stringValue);
                }
                when else {
                    // Custom transformation logic could be added here
                    return value;
                }
            }
        } catch (Exception e) {
            // Transformation failed - returning original value
            return value;
        }
    }
    
    /**
     * @description Validate field value against rules
     * @param value The value to validate
     * @param validationRules List of validation rules
     * @return True if validation passes
     */
    private static Boolean validateFieldValue(Object value, List<String> validationRules) {
        if (value == null || validationRules == null || validationRules.isEmpty()) {
            return true;
        }
        
        String stringValue = String.valueOf(value);
        
        for (String rule : validationRules) {
            if (!applyValidationRule(stringValue, rule)) {
                return false;
            }
        }
        
        return true;
    }
    
    /**
     * @description Apply single validation rule
     * @param value The value to validate
     * @param rule Validation rule
     * @return True if validation passes
     */
    private static Boolean applyValidationRule(String value, String rule) {
        if (String.isBlank(rule)) {
            return true;
        }
        
        try {
            if (rule.startsWith('required')) {
                return String.isNotBlank(value);
            } else if (rule.startsWith('min_length:')) {
                Integer minLength = Integer.valueOf(rule.substring(11));
                return value.length() >= minLength;
            } else if (rule.startsWith('max_length:')) {
                Integer maxLength = Integer.valueOf(rule.substring(11));
                return value.length() <= maxLength;
            } else if (rule.startsWith('pattern:')) {
                String pattern = rule.substring(8);
                return Pattern.matches(pattern, value);
            } else if (rule.startsWith('email')) {
                return isValidEmail(value);
            } else if (rule.startsWith('phone')) {
                return isValidPhone(value);
            }
            
            return true;
            
        } catch (Exception e) {
            // Validation rule failed
            return false;
        }
    }
    
    /**
     * @description Get field mappings between objects
     * @param sourceObjectType Source object API name
     * @param targetObjectType Target object API name
     * @return Map of field mappings
     */
    private static Map<String, FieldMapping> getFieldMappings(String sourceObjectType, String targetObjectType) {
        String mappingKey = sourceObjectType + '_to_' + targetObjectType;
        
        if (fieldMappingCache.containsKey(mappingKey)) {
            return fieldMappingCache.get(mappingKey);
        }
        
        Map<String, FieldMapping> mappings = new Map<String, FieldMapping>();
        
        try {
            // Load mappings from configuration
            List<RouteLogic_Configuration__mdt> mappingConfigs = [
                SELECT DeveloperName, Configuration_Value__c
                FROM RouteLogic_Configuration__mdt
                WHERE Configuration_Type__c = 'Field_Mapping'
                AND DeveloperName LIKE :(mappingKey + '%')
                WITH SECURITY_ENFORCED
            ];
            
            for (RouteLogic_Configuration__mdt config : mappingConfigs) {
                try {
                    FieldMapping mapping = (FieldMapping) JSON.deserialize(
                        config.Configuration_Value__c, FieldMapping.class);
                    mappings.put(mapping.targetField, mapping);
                } catch (Exception e) {
                    // Failed to parse field mapping configuration
                }
            }
            
            // If no custom mappings found, use default mappings
            if (mappings.isEmpty()) {
                mappings = getDefaultFieldMappings(sourceObjectType, targetObjectType);
            }
            
            // Cache the mappings
            fieldMappingCache.put(mappingKey, mappings);
            
        } catch (Exception e) {
            ErrorLogService.logError('RouteLogicFieldMapper.getFieldMappings', e, 'Failed to get field mappings');
        }
        
        return mappings;
    }
    
    /**
     * @description Get default field mappings
     * @param sourceObjectType Source object API name
     * @param targetObjectType Target object API name
     * @return Map of default field mappings
     */
    private static Map<String, FieldMapping> getDefaultFieldMappings(String sourceObjectType, String targetObjectType) {
        Map<String, FieldMapping> mappings = new Map<String, FieldMapping>();
        
        // Standard field mappings between Case and Lead
        if ((sourceObjectType == 'Case' && targetObjectType == 'Lead') ||
            (sourceObjectType == 'Lead' && targetObjectType == 'Case')) {
            
            // Subject mapping
            FieldMapping subjectMapping = new FieldMapping();
            subjectMapping.sourceField = sourceObjectType == 'Case' ? 'Subject' : 'Company';
            subjectMapping.targetField = targetObjectType == 'Case' ? 'Subject' : 'Company';
            subjectMapping.sourceType = FIELD_TYPE_TEXT;
            subjectMapping.targetType = FIELD_TYPE_TEXT;
            mappings.put(subjectMapping.targetField, subjectMapping);
            
            // Description mapping
            FieldMapping descMapping = new FieldMapping();
            descMapping.sourceField = 'Description';
            descMapping.targetField = 'Description';
            descMapping.sourceType = FIELD_TYPE_TEXT;
            descMapping.targetType = FIELD_TYPE_TEXT;
            mappings.put(descMapping.targetField, descMapping);
            
            // Owner mapping
            FieldMapping ownerMapping = new FieldMapping();
            ownerMapping.sourceField = 'OwnerId';
            ownerMapping.targetField = 'OwnerId';
            ownerMapping.sourceType = FIELD_TYPE_REFERENCE;
            ownerMapping.targetType = FIELD_TYPE_REFERENCE;
            mappings.put(ownerMapping.targetField, ownerMapping);
        }
        
        return mappings;
    }
    
    /**
     * @description Apply custom mapping rules
     * @param baseMappings Base field mappings
     * @param customRules Custom mapping rules
     * @return Updated field mappings
     */
    private static Map<String, FieldMapping> applyCustomMappingRules(Map<String, FieldMapping> baseMappings, 
                                                                    Map<String, String> customRules) {
        Map<String, FieldMapping> updatedMappings = baseMappings.clone();
        
        for (String targetField : customRules.keySet()) {
            String sourceField = customRules.get(targetField);
            
            FieldMapping customMapping = new FieldMapping();
            customMapping.sourceField = sourceField;
            customMapping.targetField = targetField;
            customMapping.sourceType = FIELD_TYPE_TEXT; // Default, could be enhanced
            customMapping.targetType = FIELD_TYPE_TEXT; // Default, could be enhanced
            
            updatedMappings.put(targetField, customMapping);
        }
        
        return updatedMappings;
    }
    
    /**
     * @description Initialize field mapping cache
     */
    private static void initializeCache() {
        try {
            // Initialize schema cache
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            schemaCache.putAll(globalDescribe);
            
            cacheInitialized = true;
            // Field mapping cache initialized successfully
            
        } catch (Exception e) {
            ErrorLogService.logError('RouteLogicFieldMapper.initializeCache', e, 'Failed to initialize field mapping cache');
            cacheInitialized = true; // Prevent infinite retry
        }
    }
    
    /**
     * @description Validate email format
     * @param email Email address to validate
     * @return True if valid email format
     */
    private static Boolean isValidEmail(String email) {
        if (String.isBlank(email)) {
            return false;
        }
        
        String emailPattern = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$';
        return Pattern.matches(emailPattern, email);
    }
    
    /**
     * @description Validate phone format
     * @param phone Phone number to validate
     * @return True if valid phone format
     */
    private static Boolean isValidPhone(String phone) {
        if (String.isBlank(phone)) {
            return false;
        }
        
        // Remove common phone formatting characters
        String cleanPhone = phone.replaceAll('[^0-9+]', '');
        
        // Basic phone validation (10+ digits)
        return cleanPhone.length() >= 10;
    }
    
    /**
     * @description Get field type from schema
     * @param objectType Object API name
     * @param fieldName Field API name
     * @return Field type string
     */
    public static String getFieldType(String objectType, String fieldName) {
        if (String.isBlank(objectType) || String.isBlank(fieldName)) {
            return FIELD_TYPE_TEXT;
        }
        
        try {
            if (!cacheInitialized) {
                initializeCache();
            }
            
            Schema.SObjectType sObjectType = schemaCache.get(objectType);
            if (sObjectType == null) {
                return FIELD_TYPE_TEXT;
            }
            
            Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();
            Schema.SObjectField field = fieldMap.get(fieldName);
            
            if (field == null) {
                return FIELD_TYPE_TEXT;
            }
            
            Schema.DisplayType displayType = field.getDescribe().getType();
            
            switch on displayType {
                when STRING, TEXTAREA, EMAIL, PHONE, URL {
                    return FIELD_TYPE_TEXT;
                }
                when INTEGER, LONG, DOUBLE, CURRENCY, PERCENT {
                    return FIELD_TYPE_NUMBER;
                }
                when DATE {
                    return FIELD_TYPE_DATE;
                }
                when DATETIME {
                    return FIELD_TYPE_DATETIME;
                }
                when BOOLEAN {
                    return FIELD_TYPE_BOOLEAN;
                }
                when PICKLIST, MULTIPICKLIST {
                    return FIELD_TYPE_PICKLIST;
                }
                when REFERENCE {
                    return FIELD_TYPE_REFERENCE;
                }
                when else {
                    return FIELD_TYPE_TEXT;
                }
            }
            
        } catch (Exception e) {
            // Failed to get field type - returning default TEXT type
            return FIELD_TYPE_TEXT;
        }
    }
    
    /**
     * @description Refresh field mapping cache
     */
    public static void refreshCache() {
        fieldMappingCache.clear();
        schemaCache.clear();
        cacheInitialized = false;
        initializeCache();
    }
    
    /**
     * @description Clear field mapping cache (for testing)
     */
    @TestVisible
    private static void clearCache() {
        fieldMappingCache.clear();
        schemaCache.clear();
        cacheInitialized = false;
    }
    
    // Inner classes
    
    /**
     * @description Field mapping configuration
     */
    public class FieldMapping {
        public String sourceField;
        public String targetField;
        public String sourceType;
        public String targetType;
        public String transformation;
        public List<String> validationRules;
        public Object defaultValue;
        public Boolean required;
    }
    
    // Custom exceptions
    public class FieldMappingException extends Exception {}
}

