/**
 * @description DEPRECATED - Manages encryption key lifecycle including generation, rotation, and archival
 * @author RouteLogic Team
 * @date 2025-01-17
 * @deprecated This class is deprecated as of RouteLogic v3.3.0. Use Salesforce Shield Platform Encryption instead.
 * 
 * MIGRATION NOTICE:
 * RouteLogic now leverages native Salesforce Shield Platform Encryption for all data protection needs.
 * This provides enterprise-grade security with zero custom code maintenance overhead.
 * 
 * To migrate:
 * 1. Enable Salesforce Shield Platform Encryption in your org
 * 2. Configure field-level encryption for sensitive data
 * 3. Remove dependencies on this class
 * 4. Use SecurityUtils.stripInaccessibleRecords() for CRUD security
 */
@Deprecated
public with sharing class SecurityKeyManager {
    
    private static final Integer SECURITY_KEY_SIZE = 256;
    private static final Integer KEY_ROTATION_DAYS = 90;
    private static final Integer KEY_RETENTION_DAYS = 365;
    
    /**
     * @description Rotate encryption keys automatically
     * This method is called by scheduled job every 90 days
     */
    @future
    public static void rotateEncryptionKeys() {
        try {
            // Generate new AES-256 key
            Blob newKey = Crypto.generateAesKey(SECURITY_KEY_SIZE);
            
            // Get current settings
            AI_Security_Settings__c settings = AI_Security_Settings__c.getOrgDefaults();
            if (settings.Id == null) {
                settings = initializeSecuritySettings();
            }
            
            Integer currentVersion = settings.Key_Version__c != null ? 
                Integer.valueOf(settings.Key_Version__c) : 0;
            
            // Create new key version using enhanced versioning
            KeyVersionManager.KeyVersion newKeyVersion = KeyVersionManager.createKeyVersion(newKey);
            
            // Validate key transition
            if (currentVersion > 0 && !KeyVersionManager.validateKeyTransition(currentVersion, newKeyVersion.version)) {
                throw new SecurityException('Invalid key version transition');
            }
            
            // Store new key version
            KeyVersionManager.storeKeyVersion(newKeyVersion, newKey);
            
            // Archive current key
            if (currentVersion > 0) {
                archiveCurrentKey(settings, currentVersion);
            }
            
            // Store new key (legacy support)
            storeNewKey(settings, newKey, newKeyVersion.version);
            
            // Update settings
            settings.Key_Version__c = newKeyVersion.version;
            settings.Last_Rotation_Date__c = DateTime.now();
            settings.Next_Rotation_Date__c = DateTime.now().addDays(KEY_ROTATION_DAYS);
            settings.Active__c = true;
            
            // Apply FLS before upsert
            List<AI_Security_Settings__c> settingsToUpsert = new List<AI_Security_Settings__c>{settings};
            settingsToUpsert = SecurityUtils.stripInaccessibleRecords(
                AccessType.UPSERTABLE,
                settingsToUpsert
            );
            
            upsert settingsToUpsert[0];
            
            // Log rotation event with enhanced details
            AuditService.logSecurityEvent(
                'KEY_ROTATION',
                'Encryption key rotated to version ' + newKeyVersion.version + ' (ID: ' + newKeyVersion.keyId + ')',
                'Success'
            );
            
            // Schedule re-encryption of existing data
            if (currentVersion > 0) {
                System.enqueueJob(new DataReEncryptionQueueable(newKeyVersion.version, currentVersion));
            }
            
            // Notify administrators
            notifyAdministrators('Encryption key rotation completed successfully. New version: ' + newKeyVersion.version + ' (ID: ' + newKeyVersion.keyId + ')');
            
        } catch (Exception e) {
            // Log failure and create security incident
            handleKeyRotationFailure(e);
            throw new SecurityException('Key rotation failed: ' + e.getMessage());
        }
    }
    
    /**
     * @description Initialize security settings if not exists
     */
    private static AI_Security_Settings__c initializeSecuritySettings() {
        AI_Security_Settings__c settings = new AI_Security_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Enable_Encryption__c = true,
            Enable_Key_Rotation__c = true,
            Key_Version__c = 0,
            Active__c = true
        );
        
        // Apply FLS before insert
        List<AI_Security_Settings__c> settingsToInsert = new List<AI_Security_Settings__c>{settings};
        settingsToInsert = SecurityUtils.stripInaccessibleRecords(
            AccessType.CREATABLE,
            settingsToInsert
        );
        
        insert settingsToInsert[0];
        return settings;
    }
    
    /**
     * @description Archive the current encryption key
     */
    private static void archiveCurrentKey(AI_Security_Settings__c settings, Integer version) {
        String currentKeyField = 'Encryption_Key_v' + version + '__c';
        String archiveKeyField = 'Archive_Key_v' + version + '__c';
        String archiveDateField = 'Archive_Date_v' + version + '__c';
        
        // Move current key to archive
        if (settings.get(currentKeyField) != null) {
            settings.put(archiveKeyField, settings.get(currentKeyField));
            settings.put(archiveDateField, DateTime.now());
            
            // Clear current key field
            settings.put(currentKeyField, null);
        }
    }
    
    /**
     * @description Store new encryption key
     */
    private static void storeNewKey(AI_Security_Settings__c settings, Blob newKey, Integer version) {
        String keyField = 'Encryption_Key_v' + version + '__c';
        String createdDateField = 'Key_Created_Date_v' + version + '__c';
        
        // Encode and store key
        String encodedKey = EncodingUtil.base64Encode(newKey);
        settings.put(keyField, encodedKey);
        settings.put(createdDateField, DateTime.now());
        
        // Generate key metadata
        Map<String, Object> keyMetadata = new Map<String, Object>{
            'version' => version,
            'algorithm' => 'AES256',
            'keySize' => SECURITY_KEY_SIZE,
            'created' => DateTime.now().format(),
            'createdBy' => UserInfo.getUserId()
        };
        
        settings.Key_Metadata__c = JSON.serialize(keyMetadata);
    }
    
    /**
     * @description Get current encryption key
     */
    public static Blob getCurrentKey() {
        AI_Security_Settings__c settings = AI_Security_Settings__c.getOrgDefaults();
        
        if (settings.Id == null || settings.Key_Version__c == null) {
            throw new SecurityException('Encryption not initialized');
        }
        
        Integer currentVersion = Integer.valueOf(settings.Key_Version__c);
        
        try {
            // Try to get key from enhanced version manager first
            return KeyVersionManager.getKeyByVersion(currentVersion);
        } catch (Exception e) {
            // Fallback to legacy method
            String keyField = 'Encryption_Key_v' + currentVersion + '__c';
            
            String encodedKey = (String)settings.get(keyField);
            if (String.isBlank(encodedKey)) {
                throw new SecurityException('Current encryption key not found');
            }
            
            return EncodingUtil.base64Decode(encodedKey);
        }
    }
    
    /**
     * @description Get key for specific version (for decryption)
     */
    public static Blob getKeyForVersion(Integer version) {
        try {
            // Try to get key from enhanced version manager first
            return KeyVersionManager.getKeyByVersion(version);
        } catch (Exception e) {
            // Fallback to legacy method
            AI_Security_Settings__c settings = AI_Security_Settings__c.getOrgDefaults();
            
            if (settings.Id == null) {
                throw new SecurityException('Encryption not initialized');
            }
            
            Integer currentVersion = Integer.valueOf(settings.Key_Version__c);
            
            // Check if requesting current key
            if (version == currentVersion) {
                return getCurrentKey();
            }
            
            // Check archived keys
            String archiveKeyField = 'Archive_Key_v' + version + '__c';
            String encodedKey = (String)settings.get(archiveKeyField);
            
            if (String.isBlank(encodedKey)) {
                throw new SecurityException('Encryption key for version ' + version + ' not found');
            }
            
            // Verify key hasn't exceeded retention period
            String archiveDateField = 'Archive_Date_v' + version + '__c';
            DateTime archiveDate = (DateTime)settings.get(archiveDateField);
            
            if (archiveDate != null && archiveDate.addDays(KEY_RETENTION_DAYS) < DateTime.now()) {
                throw new SecurityException('Encryption key for version ' + version + ' has expired');
            }
            
            return EncodingUtil.base64Decode(encodedKey);
        }
    }
    
    /**
     * @description Check if key rotation is due
     */
    public static Boolean isRotationDue() {
        AI_Security_Settings__c settings = AI_Security_Settings__c.getOrgDefaults();
        
        if (settings.Id == null || settings.Last_Rotation_Date__c == null) {
            return true; // First time setup
        }
        
        if (!settings.Enable_Key_Rotation__c) {
            return false; // Rotation disabled
        }
        
        DateTime lastRotation = settings.Last_Rotation_Date__c;
        return lastRotation.addDays(KEY_ROTATION_DAYS) <= DateTime.now();
    }
    
    /**
     * @description Emergency key rotation (manual trigger)
     */
    public static void emergencyKeyRotation(String reason) {
        // Verify admin permissions
        if (!FeatureManagement.checkPermission('AI_Security_Admin')) {
            throw new InsufficientPrivilegesException('Security admin permission required');
        }
        
        // Log emergency rotation request
        AuditService.logSecurityEvent(
            'EMERGENCY_KEY_ROTATION',
            'Emergency key rotation requested. Reason: ' + reason,
            'Initiated'
        );
        
        // Perform rotation
        rotateEncryptionKeys();
        
        // Create security incident
        AI_Security_Incident__c incident = new AI_Security_Incident__c(
            Type__c = 'Emergency Key Rotation',
            Severity__c = 'High',
            Status__c = 'Resolved',
            Description__c = reason,
            Resolution__c = 'Keys rotated successfully',
            Reported_By__c = UserInfo.getUserId(),
            Resolved_Date__c = DateTime.now()
        );
        
        // Apply FLS before insert
        List<AI_Security_Incident__c> incidentsToInsert = new List<AI_Security_Incident__c>{incident};
        incidentsToInsert = SecurityUtils.stripInaccessibleRecords(
            AccessType.CREATABLE,
            incidentsToInsert
        );
        
        insert incidentsToInsert[0];
    }
    
    /**
     * @description Clean up expired keys
     */
    @future
    public static void cleanupExpiredKeys() {
        AI_Security_Settings__c settings = AI_Security_Settings__c.getOrgDefaults();
        
        if (settings.Id == null) {
            return;
        }
        
        Integer currentVersion = Integer.valueOf(settings.Key_Version__c);
        DateTime cutoffDate = DateTime.now().addDays(-KEY_RETENTION_DAYS);
        
        // Check each archived key
        for (Integer version = 1; version < currentVersion; version++) {
            String archiveDateField = 'Archive_Date_v' + version + '__c';
            DateTime archiveDate = (DateTime)settings.get(archiveDateField);
            
            if (archiveDate != null && archiveDate < cutoffDate) {
                // Clear expired key
                String archiveKeyField = 'Archive_Key_v' + version + '__c';
                settings.put(archiveKeyField, null);
                settings.put(archiveDateField, null);
                
                // Log cleanup
                AuditService.logSecurityEvent(
                    'KEY_CLEANUP',
                    'Expired key removed. Version: ' + version,
                    'Success'
                );
            }
        }
        
        // Apply FLS before update
        List<AI_Security_Settings__c> settingsToUpdate = new List<AI_Security_Settings__c>{settings};
        settingsToUpdate = SecurityUtils.stripInaccessibleRecords(
            AccessType.UPDATABLE,
            settingsToUpdate
        );
        
        update settingsToUpdate[0];
    }
    
    /**
     * @description Handle key rotation failure
     */
    private static void handleKeyRotationFailure(Exception e) {
        // Log error
        ErrorLogService.logError('SecurityKeyManager.rotateEncryptionKeys', e, null);
        
        // Create critical security incident
        AI_Security_Incident__c incident = new AI_Security_Incident__c(
            Type__c = 'Key Rotation Failure',
            Severity__c = 'Critical',
            Status__c = 'Open',
            Description__c = 'Automatic key rotation failed: ' + e.getMessage(),
            Stack_Trace__c = e.getStackTraceString(),
            Reported_By__c = UserInfo.getUserId()
        );
        
        // Apply FLS before insert
        List<AI_Security_Incident__c> incidentsToInsert = new List<AI_Security_Incident__c>{incident};
        incidentsToInsert = SecurityUtils.stripInaccessibleRecords(
            AccessType.CREATABLE,
            incidentsToInsert
        );
        
        insert incidentsToInsert[0];
        
        // Send emergency notification
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(getSecurityTeamEmails());
        email.setSubject('CRITICAL: Encryption Key Rotation Failed');
        email.setHtmlBody(
            '<p>Automatic encryption key rotation has failed.</p>' +
            '<p><b>Error:</b> ' + e.getMessage() + '</p>' +
            '<p><b>Time:</b> ' + DateTime.now().format() + '</p>' +
            '<p><b>Incident ID:</b> ' + incident.Id + '</p>' +
            '<p>Please investigate immediately.</p>'
        );
        email.setSaveAsActivity(false);
        
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{email});
    }
    
    /**
     * @description Notify administrators of key rotation
     */
    private static void notifyAdministrators(String message) {
        List<User> admins = [
            SELECT Id, Email, Name
            FROM User
            WHERE Profile.Name = 'System Administrator'
            AND IsActive = true
            LIMIT 10
        ];
        
        if (admins.isEmpty()) {
            return;
        }
        
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        
        for (User admin : admins) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{admin.Email});
            email.setSubject('RouteLogic: Encryption Key Rotation Completed');
            email.setHtmlBody(
                '<p>Dear ' + admin.Name + ',</p>' +
                '<p>' + message + '</p>' +
                '<p><b>Time:</b> ' + DateTime.now().format() + '</p>' +
                '<p><b>Next rotation:</b> ' + DateTime.now().addDays(KEY_ROTATION_DAYS).format() + '</p>' +
                '<p>No action required. This is an automated notification.</p>' +
                '<br/>' +
                '<p>Best regards,<br/>RouteLogic Security Team</p>'
            );
            email.setSaveAsActivity(false);
            emails.add(email);
        }
        
        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails);
        }
    }
    
    /**
     * @description Get security team emails for critical notifications
     */
    private static List<String> getSecurityTeamEmails() {
        // Get from custom metadata or settings
        List<String> emails = new List<String>();
        
        // Add configured security team emails
        AI_Security_Config__mdt config = [
            SELECT Security_Team_Emails__c
            FROM AI_Security_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        
        if (config != null && String.isNotBlank(config.Security_Team_Emails__c)) {
            emails.addAll(config.Security_Team_Emails__c.split(','));
        }
        
        // Fallback to system admins
        if (emails.isEmpty()) {
            List<User> admins = [
                SELECT Email
                FROM User
                WHERE Profile.Name = 'System Administrator'
                AND IsActive = true
                LIMIT 5
            ];
            
            for (User admin : admins) {
                emails.add(admin.Email);
            }
        }
        
        return emails;
    }
    
    /**
     * @description Get key rotation status for monitoring
     */
    public static KeyRotationStatus getRotationStatus() {
        KeyRotationStatus status = new KeyRotationStatus();
        
        try {
            AI_Security_Settings__c settings = AI_Security_Settings__c.getOrgDefaults();
            
            if (settings.Id == null) {
                status.isInitialized = false;
                status.message = 'Encryption not initialized';
                return status;
            }
            
            status.isInitialized = true;
            status.currentVersion = Integer.valueOf(settings.Key_Version__c);
            status.lastRotationDate = settings.Last_Rotation_Date__c;
            status.nextRotationDate = settings.Next_Rotation_Date__c;
            status.isRotationDue = isRotationDue();
            status.rotationEnabled = settings.Enable_Key_Rotation__c;
            
            // Get enhanced version information
            try {
                KeyVersionManager.KeyVersion currentKeyVersion = KeyVersionManager.getCurrentKeyVersion();
                status.currentKeyId = currentKeyVersion.keyId;
                status.keyAlgorithm = currentKeyVersion.algorithm;
                status.keyExpiryDate = currentKeyVersion.expiryDate;
                
                // Get all versions for history
                List<KeyVersionManager.KeyVersion> allVersions = KeyVersionManager.getAllKeyVersions();
                status.totalVersions = allVersions.size();
                status.activeVersions = 0;
                status.expiredVersions = 0;
                
                for (KeyVersionManager.KeyVersion kv : allVersions) {
                    if (kv.status == 'ACTIVE') {
                        status.activeVersions++;
                    } else if (kv.status == 'EXPIRED') {
                        status.expiredVersions++;
                    }
                }
            } catch (Exception e) {
                // Enhanced versioning not available yet
                System.debug('Enhanced key versioning not available: ' + e.getMessage());
            }
            
            if (status.isRotationDue) {
                status.message = 'Key rotation is overdue';
            } else if (status.nextRotationDate != null) {
                Integer daysUntilRotation = DateTime.now().date().daysBetween(status.nextRotationDate.date());
                status.message = 'Next rotation in ' + daysUntilRotation + ' days';
            }
            
        } catch (Exception e) {
            status.hasError = true;
            status.message = 'Error retrieving rotation status: ' + e.getMessage();
        }
        
        return status;
    }
    
    /**
     * @description Key rotation status class
     */
    @namespaceAccessible
    public class KeyRotationStatus {
        @AuraEnabled public Boolean isInitialized { get; set; }
        @AuraEnabled public Integer currentVersion { get; set; }
        @AuraEnabled public DateTime lastRotationDate { get; set; }
        @AuraEnabled public DateTime nextRotationDate { get; set; }
        @AuraEnabled public Boolean isRotationDue { get; set; }
        @AuraEnabled public Boolean rotationEnabled { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Boolean hasError { get; set; }
        // Enhanced versioning fields
        @AuraEnabled public String currentKeyId { get; set; }
        @AuraEnabled public String keyAlgorithm { get; set; }
        @AuraEnabled public DateTime keyExpiryDate { get; set; }
        @AuraEnabled public Integer totalVersions { get; set; }
        @AuraEnabled public Integer activeVersions { get; set; }
        @AuraEnabled public Integer expiredVersions { get; set; }
        
        public KeyRotationStatus() {
            this.hasError = false;
            this.isInitialized = false;
            this.totalVersions = 0;
            this.activeVersions = 0;
            this.expiredVersions = 0;
        }
    }
}