# SQL Injection Fix Implementation Plan

## Created by: Architect Specialist
## Date: February 5, 2025
## Priority: CRITICAL - AppExchange Blockers

---

## Executive Summary

This plan outlines the approach to fix 3 critical SQL injection vulnerabilities that are blocking AppExchange submission. The fixes will be implemented using whitelist validation patterns while maintaining backward compatibility.

---

## Implementation Strategy

### Core Principles
1. **Whitelist Validation**: All dynamic values must be validated against predefined lists
2. **Custom Metadata**: Use Custom Metadata Types for configuration flexibility
3. **Backward Compatibility**: Preserve existing functionality
4. **Comprehensive Testing**: 95%+ code coverage with security-specific tests

---

## Fix Implementation Details

### 1. LogRetentionBatch.cls

#### Current Vulnerability
```apex
String query = 'SELECT Id FROM ' + String.escapeSingleQuotes(objectName) + 
              ' WHERE ' + dateField + ' < :cutoffDate';
```

#### Proposed Fix
```apex
// Create Custom Metadata Type: Log_Retention_Config__mdt
// Fields: Object_Name__c, Date_Field__c, Is_Active__c

private static Map<String, String> getAllowedObjectsAndFields() {
    Map<String, String> objectFieldMap = new Map<String, String>();
    
    for (Log_Retention_Config__mdt config : [
        SELECT Object_Name__c, Date_Field__c 
        FROM Log_Retention_Config__mdt 
        WHERE Is_Active__c = true
    ]) {
        objectFieldMap.put(config.Object_Name__c, config.Date_Field__c);
    }
    
    return objectFieldMap;
}

public Database.QueryLocator start(Database.BatchableContext bc) {
    Map<String, String> allowedObjects = getAllowedObjectsAndFields();
    
    if (!allowedObjects.containsKey(objectName)) {
        throw new SecurityException('Invalid object for log retention: ' + objectName);
    }
    
    String dateField = allowedObjects.get(objectName);
    
    // Additional validation using Schema
    Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
    if (objType == null) {
        throw new SecurityException('Object does not exist: ' + objectName);
    }
    
    String query = 'SELECT Id FROM ' + objectName + ' WHERE ' + dateField + ' < :cutoffDate WITH SECURITY_ENFORCED';
    return Database.getQueryLocator(query);
}
```

#### Custom Metadata Records Required
```
Object_Name__c: Error_Log__c, Date_Field__c: CreatedDate
Object_Name__c: AI_Audit_Event__c, Date_Field__c: Event_Time__c
Object_Name__c: AI_Processing_Status__c, Date_Field__c: LastModifiedDate
Object_Name__c: AI_Bulk_Processing_Metrics__c, Date_Field__c: CreatedDate
```

---

### 2. AIQueryOptimizationService.cls

#### Current Vulnerability
```apex
// Assumed structure based on description
String query = buildOptimizedQuery(objectName, fields, conditions);
```

#### Proposed Fix
```apex
// Create Custom Metadata Type: AI_Query_Config__mdt
// Fields: Object_Name__c, Allowed_Fields__c, Query_Type__c, Is_Active__c

public class AIQueryOptimizationService {
    
    private static final Map<String, Set<String>> ALLOWED_OBJECTS_AND_FIELDS;
    
    static {
        ALLOWED_OBJECTS_AND_FIELDS = loadAllowedConfiguration();
    }
    
    private static Map<String, Set<String>> loadAllowedConfiguration() {
        Map<String, Set<String>> configMap = new Map<String, Set<String>>();
        
        for (AI_Query_Config__mdt config : [
            SELECT Object_Name__c, Allowed_Fields__c 
            FROM AI_Query_Config__mdt 
            WHERE Is_Active__c = true
        ]) {
            Set<String> fields = new Set<String>();
            if (String.isNotBlank(config.Allowed_Fields__c)) {
                fields.addAll(config.Allowed_Fields__c.split(','));
            }
            configMap.put(config.Object_Name__c, fields);
        }
        
        return configMap;
    }
    
    public String buildOptimizedQuery(String objectName, List<String> fields, String conditions) {
        // Validate object
        if (!ALLOWED_OBJECTS_AND_FIELDS.containsKey(objectName)) {
            throw new SecurityException('Invalid object for query optimization: ' + objectName);
        }
        
        // Validate fields
        Set<String> allowedFields = ALLOWED_OBJECTS_AND_FIELDS.get(objectName);
        for (String field : fields) {
            if (!allowedFields.contains(field)) {
                throw new SecurityException('Invalid field for object ' + objectName + ': ' + field);
            }
        }
        
        // Build query safely
        String fieldList = String.join(fields, ', ');
        String query = 'SELECT ' + fieldList + ' FROM ' + objectName;
        
        if (String.isNotBlank(conditions)) {
            // Parse and validate conditions separately
            query += ' WHERE ' + validateAndSanitizeConditions(conditions);
        }
        
        query += ' WITH SECURITY_ENFORCED';
        
        return query;
    }
    
    private String validateAndSanitizeConditions(String conditions) {
        // Implement condition validation logic
        // This is a complex topic - consider using a proper query parser
        return conditions; // Placeholder - needs proper implementation
    }
}
```

---

### 3. AIMobilePerformanceService.cls

#### Current Vulnerability
```apex
// Assumed structure based on description
public void processPerformanceData(String objectType, Map<String, Object> data) {
    Type dynamicType = Type.forName(objectType);
    // Processing logic
}
```

