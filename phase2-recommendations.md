# Phase 2 Actionable Recommendations

## Priority 1: Critical Security Fixes (Immediate)

### 1. Fix SQL Injection in AIBulkOperationService

**File**: AIBulkOperationService.cls
**Location**: Line 255

**Current Code**:
```apex
String query = 'SELECT Id FROM ' + String.escapeSingleQuotes(objectType);
if (String.isNotBlank(whereClause)) {
    query += ' WHERE ' + whereClause;
}
```

**Fixed Code**:
```apex
// Option 1: Use dynamic SOQL with bind variables
public static BulkOperationResult updateFieldBulk(
    String objectType,
    String fieldName,
    Object fieldValue,
    Map<String, Object> whereParams,
    BulkConfig config
) {
    // Validate object and field names against schema
    Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(objectType);
    if (sObjType == null) {
        throw new SecurityException('Invalid object type: ' + objectType);
    }
    
    // Build safe query
    String query = 'SELECT Id FROM ' + sObjType.getDescribe().getName();
    if (whereParams != null && !whereParams.isEmpty()) {
        query += ' WHERE ';
        List<String> conditions = new List<String>();
        for (String param : whereParams.keySet()) {
            conditions.add(param + ' = :' + param);
        }
        query += String.join(conditions, ' AND ');
    }
    query += ' LIMIT 50000';
    
    // Execute with bind variables
    List<SObject> records = Database.queryWithBinds(query, whereParams, AccessLevel.USER_MODE);
    // ... rest of method
}
```

### 2. Fix CORS Header in AIWebhookService

**File**: AIWebhookService.cls
**Location**: Line 341

**Current Code**:
```apex
res.addHeader('Access-Control-Allow-Origin', 'none');
```

**Fixed Code**:
```apex
// Remove the invalid CORS header entirely, or set to specific origin
// Option 1: Remove (recommended for webhooks)
// res.addHeader('Access-Control-Allow-Origin', 'none'); // REMOVE THIS LINE

// Option 2: Set to specific trusted origin if needed
// res.addHeader('Access-Control-Allow-Origin', 'https://trusted-domain.com');
```

### 3. Fix IP Spoofing Vulnerability

**File**: SecurityAuditService.cls
**Location**: Lines 224-230

**Current Code**:
```apex
info.ipAddress = headers.get('X-Forwarded-For');
if (String.isBlank(info.ipAddress)) {
    info.ipAddress = headers.get('X-Real-IP');
}
```

**Fixed Code**:
```apex
private static String extractTrustedIP(Map<String, String> headers) {
    // Get the X-Forwarded-For header
    String xForwardedFor = headers.get('X-Forwarded-For');
    
    if (String.isNotBlank(xForwardedFor)) {
        // X-Forwarded-For format: client, proxy1, proxy2
        // Take the last IP (most trusted proxy)
        List<String> ips = xForwardedFor.split(',');
        if (!ips.isEmpty()) {
            // Get last IP and trim whitespace
            String lastIP = ips[ips.size() - 1].trim();
            
            // Validate IP format
            if (isValidIPAddress(lastIP)) {
                return lastIP;
            }
        }
    }
    
    // Fallback to X-Real-IP if available
    String xRealIP = headers.get('X-Real-IP');
    if (String.isNotBlank(xRealIP) && isValidIPAddress(xRealIP)) {
        return xRealIP;
    }
    
    return 'Unknown';
}

private static Boolean isValidIPAddress(String ip) {
    // IPv4 validation
    String ipv4Pattern = '^\\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}' +
                        '(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\b$';
    return Pattern.matches(ipv4Pattern, ip);
}
```

## Priority 2: High Priority Fixes

### 4. Add Missing FLS Checks in AIBulkOperationService

**File**: AIBulkOperationService.cls
**Location**: Lines 166-180

**Current Code**:
```apex
for (Map<String, Object> row : dataRows) {
    SObject record = targetType.newSObject();
    // ... field mapping
    records.add(record);
}
```

