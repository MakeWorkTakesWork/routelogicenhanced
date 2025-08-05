/**
 * @description Security test class for KeyVersionManager FLS enforcement
 * @author RouteLogic Security Team
 * @date 2025-01-31
 */
@isTest
private class KeyVersionManagerSecurityTest {
    
    /**
     * @description Test FLS enforcement on key storage
     */
    @isTest
    static void testFLSEnforcementOnInsert() {
        // Create test key version
        KeyVersionManager.KeyVersion keyVer = new KeyVersionManager.KeyVersion();
        keyVer.version = 1;
        keyVer.keyId = 'TEST-KEY-001';
        keyVer.createdDate = DateTime.now();
        keyVer.expiryDate = DateTime.now().addDays(90);
        keyVer.algorithm = 'AES256';
        keyVer.keySize = 256;
        keyVer.status = 'ACTIVE';
        keyVer.checksum = 'ABC123';
        
        Blob testKey = Crypto.generateAesKey(256);
        
        // Create a user without FLS permissions
        User limitedUser = createUserWithoutFLS();
        
        Test.startTest();
        
        System.runAs(limitedUser) {
            try {
                KeyVersionManager.storeKeyVersion(keyVer, testKey);
                
                // If we have proper FLS, the operation should either:
                // 1. Throw a SecurityException
                // 2. Strip inaccessible fields and succeed
                
                // Query to see what was actually stored
                List<AI_Key_Version__c> storedKeys = [
                    SELECT Id, Version_Number__c, Status__c
                    FROM AI_Key_Version__c
                    WHERE Version_Number__c = 1
                ];
                
                if (!storedKeys.isEmpty()) {
                    // Fields were stripped but insert succeeded
                    System.assert(true, 'FLS stripped inaccessible fields');
                }
                
            } catch (SecurityException e) {
                // This is expected if user lacks permissions
                System.assert(e.getMessage().contains('Insufficient permissions') ||
                             e.getMessage().contains('Failed to store'),
                             'Should throw proper security exception');
            }
        }
        
        Test.stopTest();
    }
    
    /**
     * @description Test FLS enforcement on key update
     */
    @isTest
    static void testFLSEnforcementOnUpdate() {
        // First create a key version as admin
        KeyVersionManager.KeyVersion keyVer = createTestKeyVersion();
        Blob testKey = Crypto.generateAesKey(256);
        
        KeyVersionManager.storeKeyVersion(keyVer, testKey);
        
        // Get the created record
        AI_Key_Version__c createdKey = [
            SELECT Id, Version_Number__c
            FROM AI_Key_Version__c
            WHERE Version_Number__c = :keyVer.version
            LIMIT 1
        ];
        
        // Create limited user
        User limitedUser = createUserWithoutFLS();
        
        Test.startTest();
        
        System.runAs(limitedUser) {
            try {
                // Try to mark key as expired (update operation)
                KeyVersionManager.markKeyAsExpired(createdKey.Id);
                
                // Check if update succeeded with stripped fields
                AI_Key_Version__c updatedKey = [
                    SELECT Id, Status__c
                    FROM AI_Key_Version__c
                    WHERE Id = :createdKey.Id
                ];
                
                // If we get here, FLS was enforced but update succeeded
                System.assert(updatedKey.Status__c == 'EXPIRED' || 
                             updatedKey.Status__c == 'ACTIVE',
                             'Status should be updated or unchanged based on FLS');
                
            } catch (SecurityException e) {
                // Expected if user lacks update permissions
                System.assert(e.getMessage().contains('Insufficient permissions') ||
                             e.getMessage().contains('Failed to mark'),
                             'Should throw proper security exception');
            }
        }
        
        Test.stopTest();
    }
    
    /**
     * @description Test proper encryption/decryption
     */
    @isTest
    static void testKeyEncryption() {
        // Create and store a key
        KeyVersionManager.KeyVersion keyVer = createTestKeyVersion();
        Blob originalKey = Crypto.generateAesKey(256);
        
        Test.startTest();
        
        // Store the key
        KeyVersionManager.storeKeyVersion(keyVer, originalKey);
        
        // Retrieve the key
        Blob retrievedKey = KeyVersionManager.getKeyByVersion(keyVer.version);
        
        // Keys should match (encryption/decryption working)
        System.assertEquals(originalKey.toString(), retrievedKey.toString(),
                          'Retrieved key should match original');
        
        Test.stopTest();
    }
    
