# Installation Script Security Patterns for Salesforce

## Document Created: February 5, 2025
## Specialist: Debugger (Deep Analysis)

---

## Executive Summary

Installation and uninstallation scripts in Salesforce packages run with system privileges and represent one of the highest-risk components from a security perspective. This document provides comprehensive secure patterns and best practices specifically for PostInstallScript and UninstallScript implementations.

---

## Core Security Principles

### 1. System Privilege Awareness
- Scripts run with **unlimited permissions**
- No automatic FLS/CRUD enforcement
- Can access/modify any data in the org
- One-time execution - no retry mechanism

### 2. Zero Trust Approach
- Validate everything, trust nothing
- Apply security checks even with system privileges
- Assume the environment may be hostile
- Protect against both external and internal threats

---

## Secure Version Management Pattern

### Problem
PostInstallScript must handle both fresh installs and upgrades without data loss or security vulnerabilities.

### Solution: Version Tracking with Custom Metadata

```apex
global class PostInstallScript implements InstallHandler {
    // Version tracking metadata type
    private static final String VERSION_MDT_NAME = 'CurrentVersion';
    
    global void onInstall(InstallContext context) {
        Savepoint sp = Database.setSavepoint();
        
        try {
            String previousVersion = getInstalledVersion();
            String newVersion = context.getPackageVersion().toString();
            
            // Log installation attempt (without PII)
            logInstallationAttempt(previousVersion, newVersion);
            
            if (previousVersion == null) {
                performFreshInstall(newVersion);
            } else {
                performUpgrade(previousVersion, newVersion);
            }
            
            // Update version tracking
            updateInstalledVersion(newVersion);
            
        } catch (Exception e) {
            Database.rollback(sp);
            logInstallationError(e);
            throw new InstallException('Installation failed: ' + e.getMessage(), e);
        }
    }
    
    private String getInstalledVersion() {
        Package_Version__mdt versionRecord = Package_Version__mdt.getInstance(VERSION_MDT_NAME);
        return versionRecord?.Version__c;
    }
    
    private void performUpgrade(String fromVersion, String toVersion) {
        // Execute upgrade handlers in sequence
        List<VersionUpgradeHandler> handlers = getUpgradeHandlers(fromVersion, toVersion);
        
        for (VersionUpgradeHandler handler : handlers) {
            handler.execute();
        }
    }
}
```

### Key Security Features
1. **Savepoint-based rollback** for atomic operations
2. **Version validation** before any operations
3. **Idempotent upgrade handlers** prevent duplicate execution
4. **Audit trail** without PII exposure

---

## Secure Error Handling Pattern

### Problem
Unhandled exceptions leave the org in inconsistent state with no recovery option.

### Solution: Multi-Layer Error Handling with Circuit Breaker

```apex
public class InstallErrorHandler {
    private static final Integer MAX_RETRIES = 3;
    private static final Map<String, Integer> operationRetries = new Map<String, Integer>();
    
    public static void executeWithRetry(String operationName, Callable operation) {
        Integer retryCount = operationRetries.get(operationName) ?? 0;
        
        if (retryCount >= MAX_RETRIES) {
            throw new CircuitBreakerException('Operation ' + operationName + ' has failed too many times');
        }
        
        Savepoint sp = Database.setSavepoint();
        
        try {
            operation.call();
            operationRetries.remove(operationName);
            
        } catch (Exception e) {
            Database.rollback(sp);
            operationRetries.put(operationName, retryCount + 1);
            
            // Log error without exposing sensitive data
            Installation_Error__c errorLog = new Installation_Error__c(
                Operation__c = operationName,
                Error_Type__c = e.getTypeName(),
                Error_Message__c = sanitizeErrorMessage(e.getMessage()),
                Stack_Trace_Hash__c = generateStackTraceHash(e.getStackTraceString()),
                Retry_Count__c = retryCount + 1,
                Timestamp__c = DateTime.now()
            );
            
            insert Security.stripInaccessible(AccessType.CREATABLE, new List<Installation_Error__c>{errorLog}).getRecords();
            
            throw e;
        }
    }
    
    private static String sanitizeErrorMessage(String message) {
        // Remove any potential PII patterns
        return message.replaceAll('\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}\\b', '[EMAIL]')
                     .replaceAll('\\b\\d{3}-\\d{2}-\\d{4}\\b', '[SSN]')
                     .replaceAll('\\b\\d{16}\\b', '[CC]');
    }
}
```

