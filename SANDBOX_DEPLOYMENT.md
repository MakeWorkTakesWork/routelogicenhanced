# RouteLogic Enhanced v4.0.0 - Sandbox Deployment & Testing

## Quick Start

```bash
# 1. Deploy to sandbox
cd /Users/johnsweazey/routelogicenhanced4.0.0
./scripts/deploy-security.sh YOUR_SANDBOX_ALIAS

# 2. Run tests
./scripts/test-security.sh YOUR_SANDBOX_ALIAS

# 3. Assign permissions (run in sandbox)
sfdx force:apex:execute -f scripts/assign-permissions.apex -u YOUR_SANDBOX_ALIAS
```

## Detailed Steps

### Step 1: Pre-Deployment Verification

```bash
# Verify you're in the right directory
pwd
# Should show: /Users/johnsweazey/routelogicenhanced4.0.0

# Check your sandbox connection
sfdx force:org:list
```

### Step 2: Deploy Security Components

```bash
# Run the deployment script
./scripts/deploy-security.sh YOUR_SANDBOX_ALIAS

# Or deploy manually
sfdx force:source:deploy -p RouteLogic-v4.0.0/force-app/main/default -u YOUR_SANDBOX_ALIAS
```

### Step 3: Configure Platform Cache

After deployment, in your sandbox:

1. Go to **Setup → Platform Cache**
2. Click on "RouteLogic" partition
3. If not visible, click "New Platform Cache Partition":
   - Name: RouteLogic
   - Allocated Capacity: 10 MB (minimum)

### Step 4: Initialize Security Settings

Run this in Developer Console or Workbench:

```apex
// Initialize security settings
AI_Security_Settings__c settings = new AI_Security_Settings__c(
    SetupOwnerId = UserInfo.getOrganizationId(),
    Enable_Encryption__c = true,
    Enable_Key_Rotation__c = true,
    Key_Version__c = 1,
    Active__c = true,
    Last_Rotation_Date__c = DateTime.now(),
    Next_Rotation_Date__c = DateTime.now().addDays(90)
);
insert settings;

System.debug('Security settings initialized');
```

### Step 5: Run Security Tests

```bash
# Run the test script
./scripts/test-security.sh YOUR_SANDBOX_ALIAS

# Or run specific test class
sfdx force:apex:test:run -n RouteLogicSecurityTest -u YOUR_SANDBOX_ALIAS -r human
```

### Step 6: Verify Configuration

Run this validation script:

```apex
// Comprehensive validation
try {
    // 1. Encryption test
    String encrypted = RouteLogicEncryptionUtility.encrypt('test');
    String decrypted = RouteLogicEncryptionUtility.decrypt(encrypted);
    System.debug('✓ Encryption: ' + (decrypted == 'test' ? 'PASS' : 'FAIL'));
    
    // 2. Cache test
    Cache.OrgPartition orgPart = Cache.Org.getPartition('RouteLogic');
    System.debug('✓ Platform Cache: ' + (orgPart != null ? 'AVAILABLE' : 'NOT FOUND'));
    
    // 3. Settings test
    AI_Security_Settings__c settings = AI_Security_Settings__c.getOrgDefaults();
    System.debug('✓ Security Settings: ' + (settings.Id != null ? 'CONFIGURED' : 'NOT CONFIGURED'));
    
    // 4. Permission test
    Boolean hasPerm = FeatureManagement.checkPermission('RouteLogic_Security_Admin');
    System.debug('✓ Security Permission: ' + (hasPerm ? 'GRANTED' : 'NOT GRANTED'));
    
    System.debug('==== VALIDATION COMPLETE ====');
} catch (Exception e) {
    System.debug('✗ Validation failed: ' + e.getMessage());
}
```

## Expected Test Results

### Successful Deployment
```
✓ Encryption/Decryption test PASSED
✓ Random byte generation test PASSED
✓ Platform Cache test PASSED
✓ Security Settings already configured
✓ Configuration Manager test PASSED
✓ Secure Key Vault storage test PASSED
✅ All tests PASSED! Security configuration is ready.
```

### Common Issues & Solutions

#### Issue: Platform Cache Not Found
```
⚠ Platform Cache partition not found
```
**Solution**: Manually create the partition in Setup → Platform Cache

#### Issue: Permission Denied
```
✗ Security admin permission required
```
**Solution**: Run the permission assignment script

#### Issue: Encryption Key Not Found
```
Failed to get encryption key
```
**Solution**: The key will be auto-generated on first use

## Manual Testing Checklist

- [ ] Encryption works (encrypt/decrypt test data)
- [ ] Platform Cache is accessible
- [ ] Security settings are initialized
- [ ] Permission set is assigned to admin user
- [ ] Named Credentials show as configured
- [ ] No errors in debug logs

## Next Steps After Successful Deployment

1. **Production Deployment Planning**
   - Review security configurations
   - Plan key rotation schedule
   - Document admin procedures

2. **Integration Testing**
   - Test with actual Ada webhooks
   - Verify handoff encryption
   - Test bulk operations

3. **Security Hardening**
   - Enable field audit trail
   - Configure Shield Platform Encryption
   - Set up monitoring alerts

## Rollback Instructions

If issues occur:

```bash
# Remove deployed components
sfdx force:source:delete -p RouteLogic-v4.0.0/force-app/main/default -u YOUR_SANDBOX_ALIAS

# Or selectively remove problem components
sfdx force:source:delete -p RouteLogic-v4.0.0/force-app/main/default/classes/SecureKeyVault.cls -u YOUR_SANDBOX_ALIAS
```

## Support

For deployment issues:
1. Check Setup → Deployment Status
2. Review debug logs
3. Verify all prerequisites are met
4. Run validation script for diagnostics