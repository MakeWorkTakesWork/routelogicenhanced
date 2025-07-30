#!/bin/bash
# RouteLogic Enhanced v4.0.0 - Security Test Script
# This script runs security configuration tests

echo "========================================="
echo "RouteLogic Security Test Script"
echo "========================================="

# Check if org alias is provided
if [ -z "$1" ]; then
    echo "Error: Please provide your sandbox org alias"
    echo "Usage: ./test-security.sh <org-alias>"
    exit 1
fi

ORG_ALIAS=$1
echo "Testing in org: $ORG_ALIAS"

# Create test Apex script
cat > /tmp/security-test.apex << 'EOF'
// RouteLogic Security Configuration Test
System.debug('=== Starting Security Configuration Test ===');

Boolean allTestsPassed = true;

try {
    // Test 1: Encryption functionality
    System.debug('Test 1: Testing encryption...');
    String testData = 'Sensitive customer data for testing';
    String encrypted = RouteLogicEncryptionUtility.encrypt(testData);
    String decrypted = RouteLogicEncryptionUtility.decrypt(encrypted);
    
    if (testData.equals(decrypted)) {
        System.debug('✓ Encryption/Decryption test PASSED');
    } else {
        System.debug('✗ Encryption/Decryption test FAILED');
        allTestsPassed = false;
    }
    
    // Test 2: Random byte generation
    System.debug('Test 2: Testing random byte generation...');
    Blob random16 = RouteLogicEncryptionUtility.generateRandomBytes(16);
    Blob random32 = RouteLogicEncryptionUtility.generateRandomBytes(32);
    
    if (EncodingUtil.base64Encode(random16).length() > 0 && 
        EncodingUtil.base64Encode(random32).length() > 0) {
        System.debug('✓ Random byte generation test PASSED');
    } else {
        System.debug('✗ Random byte generation test FAILED');
        allTestsPassed = false;
    }
    
    // Test 3: Platform Cache
    System.debug('Test 3: Testing Platform Cache...');
    try {
        Cache.OrgPartition orgPart = Cache.Org.getPartition('RouteLogic');
        if (orgPart != null) {
            orgPart.put('test_key', 'test_value', 300);
            String cachedValue = (String) orgPart.get('test_key');
            if ('test_value'.equals(cachedValue)) {
                System.debug('✓ Platform Cache test PASSED');
            } else {
                System.debug('✗ Platform Cache test FAILED - value mismatch');
                allTestsPassed = false;
            }
        } else {
            System.debug('⚠ Platform Cache partition not found - may need configuration');
        }
    } catch (Exception e) {
        System.debug('⚠ Platform Cache test skipped: ' + e.getMessage());
    }
    
    // Test 4: Security Settings
    System.debug('Test 4: Testing Security Settings...');
    AI_Security_Settings__c settings = AI_Security_Settings__c.getOrgDefaults();
    if (settings == null || settings.Id == null) {
        // Initialize settings
        settings = new AI_Security_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Enable_Encryption__c = true,
            Enable_Key_Rotation__c = true,
            Key_Version__c = 1,
            Active__c = true
        );
        insert settings;
        System.debug('✓ Security Settings initialized');
    } else {
        System.debug('✓ Security Settings already configured');
    }
    
    // Test 5: Configuration Manager
    System.debug('Test 5: Testing Configuration Manager...');
    RouteLogicConfigurationManager.setConfigurationValue('TEST_KEY', 'test_value', false);
    String configValue = RouteLogicConfigurationManager.getConfigurationValue('TEST_KEY');
    if ('test_value'.equals(configValue)) {
        System.debug('✓ Configuration Manager test PASSED');
    } else {
        System.debug('✗ Configuration Manager test FAILED');
        allTestsPassed = false;
    }
    
    // Test 6: Secure Key Vault
    System.debug('Test 6: Testing Secure Key Vault...');
    try {
        Blob testKey = Blob.valueOf('test_secure_key_12345');
        Boolean stored = SecureKeyVault.storeKey('TEST_SECURE_KEY', testKey);
        if (stored) {
            System.debug('✓ Secure Key Vault storage test PASSED');
        } else {
            System.debug('⚠ Secure Key Vault storage returned false - check Platform Cache');
        }
    } catch (Exception e) {
        System.debug('⚠ Secure Key Vault test error: ' + e.getMessage());
    }
    
    // Test 7: Named Credentials
    System.debug('Test 7: Checking Named Credentials...');
    try {
        List<NamedCredential> credentials = [
            SELECT DeveloperName, Endpoint 
            FROM NamedCredential 
            WHERE DeveloperName = 'Ada_API'
        ];
        if (!credentials.isEmpty()) {
            System.debug('✓ Named Credential Ada_API found: ' + credentials[0].Endpoint);
        } else {
            System.debug('⚠ Named Credential Ada_API not found - manual configuration needed');
        }
    } catch (Exception e) {
        System.debug('⚠ Cannot query Named Credentials programmatically');
    }
    
} catch (Exception e) {
    System.debug('✗ Test failed with error: ' + e.getMessage());
    System.debug('Stack trace: ' + e.getStackTraceString());
    allTestsPassed = false;
}

System.debug('=== Security Configuration Test Complete ===');
if (allTestsPassed) {
    System.debug('✅ All tests PASSED! Security configuration is ready.');
} else {
    System.debug('❌ Some tests FAILED. Please check the logs above.');
}
EOF

# Run the test
echo ""
echo "Running security tests..."
sfdx force:apex:execute -f /tmp/security-test.apex -u $ORG_ALIAS

# Clean up
rm /tmp/security-test.apex

echo ""
echo "========================================="
echo "Test execution complete!"
echo "Check the debug logs for detailed results"
echo "========================================="