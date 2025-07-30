# RouteLogic Enhanced - Deployment Guide

## Pre-Deployment Checklist

### System Requirements
- [ ] Salesforce Enterprise Edition or higher
- [ ] API Enabled (Setup > Company Information)
- [ ] Platform Events enabled
- [ ] Platform Cache enabled
- [ ] Lightning Experience enabled (recommended)
- [ ] Minimum 5GB data storage available
- [ ] Minimum 1GB file storage available

### User Permissions Required
- [ ] System Administrator profile for installation
- [ ] Modify All Data permission
- [ ] View Setup and Configuration
- [ ] Customize Application

## Deployment Methods

### Method 1: AppExchange Installation (Recommended)

1. **Navigate to AppExchange**
   - Search for "RouteLogic Enhanced"
   - Click "Get It Now"

2. **Select Installation Options**
   - Choose production or sandbox
   - Install for Admins Only (recommended initially)
   - Click "Install"

3. **Grant Third-Party Access**
   - Review permissions requested
   - Approve access for Named Credentials

4. **Wait for Installation**
   - Installation typically takes 5-10 minutes
   - You'll receive an email when complete

### Method 2: Salesforce CLI Deployment

```bash
# Authenticate to your org
sfdx force:auth:web:login -a MyOrg

# Deploy the source
sfdx force:source:deploy -p force-app -u MyOrg

# Run post-deployment script
sfdx force:apex:execute -f scripts/post-deploy.apex -u MyOrg
```

### Method 3: Change Set Deployment

1. **In Source Org:**
   - Setup > Outbound Change Sets
   - Create new change set "RouteLogic Enhanced v3.1.0"
   - Add all components from package.xml
   - Upload to target org

2. **In Target Org:**
   - Setup > Inbound Change Sets
   - Deploy the change set
   - Run test classes

## Post-Installation Configuration

### Step 1: Create Default Configuration

1. Navigate to **Setup > Custom Metadata Types**
2. Find **AI Processing Config**
3. Click **Manage Records**
4. Click **New**
5. Create record with:
   ```
   Label: Default
   DeveloperName: Default
   Default_Batch_Size__c: 200
   Max_Retry_Attempts__c: 3
   Retry_Delay_Minutes__c: 5
   Max_Concurrent_Jobs__c: 5
   Callout_Timeout_Ms__c: 120000
   Enable_Request_Compression__c: true
   Compression_Threshold_Bytes__c: 1024
   Rate_Limit_TTL_Seconds__c: 60
   Max_Rate_Limit_Retries__c: 3
   Error_Log_Retention_Days__c: 30
   Audit_Log_Retention_Days__c: 365
   Enable_IP_Anonymization__c: true (for GDPR)
   Enable_PII_Masking__c: true (if needed)
   PII_Masking_Regions__c: EU,UK,CA,AU (as needed)
   ```

### Step 2: Configure Named Credentials

1. **Ada API Configuration**
   - Setup > Named Credentials
   - Edit "Ada_API"
   - Update endpoint: `https://api.ada.support/v1`
   - Add authentication details

2. **Intercom API Configuration**
   - Edit "Intercom_API"
   - Update endpoint: `https://api.intercom.io`
   - Add OAuth or token authentication

### Step 3: Configure Platform Cache

1. Navigate to **Setup > Platform Cache**
2. Find **AIRateLimit** partition
3. Allocate cache:
   - Session Cache: 10MB minimum
   - Organization Cache: 10MB minimum

### Step 4: Schedule Background Jobs

Execute in Developer Console:
```apex
// Schedule log retention (daily at 2 AM)
System.schedule('RouteLogic Log Retention', 
    '0 0 2 * * ?', 
    new LogRetentionScheduler());

// Schedule key rotation (monthly)
System.schedule('RouteLogic Key Rotation', 
    '0 0 0 1 * ?', 
    new EncryptionKeyRotationSchedule());
```