**Fixed Code**:
```apex
// Add FLS check before processing
Set<String> targetFields = new Set<String>();
for (String sourceField : fieldMapping.keySet()) {
    targetFields.add(fieldMapping.get(sourceField));
}

// Validate field access
RouteLogicSecurityUtils.validateFieldAccess(
    objectType, 
    targetFields, 
    RouteLogicSecurityUtils.AccessType.CREATABLE
);

// Process records with stripInaccessible
for (Map<String, Object> row : dataRows) {
    SObject record = targetType.newSObject();
    // ... field mapping
    records.add(record);
}

// Apply security before DML
records = RouteLogicSecurityUtils.stripInaccessibleFields(
    RouteLogicSecurityUtils.AccessType.CREATABLE,
    records
);
```

### 5. Implement Dynamic Cache Namespace

**File**: Multiple files
**Solution**: Create a utility class

```apex
public class CacheUtils {
    private static String namespacePrefix;
    
    public static String getNamespacePrefix() {
        if (namespacePrefix == null) {
            // Get namespace dynamically
            String className = CacheUtils.class.getName();
            if (className.contains('.')) {
                namespacePrefix = className.substringBefore('.') + '.';
            } else {
                namespacePrefix = '';
            }
        }
        return namespacePrefix;
    }
    
    public static Cache.OrgPartition getPartition(String partitionName) {
        String fullName = getNamespacePrefix() + partitionName;
        return Cache.Org.getPartition(fullName);
    }
}
```

**Usage**:
```apex
// Replace this:
Cache.OrgPartition orgPart = Cache.Org.getPartition('routelogic.RateLimits');

// With this:
Cache.OrgPartition orgPart = CacheUtils.getPartition('RateLimits');
```

### 6. Add Rate Limiting to Webhooks

**File**: AIWebhookService.cls
**Location**: After line 43

**Add Code**:
```apex
// Add rate limiting check
String provider = extractProviderFromPath(req.requestURI);
String clientIP = SecurityAuditService.getCurrentIPAddress();

if (!RateLimitService.checkRateLimit('WEBHOOK_RECEIVE', clientIP)) {
    sendErrorResponse(res, 429, 'Rate limit exceeded');
    return;
}
```

## Priority 3: Medium Priority Enhancements

### 7. Complete SecureKeyVault Implementation

**File**: SecureKeyVault.cls
**Location**: Lines 185-192

**Complete Implementation**:
```apex
private static void storeKeyMetadata(String keyName, String saltHex) {
    // Create a custom setting record for key metadata
    Key_Metadata__c metadata = new Key_Metadata__c();
    metadata.Name = keyName;
    metadata.Salt__c = saltHex;
    metadata.Created_Date__c = DateTime.now();
    metadata.Key_Version__c = '1.0';
    
    try {
        upsert metadata Name;
    } catch (Exception e) {
        // If custom settings don't exist, log for manual configuration
        System.debug(LoggingLevel.ERROR, 
            'Key metadata storage failed. Please create Key_Metadata__c custom setting.');
        
        // Store in Platform Cache as fallback
        Cache.OrgPartition orgPart = CacheUtils.getPartition('KeyMetadata');
        if (orgPart != null) {
            Map<String, Object> keyMeta = new Map<String, Object>{
                'salt' => saltHex,
                'created' => DateTime.now(),
                'version' => '1.0'
            };
            orgPart.put('META_' + keyName, keyMeta, 86400); // 24 hour TTL
        }
    }
}
```

### 8. Implement Log Sanitization

**File**: SecurityAuditService.cls
**Location**: Line 64

**Current Code**:
```apex
Event_Details__c = JSON.serializePretty(details)
```

**Fixed Code**:
```apex
Event_Details__c = JSON.serializePretty(sanitizeEventDetails(details))

private static Map<String, Object> sanitizeEventDetails(Map<String, Object> details) {
    Map<String, Object> sanitized = new Map<String, Object>();
    
    Set<String> sensitiveFields = new Set<String>{
        'password', 'token', 'secret', 'key', 'ssn', 'creditcard'
    };
    
    for (String key : details.keySet()) {
        String lowerKey = key.toLowerCase();
        Boolean isSensitive = false;
        
        for (String sensitive : sensitiveFields) {
            if (lowerKey.contains(sensitive)) {
                isSensitive = true;
                break;
            }
        }
        
        if (isSensitive) {
            sanitized.put(key, '[REDACTED]');
        } else {
            Object value = details.get(key);
            if (value instanceof String) {
                // Mask potential PII patterns
                String strValue = (String) value;
                strValue = strValue.replaceAll('\\b\\d{3}-\\d{2}-\\d{4}\\b', '[SSN]');
                strValue = strValue.replaceAll('\\b\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}\\b', '[CC]');
                sanitized.put(key, strValue);
            } else {
                sanitized.put(key, value);
            }
        }
    }
    
    return sanitized;
}
```

