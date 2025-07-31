# Phase 3: Critical Security Fixes Implementation Guide

## Overview
This guide provides step-by-step instructions for implementing the critical security fixes identified in the RouteLogic Enhanced v4.0.0 security review.

## Critical Fix #1: SQL Injection Prevention

### File: AIBulkOperationService.cls

#### Current Vulnerable Code (Line 255):
```apex
public static BulkOperationResult updateFieldBulk(
    String objectType, 
    String fieldName, 
    Object fieldValue, 
    String whereClause, 
    BulkConfig config
) {
    // VULNERABLE CODE
    String query = 'SELECT Id FROM ' + String.escapeSingleQuotes(objectType);
    if (String.isNotBlank(whereClause)) {
        query += ' WHERE ' + whereClause; // SQL INJECTION RISK
    }
    List<SObject> records = Database.query(query);
    // ... rest of method
}
```

#### Secure Implementation:
```apex
public static BulkOperationResult updateFieldBulk(
    String objectType, 
    String fieldName, 
    Object fieldValue, 
    Map<String, Object> whereParams, // Changed from String to Map
    BulkConfig config
) {
    BulkOperationResult result = new BulkOperationResult();
    
    try {
        // Validate object type against schema
        Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(objectType);
        if (sObjType == null) {
            throw new SecurityException('Invalid object type: ' + objectType);
        }
        
        // Validate field name
        Schema.SObjectField field = sObjType.getDescribe().fields.getMap().get(fieldName);
        if (field == null) {
            throw new SecurityException('Invalid field: ' + fieldName);
        }
        
        // Build secure query with bind variables
        String query = 'SELECT Id FROM ' + sObjType.getDescribe().getName();
        
        if (whereParams != null && !whereParams.isEmpty()) {
            query += ' WHERE ';
            List<String> conditions = new List<String>();
            
            // Build conditions with bind variable placeholders
            for (String paramName : whereParams.keySet()) {
                // Validate field exists
                if (!sObjType.getDescribe().fields.getMap().containsKey(paramName)) {
                    throw new SecurityException('Invalid field in where clause: ' + paramName);
                }
                conditions.add(paramName + ' = :param_' + paramName);
            }
            
            query += String.join(conditions, ' AND ');
        }
        
        query += ' WITH SECURITY_ENFORCED LIMIT 50000';
        
        // Prepare bind variables map
        Map<String, Object> bindVars = new Map<String, Object>();
        if (whereParams != null) {
            for (String key : whereParams.keySet()) {
                bindVars.put('param_' + key, whereParams.get(key));
            }
        }
        
        // Execute query with bind variables
        List<SObject> records = Database.queryWithBinds(query, bindVars, AccessLevel.USER_MODE);
        
        // Process records...
        // ... rest of implementation
        
    } catch (Exception e) {
        result.success = false;
        result.errors.add(new BulkOperationError(null, e.getMessage()));
    }
    
    return result;
}
```

## Critical Fix #2: CORS Header Configuration

### File: AIWebhookService.cls

#### Current Issue (Line 341):
```apex
private static void setSecurityHeaders(RestResponse res) {
    // ... other headers ...
    res.addHeader('Access-Control-Allow-Origin', 'none'); // INVALID VALUE
}
```

#### Fixed Implementation:
```apex
private static void setSecurityHeaders(RestResponse res) {
    // Security headers for webhook endpoints
    res.addHeader('X-Content-Type-Options', 'nosniff');
    res.addHeader('X-Frame-Options', 'DENY');
    res.addHeader('X-XSS-Protection', '1; mode=block');
    res.addHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
    res.addHeader('Content-Security-Policy', 'default-src \'none\'');
    res.addHeader('Referrer-Policy', 'no-referrer');
    res.addHeader('Permissions-Policy', 'geolocation=(), microphone=(), camera=()');
    res.addHeader('Cache-Control', 'no-store, no-cache, must-revalidate, private');
    res.addHeader('Pragma', 'no-cache');
    res.addHeader('Expires', '0');
    
    // REMOVE THE INVALID CORS HEADER
    // Webhooks typically don't need CORS as they're server-to-server
    // If CORS is needed, use specific origin:
    // res.addHeader('Access-Control-Allow-Origin', 'https://trusted-domain.com');
}
```

## Critical Fix #3: IP Address Validation

### File: SecurityAuditService.cls