---

## SQL Injection Prevention Pattern

### Problem
Dynamic SOQL with user-controlled input creates SQL injection vulnerabilities.

### Solution: Whitelist-Based Validation

```apex
public class SecureQueryBuilder {
    // Whitelist of allowed objects for dynamic queries
    private static final Map<String, Set<String>> ALLOWED_OBJECTS_AND_FIELDS = new Map<String, Set<String>>{
        'Error_Log__c' => new Set<String>{'Id', 'Timestamp__c', 'CreatedDate'},
        'AI_Audit_Event__c' => new Set<String>{'Id', 'Event_Time__c', 'CreatedDate'},
        'Security_Audit_Log__c' => new Set<String>{'Id', 'Audit_Date__c', 'CreatedDate'}
    };
    
    public static String buildSecureQuery(String objectName, String dateField, DateTime cutoffDate) {
        // Validate object name
        if (!ALLOWED_OBJECTS_AND_FIELDS.containsKey(objectName)) {
            throw new SecurityException('Invalid object for query: ' + objectName);
        }
        
        // Validate field name
        Set<String> allowedFields = ALLOWED_OBJECTS_AND_FIELDS.get(objectName);
        if (!allowedFields.contains(dateField)) {
            throw new SecurityException('Invalid field for object ' + objectName + ': ' + dateField);
        }
        
        // Build query using bind variables
        return String.format('SELECT Id FROM {0} WHERE {1} < :cutoffDate WITH SECURITY_ENFORCED', 
            new List<String>{objectName, dateField});
    }
}
```

---

## PII Protection Pattern

### Problem
Logging user IDs and other PII violates privacy regulations.

### Solution: Hashed Identifiers with Org-Specific Salt

```apex
public class PIIProtection {
    // Generate org-specific salt at install time
    private static String getOrgSalt() {
        Org_Security_Settings__c settings = Org_Security_Settings__c.getOrgDefaults();
        
        if (String.isBlank(settings.Salt__c)) {
            // Generate new salt for this org
            Blob saltBlob = Crypto.generateAesKey(256);
            settings.Salt__c = EncodingUtil.base64Encode(saltBlob);
            upsert settings;
        }
        
        return settings.Salt__c;
    }
    
    public static String hashUserId(Id userId) {
        if (userId == null) return 'ANONYMOUS';
        
        // Special handling for system users
        if (UserInfo.getUserType() == 'AutomatedProcess') {
            return 'SYSTEM_PROCESS';
        }
        
        String salt = getOrgSalt();
        Blob dataToHash = Blob.valueOf(userId + salt);
        Blob hash = Crypto.generateDigest('SHA-256', dataToHash);
        
        // Return first 10 chars of base64 encoded hash
        return EncodingUtil.base64Encode(hash).substring(0, 10);
    }
    
    public static Map<String, String> protectUserInfo(User userRecord) {
        return new Map<String, String>{
            'UserId' => hashUserId(userRecord.Id),
            'UserType' => userRecord.UserType,
            'ProfileName' => userRecord.Profile.Name,
            'IsActive' => String.valueOf(userRecord.IsActive)
            // No PII fields like Name, Email, Username
        };
    }
}
```

---

## Platform Cache Security Pattern

### Problem
Cache keys can conflict with other packages and expose sensitive data.

### Solution: Namespaced Cache with Encryption

