/**
 * @description Security utility class for field-level security operations
 * @author RouteLogic Team
 * @date 2025-01-17
 */
@namespaceAccessible
public with sharing class SecurityUtils {
    
    /**
     * @description Strip inaccessible records based on access type
     * @param accessType The type of access to check (CREATABLE, UPDATABLE, etc.)
     * @param records List of records to check
     * @return List of accessible records
     */
    public static List<SObject> stripInaccessibleRecords(
        System.AccessType accessType, 
        List<SObject> records
    ) {
        if (records == null || records.isEmpty()) {
            return records;
        }
        
        try {
            SObjectAccessDecision decision = Security.stripInaccessible(
                accessType,
                records
            );
            
            return decision.getRecords();
        } catch (Exception e) {
            // Log security exception
            ErrorLogService.logError(
                'SecurityUtils.stripInaccessibleRecords',
                e,
                'Failed to strip inaccessible records for type: ' + accessType
            );
            throw new SecurityException(
                'Insufficient permissions to access required fields'
            );
        }
    }
    
    /**
     * @description Check if user has read access to specific fields
     * @param objectType The SObject type
     * @param fieldNames Set of field API names
     * @return Boolean indicating if all fields are readable
     */
    public static Boolean hasReadAccess(
        Schema.SObjectType objectType,
        Set<String> fieldNames
    ) {
        Schema.DescribeSObjectResult objectDescribe = objectType.getDescribe();
        Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();
        
        for (String fieldName : fieldNames) {
            if (fieldMap.containsKey(fieldName)) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                if (!fieldDescribe.isAccessible()) {
                    return false;
                }
            }
        }
        
        return true;
    }
    
    /**
     * @description Check if user has create access to specific fields
     * @param objectType The SObject type
     * @param fieldNames Set of field API names
     * @return Boolean indicating if all fields are creatable
     */
    public static Boolean hasCreateAccess(
        Schema.SObjectType objectType,
        Set<String> fieldNames
    ) {
        Schema.DescribeSObjectResult objectDescribe = objectType.getDescribe();
        
        if (!objectDescribe.isCreateable()) {
            return false;
        }
        
        Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();
        
        for (String fieldName : fieldNames) {
            if (fieldMap.containsKey(fieldName)) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                if (!fieldDescribe.isCreateable()) {
                    return false;
                }
            }
        }
        
        return true;
    }
    
    /**
     * @description Check if user has update access to specific fields
     * @param objectType The SObject type
     * @param fieldNames Set of field API names
     * @return Boolean indicating if all fields are updatable
     */
    public static Boolean hasUpdateAccess(
        Schema.SObjectType objectType,
        Set<String> fieldNames
    ) {
        Schema.DescribeSObjectResult objectDescribe = objectType.getDescribe();
        
        if (!objectDescribe.isUpdateable()) {
            return false;
        }
        
        Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();
        
        for (String fieldName : fieldNames) {
            if (fieldMap.containsKey(fieldName)) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                if (!fieldDescribe.isUpdateable()) {
                    return false;
                }
            }
        }
        
        return true;
    }
    
    /**
     * @description Check if user has delete access to object
     * @param objectType The SObject type
     * @return Boolean indicating if object is deletable
     */
    public static Boolean hasDeleteAccess(Schema.SObjectType objectType) {
        return objectType.getDescribe().isDeletable();
    }
    
    /**
     * @description Custom exception for security violations
     */
    public class SecurityException extends Exception {}
}