#### Current Vulnerable Code (Lines 224-230):
```apex
private static SessionInfo extractSessionInfo(RestRequest req) {
    SessionInfo info = new SessionInfo();
    Map<String, String> headers = req.headers;
    
    // VULNERABLE - Can be spoofed
    info.ipAddress = headers.get('X-Forwarded-For');
    if (String.isBlank(info.ipAddress)) {
        info.ipAddress = headers.get('X-Real-IP');
    }
    
    return info;
}
```

#### Secure Implementation:
```apex
private static SessionInfo extractSessionInfo(RestRequest req) {
    SessionInfo info = new SessionInfo();
    Map<String, String> headers = req.headers;
    
    // Extract trusted IP address
    info.ipAddress = extractTrustedIP(headers);
    info.userAgent = headers.get('User-Agent');
    info.sessionId = UserInfo.getSessionId();
    
    return info;
}

private static String extractTrustedIP(Map<String, String> headers) {
    // Salesforce trusted proxy IPs (example - verify with your setup)
    Set<String> trustedProxies = new Set<String>{
        '10.0.0.0/8',
        '172.16.0.0/12',
        '192.168.0.0/16'
    };
    
    String xForwardedFor = headers.get('X-Forwarded-For');
    
    if (String.isNotBlank(xForwardedFor)) {
        // X-Forwarded-For format: client, proxy1, proxy2
        // Parse from right to left to find first non-proxy IP
        List<String> ips = xForwardedFor.split(',');
        
        // Iterate from right to left
        for (Integer i = ips.size() - 1; i >= 0; i--) {
            String ip = ips[i].trim();
            
            // Validate IP format
            if (isValidIPAddress(ip)) {
                // Check if it's a trusted proxy
                if (!isInTrustedRange(ip, trustedProxies)) {
                    // This is the client IP
                    return ip;
                }
            }
        }
    }
    
    // Fallback to X-Real-IP if available and valid
    String xRealIP = headers.get('X-Real-IP');
    if (String.isNotBlank(xRealIP) && isValidIPAddress(xRealIP)) {
        return xRealIP;
    }
    
    // Final fallback
    return 'Unknown';
}

private static Boolean isValidIPAddress(String ip) {
    // IPv4 validation pattern
    String ipv4Pattern = '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}' +
                        '(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$';
    
    // IPv6 validation pattern (simplified)
    String ipv6Pattern = '^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|' +
                        '([0-9a-fA-F]{1,4}:){1,7}:|' +
                        '([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|' +
                        '::1|::)$';
    
    return Pattern.matches(ipv4Pattern, ip) || Pattern.matches(ipv6Pattern, ip);
}

private static Boolean isInTrustedRange(String ip, Set<String> trustedRanges) {
    // Simplified check - in production, use proper CIDR matching
    // This is a placeholder - implement proper CIDR range checking
    for (String range : trustedRanges) {
        if (ip.startsWith(range.substringBefore('/'))) {
            return true;
        }
    }
    return false;
}
```

## Critical Fix #4: FLS/CRUD Enforcement

### File: AIBulkOperationService.cls

#### Add to the class:
```apex
// Add this method to ensure FLS compliance
private static List<SObject> applyFieldLevelSecurity(
    List<SObject> records, 
    AccessType accessType
) {
    if (records == null || records.isEmpty()) {
        return records;
    }
    
    // Use Security.stripInaccessible to enforce FLS
    SObjectAccessDecision decision = Security.stripInaccessible(
        accessType,
        records,
        true // Enforce FLS
    );
    
    // Log any stripped fields for debugging
    Map<String, Set<String>> strippedFields = decision.getRemovedFields();
    if (!strippedFields.isEmpty()) {
        System.debug('Stripped fields: ' + strippedFields);
        // Could also log to Security Audit
        SecurityAuditService.logSecurityViolation(
            'FLS_FIELDS_STRIPPED',
            new Map<String, Object>{
                'strippedFields' => strippedFields,
                'operation' => accessType.name()
            }
        );
    }
    
    return decision.getRecords();
}
```

