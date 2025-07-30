# RouteLogic Enhanced v4.0.0 - Security Configuration Deployment Guide

## Overview
This guide walks through deploying and configuring the security components for RouteLogic Enhanced v4.0.0.

## Pre-Deployment Checklist
- [ ] Salesforce org with API version 59.0+
- [ ] System Administrator access
- [ ] Platform Cache enabled in org
- [ ] Custom Metadata Types enabled

## Deployment Steps

### 1. Deploy Metadata Components

Deploy all security-related metadata using Salesforce CLI:

```bash
# Deploy all security components
sfdx force:source:deploy -p force-app/main/default -u your-org-alias

# Or deploy specific components
sfdx force:source:deploy -p force-app/main/default/objects,force-app/main/default/permissionsets,force-app/main/default/customPermissions,force-app/main/default/cachePartitions -u your-org-alias
```

### 2. Configure Platform Cache

After deployment, configure the Platform Cache partition:

1. Navigate to **Setup → Platform Cache**
2. Find the "RouteLogic" partition
3. If needed, adjust the capacity allocation:
   - Minimum recommended: 10MB
   - For production: 20MB+

### 3. Configure Master Encryption Key

**Option A: Using Protected Custom Setting (Recommended)**

1. Create a Protected Custom Setting for the master secret:
```
Setup → Custom Settings → New
- Label: RouteLogic Master Secret
- Object Name: RouteLogic_Master_Secret
- Setting Type: Hierarchy
- Visibility: Protected
```

2. Add a text field for the secret (255 chars)

**Option B: Initial Configuration**

Run this anonymous Apex to generate and store the initial master key:

```apex
// Generate initial master key
String masterKey = RouteLogicEncryptionUtility.generateRandomKey();
System.debug('Master Key Generated. Store this securely: ' + masterKey);

// The key will be automatically saved on first use
```

### 4. Assign Security Permissions

Grant the security admin permission set to appropriate users:

```bash
# Via CLI
sfdx force:user:permset:assign -n RouteLogic_Security_Admin -u your-org-alias -o user@example.com

# Or via UI
# Setup → Permission Sets → RouteLogic Security Admin → Manage Assignments
```

### 5. Initialize Security Settings

Run this anonymous Apex to initialize security settings:

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

System.debug('Security settings initialized successfully');
```

### 6. Test Encryption

Verify the encryption is working:

```apex
// Test encryption
String testData = 'Sensitive information';
String encrypted = RouteLogicEncryptionUtility.encrypt(testData);
String decrypted = RouteLogicEncryptionUtility.decrypt(encrypted);

System.assert(testData == decrypted, 'Encryption/Decryption failed');
System.debug('Encryption test passed');
```

### 7. Configure Named Credentials (if not already done)

For each AI provider (Ada, Intercom, etc.):

1. Navigate to **Setup → Named Credentials**
2. Verify "Ada_API" exists
3. Configure OAuth settings:
   - Authentication Provider: Ada_OAuth_Provider
   - Scope: As required by provider
   - Start Authentication Flow on Save: Checked

## Post-Deployment Validation

### Security Checklist
- [ ] Platform Cache partition active
- [ ] Master encryption key generated and stored
- [ ] Security admin users assigned permission set
- [ ] Encryption/decryption test passed
- [ ] Named Credentials configured

### Run Security Validation

```apex
// Comprehensive security validation
try {
    // 1. Test encryption
    String encrypted = RouteLogicEncryptionUtility.encrypt('test');
    RouteLogicEncryptionUtility.decrypt(encrypted);
    System.debug('✓ Encryption working');
    
    // 2. Check Platform Cache
    Cache.OrgPartition orgPart = Cache.Org.getPartition('RouteLogic');
    System.debug('✓ Platform Cache available: ' + (orgPart != null));
    
    // 3. Check security settings
    AI_Security_Settings__c settings = AI_Security_Settings__c.getOrgDefaults();
    System.debug('✓ Security settings initialized: ' + (settings.Id != null));
    
    // 4. Check permissions
    Boolean hasPermission = FeatureManagement.checkPermission('RouteLogic_Security_Admin');
    System.debug('✓ Security admin permission available: ' + hasPermission);
    
    System.debug('All security validations passed!');
} catch (Exception e) {
    System.debug('Security validation failed: ' + e.getMessage());
}
```

## Troubleshooting

### Platform Cache Issues
- **Error**: "Cache partition not found"
- **Solution**: Ensure Platform Cache is enabled and partition is created

### Encryption Key Issues
- **Error**: "Failed to get encryption key"
- **Solution**: Run initialization script in step 5

### Permission Issues
- **Error**: "Insufficient privileges"
- **Solution**: Assign RouteLogic_Security_Admin permission set

## Security Best Practices

1. **Key Rotation**: Schedule monthly key rotation reviews
2. **Access Control**: Limit security admin permissions to 2-3 users
3. **Audit Trail**: Enable field history tracking on security objects
4. **Monitoring**: Set up alerts for encryption failures
5. **Backup**: Export encryption metadata before major changes

## Next Steps

1. Configure production environment variables
2. Set up key rotation schedule
3. Document emergency procedures
4. Train security administrators
5. Implement monitoring and alerting

## Support

For issues or questions:
- Review error logs in Setup → Debug Logs
- Check RouteLogic application logs
- Contact support with deployment ID and error details