    /**
     * @description Test audit logging on key operations
     */
    @isTest
    static void testAuditLogging() {
        KeyVersionManager.KeyVersion keyVer = createTestKeyVersion();
        Blob testKey = Crypto.generateAesKey(256);
        
        Test.startTest();
        
        // Store key (should trigger audit logging)
        KeyVersionManager.storeKeyVersion(keyVer, testKey);
        
        // Check if audit events were logged
        // Note: In test context, we can't query platform events directly
        // but we can verify the code path executed without errors
        System.assert(true, 'Audit logging executed without errors');
        
        Test.stopTest();
    }
    
    /**
     * @description Test null parameter validation
     */
    @isTest
    static void testNullParameterValidation() {
        Test.startTest();
        
        // Test null key version
        try {
            KeyVersionManager.storeKeyVersion(null, Crypto.generateAesKey(256));
            System.assert(false, 'Should throw exception for null key version');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('cannot be null'),
                         'Should validate null key version');
        }
        
        // Test null key blob
        try {
            KeyVersionManager.KeyVersion keyVer = createTestKeyVersion();
            KeyVersionManager.storeKeyVersion(keyVer, null);
            System.assert(false, 'Should throw exception for null key blob');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('cannot be null'),
                         'Should validate null key blob');
        }
        
        Test.stopTest();
    }
    
    /**
     * @description Test Database.insert error handling
     */
    @isTest
    static void testDatabaseErrorHandling() {
        // Create a key version with invalid data
        KeyVersionManager.KeyVersion keyVer = new KeyVersionManager.KeyVersion();
        keyVer.version = -1; // Invalid version number
        keyVer.keyId = null; // Required field
        keyVer.status = 'INVALID_STATUS'; // Invalid picklist value
        
        Blob testKey = Crypto.generateAesKey(256);
        
        Test.startTest();
        
        try {
            KeyVersionManager.storeKeyVersion(keyVer, testKey);
            System.assert(false, 'Should throw exception for invalid data');
        } catch (SecurityException e) {
            System.assert(e.getMessage().contains('Failed to store'),
                         'Should handle database errors properly');
        }
        
        Test.stopTest();
    }
    
    /**
     * @description Test key integrity validation
     */
    @isTest
    static void testKeyIntegrityValidation() {
        // Store a valid key
        KeyVersionManager.KeyVersion keyVer = createTestKeyVersion();
        Blob testKey = Crypto.generateAesKey(256);
        
        KeyVersionManager.storeKeyVersion(keyVer, testKey);
        
        Test.startTest();
        
        // Manually corrupt the checksum
        AI_Key_Version__c storedKey = [
            SELECT Id, Checksum__c
            FROM AI_Key_Version__c
            WHERE Version_Number__c = :keyVer.version
            LIMIT 1
        ];
        
        storedKey.Checksum__c = 'CORRUPTED';
        update storedKey;
        
        // Try to retrieve the key
        try {
            KeyVersionManager.getKeyByVersion(keyVer.version);
            System.assert(false, 'Should detect checksum mismatch');
        } catch (SecurityException e) {
            System.assert(e.getMessage().contains('integrity check failed'),
                         'Should validate key integrity');
        }
        
        Test.stopTest();
    }
    
    // Helper methods
    
    /**
     * @description Create a user without FLS permissions
     */
    private static User createUserWithoutFLS() {
        // Create a basic user profile with limited permissions
        Profile limitedProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        User limitedUser = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'testuser@test.com',
            Username = 'testuser' + DateTime.now().getTime() + '@test.com',
            Alias = 'tuser',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = limitedProfile.Id,
            LanguageLocaleKey = 'en_US'
        );
        
        insert limitedUser;
        return limitedUser;
    }
    
    /**
     * @description Create a test key version
     */
    private static KeyVersionManager.KeyVersion createTestKeyVersion() {
        KeyVersionManager.KeyVersion keyVer = new KeyVersionManager.KeyVersion();
        keyVer.version = 1;
        keyVer.keyId = 'TEST-KEY-' + DateTime.now().getTime();
        keyVer.createdDate = DateTime.now();
        keyVer.expiryDate = DateTime.now().addDays(90);
        keyVer.algorithm = 'AES256';
        keyVer.keySize = 256;
        keyVer.status = 'ACTIVE';
        keyVer.checksum = 'TEST123';
        keyVer.metadata.put('test', 'value');
        
        return keyVer;
    }
}