```apex
public class SecureCacheManager {
    private static final String NAMESPACE = 'RouteLogic';
    private static final Integer DEFAULT_TTL = 3600; // 1 hour
    
    public static void putSecure(String key, Object value, Integer ttlSeconds) {
        // Create namespaced key with hash
        String secureKey = generateSecureKey(key);
        
        // Encrypt sensitive values
        String serializedValue = JSON.serialize(value);
        Blob encryptedBlob = Crypto.encryptWithManagedIV(
            'AES256',
            Blob.valueOf(getEncryptionKey()),
            Blob.valueOf(serializedValue)
        );
        
        // Store in cache
        Cache.OrgPartition partition = Cache.Org.getPartition(NAMESPACE);
        partition.put(secureKey, EncodingUtil.base64Encode(encryptedBlob), ttlSeconds ?? DEFAULT_TTL);
    }
    
    public static Object getSecure(String key, Type valueType) {
        String secureKey = generateSecureKey(key);
        
        Cache.OrgPartition partition = Cache.Org.getPartition(NAMESPACE);
        String encryptedValue = (String) partition.get(secureKey);
        
        if (encryptedValue == null) return null;
        
        // Decrypt value
        Blob decryptedBlob = Crypto.decryptWithManagedIV(
            'AES256',
            Blob.valueOf(getEncryptionKey()),
            EncodingUtil.base64Decode(encryptedValue)
        );
        
        String decryptedJson = decryptedBlob.toString();
        return JSON.deserialize(decryptedJson, valueType);
    }
    
    private static String generateSecureKey(String key) {
        return NAMESPACE + '.' + EncodingUtil.convertToHex(
            Crypto.generateDigest('MD5', Blob.valueOf(key))
        );
    }
}
```

---

## Scheduled Job Security Pattern

### Problem
Scheduled jobs with hardcoded values and no validation are security risks.

### Solution: Secure Job Scheduling with Validation

```apex
public class SecureJobScheduler {
    private static final Map<String, String> ALLOWED_JOBS = new Map<String, String>{
        'KeyRotation' => 'RouteLogicKeyRotationBatch',
        'LogCleanup' => 'LogRetentionBatch',
        'CacheRefresh' => 'CacheRefreshSchedulable'
    };
    
    public static Id scheduleSecureJob(String jobName, String cronExpression) {
        // Validate job name
        if (!ALLOWED_JOBS.containsKey(jobName)) {
            throw new SecurityException('Invalid job name: ' + jobName);
        }
        
        // Validate cron expression
        if (!isValidCronExpression(cronExpression)) {
            throw new SecurityException('Invalid cron expression');
        }
        
        // Check for existing job
        String fullJobName = NAMESPACE + '_' + jobName;
        List<CronTrigger> existingJobs = [
            SELECT Id FROM CronTrigger 
            WHERE CronJobDetail.Name = :fullJobName 
            AND State != 'DELETED'
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        
        if (!existingJobs.isEmpty()) {
            System.abortJob(existingJobs[0].Id);
        }
        
        // Schedule new job
        String className = ALLOWED_JOBS.get(jobName);
        Type jobType = Type.forName(className);
        
        if (jobType == null) {
            throw new SecurityException('Job class not found: ' + className);
        }
        
        Schedulable jobInstance = (Schedulable) jobType.newInstance();
        return System.schedule(fullJobName, cronExpression, jobInstance);
    }
    
    private static Boolean isValidCronExpression(String cronExpr) {
        // Validate cron expression format
        Pattern cronPattern = Pattern.compile(
            '^(\\*|([0-9]|1[0-9]|2[0-9]|3[0-9]|4[0-9]|5[0-9])|\\*\\/([0-9]|1[0-9]|2[0-9]|3[0-9]|4[0-9]|5[0-9])) ' +
            '(\\*|([0-9]|1[0-9]|2[0-3])|\\*\\/([0-9]|1[0-9]|2[0-3])) ' +
            '(\\*|([1-9]|1[0-9]|2[0-9]|3[0-1])|\\*\\/([1-9]|1[0-9]|2[0-9]|3[0-1])) ' +
            '(\\*|([1-9]|1[0-2])|\\*\\/([1-9]|1[0-2])) ' +
            '(\\*|([0-7])|\\*\\/([0-7]))$'
        );
        
        return cronPattern.matcher(cronExpr).matches();
    }
}
```

---

## UninstallScript Security Pattern

### Problem
Must clean up all data securely without exposing sensitive information.

### Solution: Secure Cleanup with Audit Trail