#### Proposed Fix
```apex
// Create Enum for allowed types
public enum AllowedPerformanceTypes {
    CASE_PERFORMANCE,
    USER_PERFORMANCE,
    AGENT_PERFORMANCE,
    QUEUE_PERFORMANCE
}

// Create mapping to actual objects
private static final Map<AllowedPerformanceTypes, String> TYPE_TO_OBJECT = new Map<AllowedPerformanceTypes, String>{
    AllowedPerformanceTypes.CASE_PERFORMANCE => 'Case',
    AllowedPerformanceTypes.USER_PERFORMANCE => 'User',
    AllowedPerformanceTypes.AGENT_PERFORMANCE => 'AI_Agent_Performance__c',
    AllowedPerformanceTypes.QUEUE_PERFORMANCE => 'Queue_Performance__c'
};

public void processPerformanceData(String performanceTypeStr, Map<String, Object> data) {
    AllowedPerformanceTypes perfType;
    
    try {
        perfType = AllowedPerformanceTypes.valueOf(performanceTypeStr.toUpperCase());
    } catch (Exception e) {
        throw new SecurityException('Invalid performance type: ' + performanceTypeStr);
    }
    
    String objectName = TYPE_TO_OBJECT.get(perfType);
    
    // Use Schema to safely get the SObjectType
    Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
    if (objType == null) {
        throw new SecurityException('Object type not found: ' + objectName);
    }
    
    // Process data using the validated type
    processValidatedData(objType, data);
}

private void processValidatedData(Schema.SObjectType objType, Map<String, Object> data) {
    // Safe processing logic here
    SObject record = objType.newSObject();
    
    // Validate and set field values
    Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
    
    for (String fieldName : data.keySet()) {
        if (fieldMap.containsKey(fieldName)) {
            Schema.SObjectField field = fieldMap.get(fieldName);
            if (field.getDescribe().isUpdateable()) {
                record.put(fieldName, data.get(fieldName));
            }
        }
    }
    
    // Process the record with security enforced
    insert Security.stripInaccessible(AccessType.CREATABLE, new List<SObject>{record}).getRecords();
}
```

---

## Implementation Tasks

### Phase 1: Setup (Day 1)
1. Create Custom Metadata Types:
   - Log_Retention_Config__mdt
   - AI_Query_Config__mdt
2. Create and deploy metadata records
3. Set up version control branch for fixes

### Phase 2: Implementation (Day 2-3)
1. Implement LogRetentionBatch fix
2. Implement AIQueryOptimizationService fix
3. Implement AIMobilePerformanceService fix
4. Update any dependent classes

### Phase 3: Testing (Day 4-5)
1. Create comprehensive test classes:
   - LogRetentionBatchSecurityTest
   - AIQueryOptimizationServiceSecurityTest
   - AIMobilePerformanceServiceSecurityTest
2. Test SQL injection prevention
3. Test backward compatibility
4. Performance testing

### Phase 4: Validation (Day 6)
1. Run AppExchange Security Scanner
2. Fix any additional issues found
3. Code review with security focus
4. Documentation updates

---

## Test Strategy

### Security Test Cases
```apex
@isTest
private class LogRetentionBatchSecurityTest {
    
    @isTest
    static void testSQLInjectionPrevention() {
        // Setup
        Test.startTest();
        
        // Test malicious object name
        try {
            LogRetentionBatch batch = new LogRetentionBatch();
            batch.objectName = 'Account WHERE 1=1; DELETE FROM Account;--';
            batch.start(null);
            System.assert(false, 'Should have thrown SecurityException');
        } catch (SecurityException e) {
            System.assert(e.getMessage().contains('Invalid object'));
        }
        
        // Test non-existent object
        try {
            LogRetentionBatch batch = new LogRetentionBatch();
            batch.objectName = 'NonExistentObject__c';
            batch.start(null);
            System.assert(false, 'Should have thrown SecurityException');
        } catch (SecurityException e) {
            System.assert(e.getMessage().contains('Invalid object'));
        }
        
        Test.stopTest();
    }
    
    @isTest
    static void testValidObjectProcessing() {
        // Setup test data
        Log_Retention_Config__mdt config = new Log_Retention_Config__mdt(
            Object_Name__c = 'Error_Log__c',
            Date_Field__c = 'CreatedDate',
            Is_Active__c = true
        );
        
        Test.startTest();
        
        LogRetentionBatch batch = new LogRetentionBatch();
        batch.objectName = 'Error_Log__c';
        
        Database.QueryLocator ql = batch.start(null);
        System.assertNotEquals(null, ql, 'Should return valid query locator');
        
        Test.stopTest();
    }
}
```

---

## Rollback Plan

If issues are discovered post-deployment:

1. **Immediate Rollback**: Revert to previous version using Git
2. **Data Recovery**: No data changes expected, but monitor for issues
3. **Communication**: Notify all stakeholders
4. **Root Cause Analysis**: Investigate and fix issues
5. **Re-deployment**: After fixes and additional testing

---

## Success Criteria

1. ✅ All 3 SQL injection vulnerabilities fixed
2. ✅ AppExchange Security Scanner passes
3. ✅ 95%+ code coverage maintained
4. ✅ No regression in functionality
5. ✅ Performance unchanged or improved
6. ✅ All security tests pass

---

## Risk Mitigation

1. **Testing Environment**: Full sandbox testing before production
2. **Gradual Rollout**: Deploy to subset of users first
3. **Monitoring**: Enhanced logging during initial deployment
4. **Backup**: Full org backup before deployment
5. **Communication**: Clear documentation for administrators

---

## Next Steps

1. **Architect Handoff**: Plan complete, ready for implementation
2. **Implementer Role**: Execute the fixes as specified
3. **Debugger Role**: Validate security patterns
4. **Reviewer Role**: Final security validation

---

*Implementation plan created by Architect specialist - Ready for handoff to Implementer*