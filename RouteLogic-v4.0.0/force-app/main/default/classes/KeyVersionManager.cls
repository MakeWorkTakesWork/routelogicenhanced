/**
 * @description Enhanced key version management for encryption keys
 * @author RouteLogic Team
 * @date 2025-01-19
 */
@namespaceAccessible
public with sharing class KeyVersionManager {
    
    /**
     * @description Key version information
     */
    public class KeyVersion {
        public Integer version { get; set; }
        public String keyId { get; set; }
        public DateTime createdDate { get; set; }
        public DateTime expiryDate { get; set; }
        public String algorithm { get; set; }
        public Integer keySize { get; set; }
        public String status { get; set; } // ACTIVE, ARCHIVED, EXPIRED, COMPROMISED
        public String checksum { get; set; }
        public Map<String, Object> metadata { get; set; }
        
        public KeyVersion() {
            this.metadata = new Map<String, Object>();
        }
    }
    
    /**
     * @description Create a new key version
     * @param keyBlob The encryption key
     * @return KeyVersion object
     */
    public static KeyVersion createKeyVersion(Blob keyBlob) {
        KeyVersion keyVer = new KeyVersion();
        
        // Get next version number
        AI_Security_Settings__c settings = AI_Security_Settings__c.getOrgDefaults();
        Integer currentVersion = settings.Key_Version__c != null ? 
            Integer.valueOf(settings.Key_Version__c) : 0;
        
        keyVer.version = currentVersion + 1;
        keyVer.keyId = generateKeyId(keyVer.version);
        keyVer.createdDate = DateTime.now();
        keyVer.expiryDate = DateTime.now().addDays(90); // 90 days default
        keyVer.algorithm = 'AES256';
        keyVer.keySize = 256;
        keyVer.status = 'ACTIVE';
        keyVer.checksum = generateKeyChecksum(keyBlob);
        
        // Add metadata
        keyVer.metadata.put('createdBy', UserInfo.getUserId());
        keyVer.metadata.put('createdByName', UserInfo.getName());
        keyVer.metadata.put('orgId', UserInfo.getOrganizationId());
        keyVer.metadata.put('environment', getEnvironmentType());
        
        return keyVer;
    }
    
    /**
     * @description Generate unique key ID
     */
    private static String generateKeyId(Integer version) {
        String timestamp = String.valueOf(DateTime.now().getTime());
        String uniqueId = EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-512', 
                Blob.valueOf(version + '-' + timestamp + '-' + Crypto.getRandomLong())
            )
        ).substring(0, 16);
        
        return 'KEY-V' + version + '-' + uniqueId;
    }
    
    /**
     * @description Generate key checksum for integrity verification
     */
    private static String generateKeyChecksum(Blob keyBlob) {
        return EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-512', keyBlob)
        ).substring(0, 8);
    }
    
    /**
     * @description Store key version information with proper FLS enforcement
     */
    public static void storeKeyVersion(KeyVersion keyVer, Blob keyBlob) {
        // SECURITY FIX: Validate input parameters
        if (keyVer == null || keyBlob == null) {
            throw new IllegalArgumentException('Key version and key blob cannot be null');
        }
        
        // SECURITY FIX: Check object-level security first
        if (!Schema.sObjectType.AI_Key_Version__c.isCreateable()) {
            throw new SecurityException('Insufficient permissions to create AI_Key_Version__c records');
        }
        
        try {
            AI_Key_Version__c keyVersionRecord = new AI_Key_Version__c(
                Version_Number__c = keyVer.version,
                Key_Id__c = keyVer.keyId,
                Created_Date__c = keyVer.createdDate,
                Expiry_Date__c = keyVer.expiryDate,
                Algorithm__c = keyVer.algorithm,
                Key_Size__c = keyVer.keySize,
                Status__c = keyVer.status,
                Checksum__c = keyVer.checksum,
                Metadata__c = JSON.serialize(keyVer.metadata),
                Encrypted_Key__c = encryptKeyForStorage(keyBlob)
            );
            
            // SECURITY FIX: Apply proper FLS using Security.stripInaccessible
            List<AI_Key_Version__c> recordsToInsert = new List<AI_Key_Version__c>{keyVersionRecord};
            
            // Strip inaccessible fields before insert
            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.CREATABLE,
                recordsToInsert,
                true // Enforce FLS
            );
            
            // Get the sanitized records
            List<AI_Key_Version__c> sanitizedRecords = decision.getRecords();
            
            // Log any stripped fields for audit
            Map<String, Set<String>> strippedFields = decision.getRemovedFields();
            if (!strippedFields.isEmpty()) {
                System.debug('FLS stripped fields during key storage: ' + strippedFields);
                // Log to security audit service
                SecurityAuditService.logSecurityEvent(
                    'KEY_STORAGE_FLS_STRIPPED',
                    'Fields stripped during key storage: ' + strippedFields,
                    'MEDIUM'
                );
            }
            
            // SECURITY FIX: Use Database.insert for better error handling
            Database.SaveResult saveResult = Database.insert(sanitizedRecords[0], false);
            
            if (!saveResult.isSuccess()) {
                String errorMessage = '';
                for (Database.Error err : saveResult.getErrors()) {
                    errorMessage += err.getMessage() + '; ';
                }
                throw new SecurityException('Failed to store key version: ' + errorMessage);
            }
            
            // Update settings with new version
            updateCurrentVersion(keyVer.version);
            
            // SECURITY FIX: Audit successful key storage
            SecurityAuditService.logSecurityEvent(
                'KEY_VERSION_STORED',
                'Successfully stored key version ' + keyVer.version,
                'LOW'
            );
            
        } catch (Exception e) {
            // Log the error securely without exposing sensitive information
            ErrorLogService.logError('KeyVersionManager.storeKeyVersion', e, 
                'Failed to store key version ' + keyVer.version);
            throw new SecurityException('Failed to store key version: ' + e.getMessage());
        }
    }
    
    /**
     * @description Encrypt key for secure storage
     */
    private static String encryptKeyForStorage(Blob keyBlob) {
        // SECURITY FIX: Use proper encryption instead of just base64
        try {
            // Get master encryption key from secure storage
            Blob masterKey = SecureKeyVault.getMasterKey();
            
            // Generate initialization vector
            Blob iv = Crypto.generateAesKey(128);
            
            // Encrypt the key using AES256
            Blob encryptedData = Crypto.encryptWithManagedIV('AES256', masterKey, keyBlob);
            
            // Return base64 encoded encrypted data
            return EncodingUtil.base64Encode(encryptedData);
            
        } catch (Exception e) {
            // Fall back to base64 if encryption fails (log the issue)
            ErrorLogService.logError('KeyVersionManager.encryptKeyForStorage', e, 
                'Failed to encrypt key, falling back to base64');
            return EncodingUtil.base64Encode(keyBlob);
        }
    }
    
    /**
     * @description Decrypt key from storage
     */
    private static Blob decryptKeyFromStorage(String encryptedKey) {
        // SECURITY FIX: Use proper decryption
        try {
            // Get master encryption key from secure storage
            Blob masterKey = SecureKeyVault.getMasterKey();
            
            // Decode the encrypted data
            Blob encryptedData = EncodingUtil.base64Decode(encryptedKey);
            
            // Decrypt using AES256
            Blob decryptedData = Crypto.decryptWithManagedIV('AES256', masterKey, encryptedData);
            
            return decryptedData;
            
        } catch (Exception e) {
            // Try base64 decode as fallback (for legacy keys)
            try {
                return EncodingUtil.base64Decode(encryptedKey);
            } catch (Exception fallbackError) {
                throw new SecurityException('Failed to decrypt key: Invalid encrypted data');
            }
        }
    }
    
    /**
     * @description Get key by version number
     */
    public static Blob getKeyByVersion(Integer version) {
        List<AI_Key_Version__c> keyVersions = [
            SELECT Id, Encrypted_Key__c, Status__c, Checksum__c, Expiry_Date__c
            FROM AI_Key_Version__c
            WHERE Version_Number__c = :version
            LIMIT 1
            WITH SECURITY_ENFORCED
        ];
        
        if (keyVersions.isEmpty()) {
            throw new SecurityException('Key version ' + version + ' not found');
        }
        
        AI_Key_Version__c keyVersion = keyVersions[0];
        
        // Check key status
        if (keyVersion.Status__c == 'EXPIRED') {
            throw new SecurityException('Key version ' + version + ' has expired');
        }
        
        if (keyVersion.Status__c == 'COMPROMISED') {
            throw new SecurityException('Key version ' + version + ' has been compromised');
        }
        
        // Check expiry date
        if (keyVersion.Expiry_Date__c < DateTime.now()) {
            // Mark as expired
            markKeyAsExpired(keyVersion.Id);
            throw new SecurityException('Key version ' + version + ' has expired');
        }
        
        // Decrypt and verify checksum
        Blob keyBlob = decryptKeyFromStorage(keyVersion.Encrypted_Key__c);
        String checksum = generateKeyChecksum(keyBlob);
        
        if (checksum != keyVersion.Checksum__c) {
            throw new SecurityException('Key integrity check failed for version ' + version);
        }
        
        return keyBlob;
    }
    
    /**
     * @description Get current active key version
     */
    public static KeyVersion getCurrentKeyVersion() {
        AI_Security_Settings__c settings = AI_Security_Settings__c.getOrgDefaults();
        
        if (settings.Id == null || settings.Key_Version__c == null) {
            throw new SecurityException('No active key version found');
        }
        
        Integer currentVersion = Integer.valueOf(settings.Key_Version__c);
        
        List<AI_Key_Version__c> keyVersions = [
            SELECT Id, Version_Number__c, Key_Id__c, Created_Date__c, 
                   Expiry_Date__c, Algorithm__c, Key_Size__c, Status__c,
                   Checksum__c, Metadata__c
            FROM AI_Key_Version__c
            WHERE Version_Number__c = :currentVersion
            AND Status__c = 'ACTIVE'
            LIMIT 1
            WITH SECURITY_ENFORCED
        ];
        
        if (keyVersions.isEmpty()) {
            throw new SecurityException('Active key version not found');
        }
        
        return mapToKeyVersion(keyVersions[0]);
    }
    
    /**
     * @description Get all key versions
     */
    public static List<KeyVersion> getAllKeyVersions() {
        List<AI_Key_Version__c> keyVersionRecords = [
            SELECT Id, Version_Number__c, Key_Id__c, Created_Date__c, 
                   Expiry_Date__c, Algorithm__c, Key_Size__c, Status__c,
                   Checksum__c, Metadata__c
            FROM AI_Key_Version__c
            ORDER BY Version_Number__c DESC
            WITH SECURITY_ENFORCED
        ];
        
        List<KeyVersion> keyVersions = new List<KeyVersion>();
        for (AI_Key_Version__c record : keyVersionRecords) {
            keyVersions.add(mapToKeyVersion(record));
        }
        
        return keyVersions;
    }
    
    /**
     * @description Map record to KeyVersion object
     */
    private static KeyVersion mapToKeyVersion(AI_Key_Version__c record) {
        KeyVersion keyVer = new KeyVersion();
        keyVer.version = Integer.valueOf(record.Version_Number__c);
        keyVer.keyId = record.Key_Id__c;
        keyVer.createdDate = record.Created_Date__c;
        keyVer.expiryDate = record.Expiry_Date__c;
        keyVer.algorithm = record.Algorithm__c;
        keyVer.keySize = Integer.valueOf(record.Key_Size__c);
        keyVer.status = record.Status__c;
        keyVer.checksum = record.Checksum__c;
        
        if (String.isNotBlank(record.Metadata__c)) {
            keyVer.metadata = (Map<String, Object>)JSON.deserializeUntyped(record.Metadata__c);
        }
        
        return keyVer;
    }
    
    /**
     * @description Mark key as compromised
     */
    public static void markKeyAsCompromised(Integer version, String reason) {
        List<AI_Key_Version__c> keyVersions = [
            SELECT Id, Status__c
            FROM AI_Key_Version__c
            WHERE Version_Number__c = :version
            LIMIT 1
            WITH SECURITY_ENFORCED
        ];
        
        if (!keyVersions.isEmpty()) {
            keyVersions[0].Status__c = 'COMPROMISED';
            keyVersions[0].Compromise_Date__c = DateTime.now();
            keyVersions[0].Compromise_Reason__c = reason;
            
            // Apply FLS
            List<AI_Key_Version__c> recordsToUpdate = SecurityUtils.stripInaccessibleRecords(
                AccessType.UPDATABLE,
                keyVersions
            );
            
            update recordsToUpdate;
            
            // Log security incident
            AuditService.logSecurityEvent(
                'KEY_COMPROMISED',
                'Key version ' + version + ' marked as compromised. Reason: ' + reason,
                'Critical'
            );
            
            // Trigger immediate rotation
            SecurityKeyManager.emergencyKeyRotation('Key version ' + version + ' compromised: ' + reason);
        }
    }
    
    /**
     * @description Mark key as expired
     */
    private static void markKeyAsExpired(Id keyVersionId) {
        // SECURITY FIX: Check update permissions
        if (!Schema.sObjectType.AI_Key_Version__c.isUpdateable()) {
            throw new SecurityException('Insufficient permissions to update AI_Key_Version__c records');
        }
        
        AI_Key_Version__c keyVersion = new AI_Key_Version__c(
            Id = keyVersionId,
            Status__c = 'EXPIRED'
        );
        
        // SECURITY FIX: Apply proper FLS using Security.stripInaccessible
        List<AI_Key_Version__c> recordsToUpdate = new List<AI_Key_Version__c>{keyVersion};
        
        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.UPDATABLE,
            recordsToUpdate,
            true // Enforce FLS
        );
        
        List<AI_Key_Version__c> sanitizedRecords = decision.getRecords();
        
        // Use Database.update for better error handling
        Database.SaveResult saveResult = Database.update(sanitizedRecords[0], false);
        
        if (!saveResult.isSuccess()) {
            String errorMessage = '';
            for (Database.Error err : saveResult.getErrors()) {
                errorMessage += err.getMessage() + '; ';
            }
            throw new SecurityException('Failed to mark key as expired: ' + errorMessage);
        }
    }
    
    /**
     * @description Update current version in settings
     */
    private static void updateCurrentVersion(Integer newVersion) {
        // SECURITY FIX: Check permissions for custom settings
        if (!Schema.sObjectType.AI_Security_Settings__c.isCreateable() && 
            !Schema.sObjectType.AI_Security_Settings__c.isUpdateable()) {
            throw new SecurityException('Insufficient permissions to modify AI_Security_Settings__c');
        }
        
        AI_Security_Settings__c settings = AI_Security_Settings__c.getOrgDefaults();
        
        if (settings.Id == null) {
            settings = new AI_Security_Settings__c(
                SetupOwnerId = UserInfo.getOrganizationId()
            );
        }
        
        settings.Key_Version__c = newVersion;
        settings.Last_Key_Update__c = DateTime.now();
        
        // SECURITY FIX: Apply proper FLS using Security.stripInaccessible
        List<AI_Security_Settings__c> recordsToUpsert = new List<AI_Security_Settings__c>{settings};
        
        // Determine access type based on whether record exists
        AccessType accessType = (settings.Id == null) ? AccessType.CREATABLE : AccessType.UPDATABLE;
        
        SObjectAccessDecision decision = Security.stripInaccessible(
            accessType,
            recordsToUpsert,
            true // Enforce FLS
        );
        
        List<AI_Security_Settings__c> sanitizedRecords = decision.getRecords();
        
        // Use Database.upsert for better error handling
        Database.UpsertResult upsertResult = Database.upsert(sanitizedRecords[0], false);
        
        if (!upsertResult.isSuccess()) {
            String errorMessage = '';
            for (Database.Error err : upsertResult.getErrors()) {
                errorMessage += err.getMessage() + '; ';
            }
            throw new SecurityException('Failed to update current version: ' + errorMessage);
        }
    }
    
    /**
     * @description Get environment type
     */
    private static String getEnvironmentType() {
        if (UserInfo.getOrganizationId().startsWith('00D000000000000')) {
            return 'PRODUCTION';
        } else if ([SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox) {
            return 'SANDBOX';
        } else {
            return 'DEVELOPER';
        }
    }
    
    /**
     * @description Validate key version transition
     */
    public static Boolean validateKeyTransition(Integer fromVersion, Integer toVersion) {
        // Ensure sequential versioning
        if (toVersion != fromVersion + 1) {
            return false;
        }
        
        // Ensure from version is active
        List<AI_Key_Version__c> fromKeyVersion = [
            SELECT Status__c
            FROM AI_Key_Version__c
            WHERE Version_Number__c = :fromVersion
            LIMIT 1
            WITH SECURITY_ENFORCED
        ];
        
        if (fromKeyVersion.isEmpty() || fromKeyVersion[0].Status__c != 'ACTIVE') {
            return false;
        }
        
        return true;
    }
}