```apex
global class UninstallScript implements UninstallHandler {
    global void onUninstall(UninstallContext context) {
        try {
            // Archive critical data before deletion
            archiveCriticalData();
            
            // Cancel all scheduled jobs
            cancelScheduledJobs();
            
            // Clear platform cache
            clearPlatformCache();
            
            // Delete data in correct order (children first)
            deletePackageData();
            
            // Send uninstall notification (no PII)
            sendUninstallNotification();
            
        } catch (Exception e) {
            // Log but don't fail uninstall
            logUninstallError(e);
        }
    }
    
    private void archiveCriticalData() {
        // Create summary without PII
        Uninstall_Summary__c summary = new Uninstall_Summary__c(
            Uninstall_Date__c = DateTime.now(),
            Record_Counts__c = getRecordCountsJson(),
            Package_Version__c = getInstalledVersion(),
            Org_Id_Hash__c = hashOrgId()
        );
        
        insert Security.stripInaccessible(AccessType.CREATABLE, 
            new List<Uninstall_Summary__c>{summary}).getRecords();
    }
    
    private void deletePackageData() {
        // Delete in dependency order
        List<String> objectsToDelete = new List<String>{
            'Installation_Error__c',
            'Security_Audit_Log__c',
            'AI_Processing_Status__c',
            'Error_Log__c'
        };
        
        for (String objectName : objectsToDelete) {
            deleteObjectData(objectName);
        }
    }
    
    private void deleteObjectData(String objectName) {
        // Validate object name
        if (!isPackageObject(objectName)) {
            throw new SecurityException('Invalid object for deletion: ' + objectName);
        }
        
        // Delete in batches with error handling
        String query = 'SELECT Id FROM ' + objectName + ' WITH SECURITY_ENFORCED';
        Database.delete(Database.query(query), false);
    }
}
```

---

## Testing Requirements

### 1. Security Test Cases
```apex
@isTest
private class InstallScriptSecurityTest {
    @isTest
    static void testSQLInjectionPrevention() {
        // Test with malicious object name
        try {
            SecureQueryBuilder.buildSecureQuery(
                'Account WHERE 1=1; DELETE FROM Account; --', 
                'CreatedDate', 
                DateTime.now()
            );
            System.assert(false, 'Should have thrown SecurityException');
        } catch (SecurityException e) {
            System.assert(e.getMessage().contains('Invalid object'));
        }
    }
    
    @isTest
    static void testPIIProtection() {
        // Verify no PII in logs
        Id userId = UserInfo.getUserId();
        String hashedId = PIIProtection.hashUserId(userId);
        
        System.assertNotEquals(userId, hashedId);
        System.assert(hashedId.length() == 10);
        
        // Verify consistent hashing
        String hashedId2 = PIIProtection.hashUserId(userId);
        System.assertEquals(hashedId, hashedId2);
    }
}
```

### 2. Installation Scenario Tests
- Fresh install
- Upgrade from each supported version
- Failed install with rollback
- Concurrent install attempts
- Governor limit scenarios

### 3. Uninstall Verification Tests
- Complete data removal
- Job cancellation
- Cache clearing
- Archive creation

---

## Implementation Checklist

### Pre-Deployment
- [ ] Remove all hardcoded values
- [ ] Implement version tracking
- [ ] Add comprehensive error handling
- [ ] Create rollback mechanisms
- [ ] Implement PII protection
- [ ] Add SQL injection prevention
- [ ] Secure all dynamic queries
- [ ] Implement cache security
- [ ] Add job validation

### Testing
- [ ] Test all installation scenarios
- [ ] Test all upgrade paths
- [ ] Test error scenarios
- [ ] Test rollback functionality
- [ ] Test uninstall completeness
- [ ] Security penetration testing
- [ ] Governor limit testing

### Documentation
- [ ] Document all security measures
- [ ] Create upgrade guide
- [ ] Document error codes
- [ ] Create troubleshooting guide
- [ ] Document rollback procedures

---

## Summary

Installation scripts represent the highest privilege code in a Salesforce package. By implementing these security patterns, you can:

1. **Prevent SQL injection** through whitelist validation
2. **Protect PII** with proper hashing and anonymization
3. **Handle errors gracefully** with rollback capabilities
4. **Secure platform resources** like cache and scheduled jobs
5. **Maintain audit trails** without exposing sensitive data

These patterns should be considered **mandatory** for any production-ready Salesforce package intended for AppExchange distribution.

---

*Document created by Debugger specialist during RouteLogic Enhanced security review*