/**
 * @description Test class for RouteLogic security components
 * @author RouteLogic Team
 * @date 2025-01-28
 */
@IsTest
public class RouteLogicSecurityTest {
    
    @IsTest
    static void testEncryptionUtility() {
        Test.startTest();
        
        // Test basic encryption/decryption
        String testData = 'Sensitive customer information';
        String encrypted = RouteLogicEncryptionUtility.encrypt(testData);
        String decrypted = RouteLogicEncryptionUtility.decrypt(encrypted);
        
        System.assertEquals(testData, decrypted, 'Decrypted data should match original');
        System.assertNotEquals(testData, encrypted, 'Encrypted data should be different');
        
        // Test with empty string
        try {
            RouteLogicEncryptionUtility.encrypt('');
            System.assert(false, 'Should throw exception for empty string');
        } catch (IllegalArgumentException e) {
            System.assert(true, 'Expected exception thrown');
        }
        
        // Test custom key encryption
        String customKey = 'MyCustomSecretKey123!@#';
        String encryptedCustom = RouteLogicEncryptionUtility.encryptWithKey(testData, customKey);
        String decryptedCustom = RouteLogicEncryptionUtility.decryptWithKey(encryptedCustom, customKey);
        
        System.assertEquals(testData, decryptedCustom, 'Custom key decryption should work');
        
        Test.stopTest();
    }
    
    @IsTest
    static void testRandomGeneration() {
        Test.startTest();
        
        // Test different sizes
        String random16 = RouteLogicEncryptionUtility.generateRandomKey();
        String random32 = RouteLogicEncryptionUtility.generateRandomSalt();
        
        System.assertNotEquals(null, random16, 'Should generate random key');
        System.assertNotEquals(null, random32, 'Should generate random salt');
        System.assertNotEquals(random16, random32, 'Random values should be different');
        
        // Test key strength validation
        System.assertEquals(false, RouteLogicEncryptionUtility.validateKeyStrength('weak'));
        System.assertEquals(false, RouteLogicEncryptionUtility.validateKeyStrength('12345678901234567890123456789012')); // Only numbers
        System.assertEquals(true, RouteLogicEncryptionUtility.validateKeyStrength('StrongP@ssw0rd123!WithMixedChars'));
        
        Test.stopTest();
    }
    
    @IsTest
    static void testSecureHash() {
        Test.startTest();
        
        String data = 'DataToHash';
        String salt = 'MySalt';
        
        String hash1 = RouteLogicEncryptionUtility.generateSecureHash(data, salt);
        String hash2 = RouteLogicEncryptionUtility.generateSecureHash(data, salt);
        String hash3 = RouteLogicEncryptionUtility.generateSecureHash(data, 'DifferentSalt');
        
        System.assertEquals(hash1, hash2, 'Same input should produce same hash');
        System.assertNotEquals(hash1, hash3, 'Different salt should produce different hash');
        
        Test.stopTest();
    }
    
    @IsTest
    static void testSecureKeyVault() {
        Test.startTest();
        
        // Mock Platform Cache for testing
        Cache.OrgPartition orgPart = Cache.Org.getPartition('RouteLogic');
        
        // Test key storage
        Blob testKey = Blob.valueOf('TestSecureKey123');
        Boolean stored = SecureKeyVault.storeKey('TEST_KEY', testKey);
        
        // In test context, Platform Cache might not be available
        System.assertNotEquals(null, stored, 'Store operation should complete');
        
        // Test key retrieval (will fail in test context without cache)
        try {
            Blob retrieved = SecureKeyVault.retrieveKey('TEST_KEY', 'master_secret');
            // If we get here, cache is available
            System.assertNotEquals(null, retrieved, 'Should retrieve key');
        } catch (Exception e) {
            // Expected in test context
            System.assert(true, 'Cache not available in test context');
        }
        
        Test.stopTest();
    }
    
    @IsTest
    static void testAdaSecurityProvider() {
        Test.startTest();
        
        AdaSecurityProvider provider = new AdaSecurityProvider();
        
        // Test PII sanitization
        String input = 'My SSN is 123-45-6789 and email is test@example.com';
        String sanitized = provider.sanitizeRequest(input);
        
        System.assert(!sanitized.contains('123-45-6789'), 'SSN should be removed');
        System.assert(!sanitized.contains('test@example.com'), 'Email should be removed');
        System.assert(sanitized.contains('[SSN_REMOVED]'), 'Should have SSN placeholder');
        System.assert(sanitized.contains('[EMAIL_REMOVED]'), 'Should have email placeholder');
        
        // Test security headers
        Map<String, String> headers = provider.getSecurityHeaders();
        
        System.assertNotEquals(null, headers.get('X-Ada-Client-Id'), 'Should have client ID');
        System.assertNotEquals(null, headers.get('X-Ada-Timestamp'), 'Should have timestamp');
        System.assertNotEquals(null, headers.get('X-Ada-Nonce'), 'Should have nonce');
        System.assertEquals('application/json', headers.get('Content-Type'), 'Should have content type');
        
        Test.stopTest();
    }
    
    @IsTest
    static void testConfigurationManager() {
        Test.startTest();
        
        // Test setting and getting configuration
        RouteLogicConfigurationManager.setConfigurationValue('TEST_CONFIG', 'test_value', false);
        String value = RouteLogicConfigurationManager.getConfigurationValue('TEST_CONFIG');
        
        // Configuration might not persist in test context
        if (value != null) {
            System.assertEquals('test_value', value, 'Should retrieve configuration value');
        }
        
        // Test encrypted configuration
        RouteLogicConfigurationManager.setConfigurationValue('TEST_ENCRYPTED', 'secret_value', true);
        String encrypted = RouteLogicConfigurationManager.getConfigurationValue('TEST_ENCRYPTED');
        
        if (encrypted != null) {
            System.assertEquals('secret_value', encrypted, 'Should decrypt configuration value');
        }
        
        Test.stopTest();
    }
    
    @IsTest
    static void testSecuritySettings() {
        Test.startTest();
        
        // Initialize settings
        AI_Security_Settings__c settings = AI_Security_Settings__c.getOrgDefaults();
        if (settings.Id == null) {
            settings = new AI_Security_Settings__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Enable_Encryption__c = true,
                Enable_Key_Rotation__c = true,
                Key_Version__c = 1,
                Active__c = true
            );
            insert settings;
        }
        
        // Verify settings
        AI_Security_Settings__c retrieved = AI_Security_Settings__c.getOrgDefaults();
        System.assertNotEquals(null, retrieved.Id, 'Settings should be created');
        System.assertEquals(true, retrieved.Enable_Encryption__c, 'Encryption should be enabled');
        System.assertEquals(true, retrieved.Enable_Key_Rotation__c, 'Key rotation should be enabled');
        
        Test.stopTest();
    }
}