#### Update bulk import method:
```apex
public static BulkOperationResult importDataBulk(
    String objectType,
    List<Map<String, Object>> dataRows,
    Map<String, String> fieldMapping,
    BulkConfig config
) {
    BulkOperationResult result = new BulkOperationResult();
    
    try {
        // Validate object access
        if (!RouteLogicSecurityUtils.hasCreateAccess(objectType)) {
            throw new SecurityException('No create access to ' + objectType);
        }
        
        // Get object describe
        Schema.SObjectType targetType = Schema.getGlobalDescribe().get(objectType);
        
        // Create records
        List<SObject> records = new List<SObject>();
        for (Map<String, Object> row : dataRows) {
            SObject record = targetType.newSObject();
            
            // Map fields
            for (String sourceField : fieldMapping.keySet()) {
                String targetField = fieldMapping.get(sourceField);
                if (row.containsKey(sourceField)) {
                    record.put(targetField, row.get(sourceField));
                }
            }
            
            records.add(record);
        }
        
        // Apply FLS before insert
        records = applyFieldLevelSecurity(records, AccessType.CREATABLE);
        
        // Perform bulk insert with allOrNone = false
        Database.SaveResult[] saveResults = Database.insert(records, false);
        
        // Process results
        processSaveResults(saveResults, records, result);
        
    } catch (Exception e) {
        result.success = false;
        result.errors.add(new BulkOperationError(null, e.getMessage()));
    }
    
    return result;
}
```

## Testing the Fixes

### Test Class for SQL Injection Fix:
```apex
@isTest
private class AIBulkOperationServiceSecurityTest {
    
    @isTest
    static void testSQLInjectionPrevention() {
        // Create test data
        List<Case> testCases = new List<Case>();
        for (Integer i = 0; i < 5; i++) {
            testCases.add(new Case(
                Subject = 'Test Case ' + i,
                Status = 'New',
                Priority = 'High'
            ));
        }
        insert testCases;
        
        // Test with safe parameters
        Map<String, Object> whereParams = new Map<String, Object>{
            'Status' => 'New',
            'Priority' => 'High'
        };
        
        Test.startTest();
        AIBulkOperationService.BulkOperationResult result = 
            AIBulkOperationService.updateFieldBulk(
                'Case',
                'Status',
                'Working',
                whereParams,
                new AIBulkOperationService.BulkConfig()
            );
        Test.stopTest();
        
        System.assert(result.success, 'Operation should succeed');
        System.assertEquals(5, result.successCount, 'Should update 5 records');
        
        // Verify updates
        List<Case> updatedCases = [SELECT Status FROM Case WHERE Id IN :testCases];
        for (Case c : updatedCases) {
            System.assertEquals('Working', c.Status, 'Status should be updated');
        }
    }
    
    @isTest
    static void testInvalidFieldPrevention() {
        // Test with invalid field - should throw exception
        Map<String, Object> whereParams = new Map<String, Object>{
            'InvalidField__c' => 'Value'
        };
        
        Test.startTest();
        try {
            AIBulkOperationService.updateFieldBulk(
                'Case',
                'Status',
                'Working',
                whereParams,
                new AIBulkOperationService.BulkConfig()
            );
            System.assert(false, 'Should throw exception for invalid field');
        } catch (SecurityException e) {
            System.assert(e.getMessage().contains('Invalid field'), 
                'Should indicate invalid field');
        }
        Test.stopTest();
    }
}
```

## Deployment Steps

### 1. Create Utility Classes First
Deploy the CacheUtils class to handle dynamic namespacing:
```bash
sfdx force:source:deploy -p force-app/main/default/classes/CacheUtils.cls -u <org-alias>
```

### 2. Update Security Classes
Deploy the updated security classes:
```bash
sfdx force:source:deploy -p force-app/main/default/classes/SecurityAuditService.cls,AIBulkOperationService.cls,AIWebhookService.cls -u <org-alias>
```

### 3. Run Tests
Verify all tests pass:
```bash
sfdx force:apex:test:run -n AIBulkOperationServiceSecurityTest,SecurityAuditServiceTest -u <org-alias> -c -r human
```

### 4. Monitor Deployment
Check for any errors in the deployment:
```bash
sfdx force:apex:log:tail -u <org-alias> --color
```

## Validation Checklist

- [ ] SQL injection fix deployed and tested
- [ ] CORS header removed or corrected
- [ ] IP validation implemented with trusted proxy support
- [ ] FLS/CRUD checks added to all DML operations
- [ ] All unit tests passing
- [ ] No regression in existing functionality
- [ ] Security audit logs showing proper tracking
- [ ] Performance metrics unchanged or improved

## Rollback Plan

If issues occur:
1. Revert to previous version using source control
2. Redeploy original classes
3. Document any issues encountered
4. Adjust fixes based on findings
5. Retest in sandbox before production

---

**Implementation Date**: [To be scheduled]  
**Implemented By**: [Developer name]  
**Verified By**: [QA/Security team]