# RouteLogic Enhanced - Installation Guide

## Quick Start Installation

### From AppExchange (5 minutes)

1. **Visit AppExchange**
   - Go to [Salesforce AppExchange](https://appexchange.salesforce.com)
   - Search for "RouteLogic Enhanced"
   - Click "Get It Now"

2. **Choose Environment**
   - Select Production or Sandbox
   - Click "Install in Production" or "Install in Sandbox"

3. **Log In**
   - Enter your Salesforce credentials
   - Grant access if prompted

4. **Configure Installation**
   - Install for: **Admins Only** (Recommended)
   - Click "Install"

5. **Approve Access**
   - Review third-party access
   - Click "Continue"
   - Click "Done" when installation completes

## Detailed Installation Steps

### Pre-Installation Requirements

#### Verify Salesforce Edition
```
Setup > Company Information > Organization Edition
Required: Enterprise, Unlimited, or Developer Edition
```

#### Enable Required Features
1. **API Access**
   - Setup > Company Information
   - Verify "API Enabled" is checked

2. **Platform Events**
   - Setup > Platform Events
   - Ensure Platform Events are enabled

3. **Platform Cache**
   - Setup > Platform Cache
   - Create partition if none exists

### Installation Process

#### Step 1: Backup Current System
```bash
# Using Salesforce CLI
sfdx force:mdapi:retrieve -r ./backup -u YourOrg -p "Package1,Package2"
```

#### Step 2: Install Package

**Option A: AppExchange**
- Follow Quick Start steps above

**Option B: Unlocked Package**
```bash
# Install specific version
sfdx force:package:install --package 04t... -u YourOrg --wait 10
```

**Option C: GitHub/Source Deploy**
```bash
# Clone repository
git clone https://github.com/your-org/routelogic-enhanced.git
cd routelogic-enhanced

# Deploy to org
sfdx force:source:deploy -p force-app -u YourOrg
```

#### Step 3: Post-Install Configuration

The package includes an automated post-install script that:
- Creates default configuration records
- Sets up Platform Cache partitions
- Initializes encryption keys
- Configures audit settings

To run manually if needed:
```apex
// Execute in Developer Console
PostInstallScript postInstall = new PostInstallScript();
postInstall.onInstall(null);
```

### Configuration Wizard

After installation, access the Configuration Wizard:

1. **App Launcher** > **RouteLogic Enhanced**
2. Click **Setup Wizard**
3. Follow the guided setup:

#### Wizard Step 1: API Credentials
- Enter Ada API credentials
- Enter Intercom API credentials
- Test connections

#### Wizard Step 2: Security Settings
- Enable IP Anonymization (GDPR)
- Configure PII Masking regions
- Set retention policies

#### Wizard Step 3: Processing Configuration
- Set default batch size (200 recommended)
- Configure retry attempts
- Set rate limits

#### Wizard Step 4: User Access
- Assign permission sets
- Configure field-level security
- Set up sharing rules

## Component Installation Details

### Apex Classes (97 files)
- Core processing: 35 classes
- Security layer: 15 classes
- Integration: 20 classes
- Utilities: 15 classes
- Test classes: 12 classes

### Custom Objects (11 objects)
```
AI_Archive_Reference__c     - Audit archive storage
AI_Audit_Event__c          - Audit log entries
AI_Bulk_Processing_Metrics__c - Performance metrics
AI_Callback_Context__c     - Webhook context
AI_Conversation_Entry__c   - Conversation history
AI_Conversation_Session__c - Session management
AI_Key_Version__c         - Encryption keys
AI_Processing_Status__c   - Processing status
AI_Rate_Limit__c         - Rate limiting
AI_Retry_Request__c      - Retry queue
Error_Log__c             - Error logging
```

### Platform Events (5 events)
```
AI_Audit_Platform_Event__e
AI_Case_Request__e
AI_Critical_Error__e
AI_Processing_Metric__e
AI_Webhook_Response__e
```

### Lightning Components (3 components)
- AI Bulk Processing Dashboard
- AI Force Process Cases
- AI Processing Metrics

### Custom Metadata Types (2 types)
- AI_Processing_Config__mdt
- AI_Provider_Settings__mdt

## Verification Steps

### 1. Verify Installation
```apex
// Check version
System.debug([SELECT Id, SubscriberPackageId, 
    SubscriberPackageVersion.Name 
    FROM InstalledSubscriberPackage 
    WHERE SubscriberPackage.Name = 'RouteLogic Enhanced']);
```

### 2. Test Basic Functionality
```apex
// Create test case
Case c = new Case(Subject = 'Test', Priority = 'High');
insert c;

// Check AI fields added
System.debug(c.AI_Processing_Status__c);
```

### 3. Verify Components
- [ ] Navigate to Setup > Installed Packages
- [ ] Verify "RouteLogic Enhanced" appears
- [ ] Check version is 3.1.0
- [ ] Click "View Components"

### 4. Run Health Check
```apex
// Execute health check
AIBulkProcessingCoordinator.performHealthCheck();
```

## Troubleshooting Installation

### Common Issues

#### "Package Not Found" Error
- Verify you're in the correct org
- Check AppExchange listing is live
- Try direct package link

#### "Insufficient Privileges" Error
- Must be System Administrator
- Check profile permissions
- Verify API access enabled

#### "Dependency Missing" Error
- Enable Platform Events
- Enable Platform Cache
- Check Salesforce edition

#### Test Failures
- Run in sandbox first
- Check debug logs
- Verify all components deployed

### Installation Logs

View installation details:
```
Setup > Deployment Status
OR
Setup > Installed Packages > RouteLogic Enhanced > View Details
```

## Uninstall Process

If you need to uninstall:

1. **Backup Data**
   ```sql
   SELECT * FROM AI_Processing_Status__c
   SELECT * FROM AI_Conversation_Session__c
   SELECT * FROM Error_Log__c
   ```

2. **Deactivate Components**
   - Deactivate all triggers
   - Cancel scheduled jobs
   - Remove permission set assignments

3. **Uninstall Package**
   - Setup > Installed Packages
   - Click "Uninstall" next to RouteLogic Enhanced
   - Follow prompts

**Warning**: Uninstalling will permanently delete all package data.

## Post-Installation Tasks

### Required Configuration
1. Configure Named Credentials
2. Create AI Processing Config record
3. Schedule maintenance jobs
4. Assign permission sets

### Recommended Configuration
1. Enable Shield Encryption
2. Configure email alerts
3. Set up monitoring
4. Create custom reports

### User Training
1. Review user guide
2. Watch training videos
3. Practice in sandbox
4. Schedule admin training

## Getting Help

### Resources
- In-app help: Click ? icon
- Documentation: /docs folder
- Video tutorials: Upon request
- Support email: support@routelogic.com

### Support Levels
- **Basic**: Email support, 48hr response
- **Premium**: Priority support, 4hr response
- **Enterprise**: Dedicated support, 1hr response

## Next Steps

1. Complete [Post-Installation Checklist](./POST_INSTALL_CHECKLIST.md)
2. Review [Admin Guide](./ADMIN_GUIDE.md)
3. Configure security settings
4. Plan user rollout
5. Schedule training sessions