## Priority 4: Low Priority Improvements

### 9. Update Version Strings

**Files**: Multiple
**Action**: Global find and replace
- Find: `RouteLogic/3.3.0`
- Replace: `RouteLogic/4.0.0`

### 10. Implement Log Retention

**File**: Create new scheduled class

```apex
public class SecurityLogCleanupSchedulable implements Schedulable {
    private static final Integer RETENTION_DAYS = 90;
    
    public void execute(SchedulableContext ctx) {
        cleanupOldLogs();
    }
    
    @future
    private static void cleanupOldLogs() {
        DateTime cutoffDate = DateTime.now().addDays(-RETENTION_DAYS);
        
        // Delete old audit logs
        List<Security_Audit_Log__c> oldLogs = [
            SELECT Id 
            FROM Security_Audit_Log__c 
            WHERE CreatedDate < :cutoffDate
            LIMIT 10000
        ];
        
        if (!oldLogs.isEmpty()) {
            delete oldLogs;
        }
        
        // Archive important logs before deletion (optional)
        // This could involve exporting to external storage
    }
    
    // Schedule the job
    public static void scheduleCleanup() {
        String cronExp = '0 0 2 * * ?'; // Run at 2 AM daily
        System.schedule('Security Log Cleanup', cronExp, new SecurityLogCleanupSchedulable());
    }
}
```

## Testing Requirements

### Unit Tests for Security Fixes

```apex
@isTest
private class SecurityFixesTest {
    
    @isTest
    static void testSQLInjectionFix() {
        // Test with malicious where clause
        Map<String, Object> whereParams = new Map<String, Object>{
            'Status__c' => 'Active',
            'Priority__c' => 'High'
        };
        
        Test.startTest();
        BulkOperationResult result = AIBulkOperationService.updateFieldBulk(
            'Case',
            'Status__c',
            'Closed',
            whereParams,
            new AIBulkOperationService.BulkConfig()
        );
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        System.assertEquals(true, result.success);
    }
    
    @isTest
    static void testIPValidation() {
        // Test valid IPs
        System.assertEquals(true, SecurityAuditService.isValidIPAddress('192.168.1.1'));
        System.assertEquals(true, SecurityAuditService.isValidIPAddress('10.0.0.1'));
        
        // Test invalid IPs
        System.assertEquals(false, SecurityAuditService.isValidIPAddress('999.999.999.999'));
        System.assertEquals(false, SecurityAuditService.isValidIPAddress('not.an.ip'));
    }
}
```

## Deployment Checklist

1. **Create Custom Objects/Fields**:
   - Security_Audit_Log__c (if not exists)
   - Security_Alert__e platform event
   - Key_Metadata__c custom setting

2. **Configure Platform Cache**:
   ```
   Setup > Platform Cache > New Partition
   - Name: RateLimits
   - Size: 10MB minimum
   
   - Name: KeyMetadata  
   - Size: 5MB minimum
   ```

3. **Update Permission Sets**:
   - Add access to new objects
   - Grant Platform Cache permissions

4. **Deploy in Order**:
   1. Custom objects and fields
   2. Utility classes (CacheUtils)
   3. Updated security classes
   4. Test classes
   5. Schedule cleanup job

5. **Post-Deployment**:
   - Run all tests
   - Verify 85%+ code coverage
   - Test rate limiting
   - Monitor security logs

## Performance Testing

```apex
// Test high-volume scenarios
@isTest
static void testBulkProcessingAt10KScale() {
    List<Case> testCases = new List<Case>();
    for (Integer i = 0; i < 10000; i++) {
        testCases.add(new Case(
            Subject = 'Test Case ' + i,
            Priority = 'High'
        ));
    }
    insert testCases;
    
    Test.startTest();
    List<Id> caseIds = new List<Id>();
    for (Case c : testCases) {
        caseIds.add(c.Id);
    }
    
    List<Id> jobIds = BulkProcessingOptimizer.optimizeBulkProcessing(caseIds);
    Test.stopTest();
    
    System.assert(!jobIds.isEmpty(), 'Jobs should be queued');
}
```