### Step 5: Assign Permission Sets

1. Navigate to **Setup > Permission Sets**
2. Find **RouteLogic_Admin** and **RouteLogic_User**
3. Assign to appropriate users:
   - Admins: RouteLogic_Admin
   - Regular Users: RouteLogic_User

### Step 6: Configure Page Layouts

1. **Case Page Layout**
   - Add AI fields section
   - Include: AI_Processing_Status__c, AI_Sentiment__c, AI_Intent__c
   - Add AI Processing related list

2. **Add Lightning Components**
   - Edit Case Lightning Page
   - Add "AI Processing Dashboard" component
   - Add "Force Process Cases" component

## Validation Steps

### 1. Test Basic Functionality
```apex
// Run in Anonymous Apex
Case testCase = new Case(
    Subject = 'Test RouteLogic Installation',
    Description = 'Testing AI processing',
    Priority = 'High'
);
insert testCase;

// Trigger AI processing
AI_Case_Request__e evt = new AI_Case_Request__e(
    CaseId__c = testCase.Id,
    AI_Provider__c = 'Ada',
    Priority__c = 'High',
    Request_Type__c = 'Analysis'
);
EventBus.publish(evt);
```

### 2. Verify Components
- [ ] All Apex classes deployed (90+ classes)
- [ ] All custom objects created
- [ ] Platform Events configured
- [ ] Named Credentials accessible
- [ ] Lightning components visible
- [ ] Permission sets created

### 3. Run Test Suite
```apex
// Execute all tests
ComprehensiveTestSuite.runAll();
```

## Common Deployment Issues

### Issue: "Insufficient Privileges" Error
**Solution:** Ensure installing user has System Administrator profile

### Issue: Platform Event Delivery Fails
**Solution:** 
1. Check Platform Event settings
2. Verify subscriber is active
3. Check debug logs for errors

### Issue: Named Credential Authentication Fails
**Solution:**
1. Verify endpoint URL is correct
2. Check firewall/IP restrictions
3. Validate API credentials

### Issue: Test Failures During Deployment
**Solution:**
1. Run tests in sandbox first
2. Check for required custom settings
3. Verify all dependencies deployed

## Security Hardening

### Enable Shield Platform Encryption (Optional)
1. Setup > Platform Encryption
2. Enable for custom objects:
   - AI_Conversation_Entry__c
   - AI_Processing_Status__c
   - Error_Log__c

### Configure IP Restrictions
1. Setup > Network Access
2. Add trusted IP ranges
3. Enable login IP restrictions

### Review Sharing Settings
1. Setup > Sharing Settings
2. Set OWD for custom objects to Private
3. Create sharing rules as needed

## Production Deployment Best Practices

1. **Deploy During Maintenance Window**
   - Schedule during low-usage hours
   - Notify users in advance

2. **Backup Current Configuration**
   - Export all metadata
   - Document current settings

3. **Deploy in Phases**
   - Phase 1: Core components
   - Phase 2: Configuration
   - Phase 3: User access

4. **Monitor Post-Deployment**
   - Check error logs
   - Monitor performance
   - Verify integrations

## Rollback Procedure

If issues occur:

1. **Immediate Rollback**
   ```bash
   sfdx force:source:deploy -p backup/previous-version -u MyOrg
   ```

2. **Disable Features**
   - Deactivate triggers
   - Disable Platform Events
   - Remove permission sets

3. **Uninstall Package**
   - Setup > Installed Packages
   - Uninstall RouteLogic Enhanced
   - Note: This will delete all data

## Support Resources

- **Documentation**: /docs folder in package
- **Email Support**: support@routelogic.com
- **Knowledge Base**: https://help.routelogic.com
- **Video Tutorials**: Available post-installation

## Next Steps

After successful deployment:
1. Review [ADMIN_GUIDE.md](./ADMIN_GUIDE.md)
2. Complete user training
3. Configure monitoring alerts
4. Plan phased rollout to users