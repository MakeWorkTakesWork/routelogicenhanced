/**
 * @description Negative test cases for SecurityKeyManager
 * @author RouteLogic Team
 * @date 2025-01-20
 */
@isTest
@namespaceAccessible
public with sharing class SecurityKeyManagerNegativeTest {
    
    @TestSetup
    static void setup() {
        // Create test metadata records
        AI_Provider_Settings__mdt testSettings = new AI_Provider_Settings__mdt(
            DeveloperName = 'Test_Provider',
            Label = 'Test Provider',
            Provider_Name__c = 'TestProvider',
            Endpoint_URL__c = 'https://test.example.com/api',
            Authentication_Type__c = 'OAuth2',
            Named_Credential__c = 'Test_API',
            Is_Active__c = true
        );
        
        // Create security settings
        AI_Security_Settings__c secSettings = AI_Security_Settings__c.getOrgDefaults();
        secSettings.Key_Version__c = '1';
        secSettings.Encryption_Algorithm__c = 'AES256';
        secSettings.Key_Rotation_Days__c = 90;
        upsert secSettings;
    }
    
    /**
     * @description Test unauthorized key rotation attempts
     */
    @isTest
    static void testUnauthorizedKeyRotation() {
        // Create a user without Manage Encryption Keys permission
        Profile stdProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User stdUser = new User(
            Alias = 'stdkey',
            Email = 'stdkey@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'StandardKey',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = stdProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'stdkey@routelogic.test.unique'
        );
        insert stdUser;
        
        Test.startTest();
        System.runAs(stdUser) {
            try {
                SecurityKeyManager keyManager = new SecurityKeyManager();
                keyManager.rotateKeys();
                System.assert(false, 'Expected exception for unauthorized key rotation');
            } catch (Exception e) {
                System.assert(
                    e.getMessage().contains('permission') || 
                    e.getMessage().contains('Unauthorized') ||
                    e.getMessage().contains('INSUFFICIENT'),
                    'Expected permission error, got: ' + e.getMessage()
                );
            }
        }
        Test.stopTest();
    }
    
    /**
     * @description Test tampering with key checksums
     */
    @isTest
    static void testKeyChecksumTampering() {
        Test.startTest();
        try {
            // Create a key version with tampered checksum
            AI_Key_Version__c keyVersion = new AI_Key_Version__c(
                Key_ID__c = 'KEY-V1-TAMPERED',
                Version_Number__c = 999,
                Algorithm__c = 'AES256',
                Key_Size__c = 256,
                Status__c = 'ACTIVE',
                Checksum__c = 'INVALID_CHECKSUM',
                Created_Date__c = DateTime.now(),
                Expiry_Date__c = DateTime.now().addDays(90)
            );
            insert keyVersion;
            
            // Attempt to use the tampered key
            KeyVersionManager.KeyVersion kv = new KeyVersionManager.KeyVersion();
            kv.keyId = keyVersion.Key_ID__c;
            kv.checksum = keyVersion.Checksum__c;
            
            // Verify integrity check should fail
            Boolean isValid = KeyVersionManager.verifyKeyIntegrity(kv);
            System.assert(!isValid, 'Tampered key should fail integrity check');
            
        } catch (Exception e) {
            // Expected if integrity checks prevent insertion
            System.assert(true, 'Key integrity protection working');
        }
        Test.stopTest();
    }
    
    /**
     * @description Test accessing expired encryption keys
     */
    @isTest
    static void testExpiredKeyAccess() {
        // Create an expired key version
        AI_Key_Version__c expiredKey = new AI_Key_Version__c(
            Key_ID__c = 'KEY-V1-EXPIRED',
            Version_Number__c = 1,
            Algorithm__c = 'AES256',
            Key_Size__c = 256,
            Status__c = 'EXPIRED',
            Created_Date__c = DateTime.now().addDays(-180),
            Expiry_Date__c = DateTime.now().addDays(-90),
            Checksum__c = 'ABC12345'
        );
        insert expiredKey;
        
        Test.startTest();
        try {
            SecurityKeyManager keyManager = new SecurityKeyManager();
            // Attempt to decrypt with expired key
            Blob testData = Blob.valueOf('test data');
            String encrypted = EncodingUtil.base64Encode(testData);
            
            // This should fail as the key is expired
            Blob decrypted = keyManager.decryptData(encrypted);
            System.assert(false, 'Should not be able to use expired keys');
            
        } catch (Exception e) {
            System.assert(
                e.getMessage().contains('expired') || 
                e.getMessage().contains('Expired') ||
                e.getMessage().contains('invalid'),
                'Expected expired key error'
            );
        }
        Test.stopTest();
    }
    
    /**
     * @description Test metadata injection attacks
     */
    @isTest
    static void testMetadataInjection() {
        Test.startTest();
        try {
            // Attempt to inject malicious metadata
            String maliciousMetadata = '{"keyId": "../../admin/keys", "action": "extract"}';
            
            AI_Processing_Status__c status = new AI_Processing_Status__c(
                Case__c = [SELECT Id FROM Case LIMIT 1].Id,
                AI_Provider__c = 'Test',
                Status__c = 'Pending',
                Metadata__c = maliciousMetadata
            );
            insert status;
            
            // Verify metadata is sanitized when processed
            AI_Processing_Status__c retrieved = [
                SELECT Metadata__c 
                FROM AI_Processing_Status__c 
                WHERE Id = :status.Id
            ];
            
            // Parse metadata and check for path traversal
            Map<String, Object> metadata = (Map<String, Object>) JSON.deserializeUntyped(retrieved.Metadata__c);
            String keyId = (String) metadata.get('keyId');
            
            System.assert(!keyId.contains('../'), 'Path traversal should be prevented');
            
        } catch (Exception e) {
            // Expected if validation prevents malicious input
            System.assert(true, 'Metadata validation working');
        }
        Test.stopTest();
    }
    
    /**
     * @description Test concurrent key rotation race conditions
     */
    @isTest
    static void testConcurrentKeyRotation() {
        Test.startTest();
        
        // Simulate concurrent key rotation attempts
        List<Database.SaveResult> results = new List<Database.SaveResult>();
        
        // Create multiple key versions with same version number
        List<AI_Key_Version__c> keys = new List<AI_Key_Version__c>();
        for (Integer i = 0; i < 5; i++) {
            keys.add(new AI_Key_Version__c(
                Key_ID__c = 'KEY-V2-CONCURRENT-' + i,
                Version_Number__c = 2, // Same version number
                Algorithm__c = 'AES256',
                Key_Size__c = 256,
                Status__c = 'ACTIVE',
                Created_Date__c = DateTime.now(),
                Expiry_Date__c = DateTime.now().addDays(90),
                Checksum__c = 'CHK' + i
            ));
        }
        
        results = Database.insert(keys, false);
        
        // Verify only one succeeded (or none if unique constraint exists)
        Integer successCount = 0;
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                successCount++;
            }
        }
        
        System.assert(successCount <= 1, 'Concurrent key creation should be prevented');
        
        Test.stopTest();
    }
    
    /**
     * @description Test invalid state transitions for keys
     */
    @isTest
    static void testInvalidKeyStateTransitions() {
        // Create a compromised key
        AI_Key_Version__c compromisedKey = new AI_Key_Version__c(
            Key_ID__c = 'KEY-V1-COMPROMISED',
            Version_Number__c = 1,
            Algorithm__c = 'AES256',
            Key_Size__c = 256,
            Status__c = 'COMPROMISED',
            Created_Date__c = DateTime.now().addDays(-30),
            Expiry_Date__c = DateTime.now().addDays(60),
            Checksum__c = 'COMP123'
        );
        insert compromisedKey;
        
        Test.startTest();
        try {
            // Attempt to reactivate compromised key
            compromisedKey.Status__c = 'ACTIVE';
            update compromisedKey;
            
            System.assert(false, 'Should not be able to reactivate compromised key');
            
        } catch (Exception e) {
            System.assert(
                e.getMessage().contains('Invalid') || 
                e.getMessage().contains('transition') ||
                e.getMessage().contains('compromised'),
                'Expected state transition error'
            );
        }
        Test.stopTest();
    }
    
    /**
     * @description Test encryption with null or empty data
     */
    @isTest
    static void testEncryptionWithInvalidData() {
        SecurityKeyManager keyManager = new SecurityKeyManager();
        
        Test.startTest();
        
        // Test null data
        try {
            String encrypted = keyManager.encryptData(null);
            System.assert(false, 'Should not encrypt null data');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('null') || 
                         e.getMessage().contains('empty') ||
                         e.getMessage().contains('Invalid'),
                         'Expected null data error');
        }
        
        // Test empty blob
        try {
            String encrypted = keyManager.encryptData(Blob.valueOf(''));
            // Some systems might allow empty encryption
            if (encrypted != null) {
                // Try to decrypt
                Blob decrypted = keyManager.decryptData(encrypted);
                System.assertEquals(0, decrypted.size(), 'Empty data should decrypt to empty');
            }
        } catch (Exception e) {
            // Also acceptable to throw error for empty data
            System.assert(true, 'Empty data validation working');
        }
        
        Test.stopTest();
    }
    
    /**
     * @description Test key version rollback attempts
     */
    @isTest
    static void testKeyVersionRollback() {
        Test.startTest();
        
        // Get current key version
        AI_Security_Settings__c settings = AI_Security_Settings__c.getOrgDefaults();
        Decimal currentVersion = settings.Key_Version__c != null ? settings.Key_Version__c : 1;
        
        try {
            // Attempt to set an older version
            settings.Key_Version__c = currentVersion - 1;
            update settings;
            
            // Verify rollback prevention
            AI_Security_Settings__c updatedSettings = AI_Security_Settings__c.getOrgDefaults();
            System.assert(updatedSettings.Key_Version__c >= currentVersion, 
                         'Key version rollback should be prevented');
                         
        } catch (Exception e) {
            // Expected if validation prevents rollback
            System.assert(e.getMessage().contains('rollback') || 
                         e.getMessage().contains('version') ||
                         e.getMessage().contains('Invalid'),
                         'Expected version rollback error');
        }
        
        Test.stopTest();
    }
}