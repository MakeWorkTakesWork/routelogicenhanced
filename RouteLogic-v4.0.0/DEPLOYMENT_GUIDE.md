# RouteLogic Enhanced v4.0.0 - Deployment Guide

## 🎯 Deployment Overview

This guide provides step-by-step instructions for deploying RouteLogic Enhanced v4.0.0 from v3.3.0, including all security fixes, architectural improvements, and new features.

## 📋 Pre-Deployment Requirements

### System Requirements
- Salesforce API version 60.0 or higher
- Lightning Experience enabled
- Platform Events enabled
- Minimum 50MB of data storage available
- System Administrator or equivalent permissions

### Backup Requirements
- Export existing RouteLogic configuration
- Backup custom field data
- Document current routing rules
- Export audit trail data

### Environment Validation
```bash
# Validate org readiness
sfdx force:org:display -u target-org
sfdx force:limits:api:display -u target-org
sfdx force:user:display -u target-org
```

## 🚀 Deployment Steps

### Phase 1: Pre-Deployment Validation

#### 1.1 Environment Check
```apex
// Run in Anonymous Apex
System.debug('Org Edition: ' + UserInfo.getOrganizationType());
System.debug('API Version: ' + System.version());
System.debug('User License: ' + UserInfo.getLicenseType());

// Check Platform Events
List<PlatformEventChannel> channels = [SELECT DeveloperName FROM PlatformEventChannel];
System.debug('Platform Event Channels: ' + channels.size());
```

#### 1.2 Dependency Validation
```bash
# Check for conflicting packages
sfdx force:package:installed:list -u target-org

# Validate custom metadata types
sfdx force:data:soql:query -q "SELECT DeveloperName FROM CustomMetadataType WHERE DeveloperName LIKE 'RouteLogic%'" -u target-org
```

#### 1.3 Data Backup
```bash
# Export existing configuration
sfdx force:data:tree:export -q "SELECT Id, DeveloperName, Configuration_Type__c, Configuration_Value__c FROM RouteLogic_Configuration__mdt" -d backup/ -u target-org

# Export routing ledger
sfdx force:data:tree:export -q "SELECT Id, Case__c, Initial_AI_Provider__c, Routing_Engine_Decision__c FROM Routing_Ledger__c" -d backup/ -u target-org
```

### Phase 2: Core Deployment

#### 2.1 Deploy Metadata
```bash
# Deploy custom objects and fields
sfdx force:source:deploy -p force-app/main/default/objects -u target-org -l RunLocalTests

# Deploy Apex classes
sfdx force:source:deploy -p force-app/main/default/classes -u target-org -l RunLocalTests

# Deploy Lightning Web Components
sfdx force:source:deploy -p force-app/main/default/lwc -u target-org
```

#### 2.2 Deploy Configuration
```bash
# Deploy custom metadata types
sfdx force:source:deploy -p force-app/main/default/customMetadata -u target-org

# Deploy permission sets
sfdx force:source:deploy -p force-app/main/default/permissionsets -u target-org
```

#### 2.3 Validation Tests
```bash
# Run comprehensive test suite
sfdx force:apex:test:run -c -r human -d test-results/ -u target-org

# Validate specific components
sfdx force:apex:test:run -n "RouteLogicTestSuite,AgnosticRoutingEngineTest,RouteLogicObjectManagerTest" -u target-org
```

### Phase 3: Configuration Setup

#### 3.1 Security Configuration
```apex
// Generate encryption keys
String masterKey = RouteLogicEncryptionUtility.generateRandomKey();
String derivedKey = RouteLogicEncryptionUtility.deriveKey(masterKey, 'RouteLogic_v4');

// Store securely
RouteLogicConfigurationManager.setConfigurationValue(
    'Security_Master_Key', 
    masterKey, 
    true, // encrypted
    'Production'
);
```

#### 3.2 Provider Configuration
```apex
// Configure Ada.cx
Map<String, String> adaConfig = new Map<String, String>{
    'Provider_Ada_API_Key' => 'your-ada-api-key',
    'Provider_Ada_Endpoint' => 'https://api.ada.cx/v1',
    'Provider_Ada_Timeout' => '30',
    'Provider_Ada_Retry_Count' => '3'
};

for (String key : adaConfig.keySet()) {
    RouteLogicConfigurationManager.setConfigurationValue(
        key, 
        adaConfig.get(key), 
        key.contains('Key'), // encrypt API keys
        'Production'
    );
}

// Configure Intercom
Map<String, String> intercomConfig = new Map<String, String>{
    'Provider_Intercom_Access_Token' => 'your-intercom-token',
    'Provider_Intercom_Endpoint' => 'https://api.intercom.io',
    'Provider_Intercom_Timeout' => '30',
    'Provider_Intercom_Retry_Count' => '3'
};

for (String key : intercomConfig.keySet()) {
    RouteLogicConfigurationManager.setConfigurationValue(
        key, 
        intercomConfig.get(key), 
        key.contains('Token'), // encrypt tokens
        'Production'
    );
}
```

#### 3.3 Object Configuration
```apex
// Enable Case routing
RouteLogicObjectManager.ObjectConfiguration caseConfig = new RouteLogicObjectManager.ObjectConfiguration();
caseConfig.objectApiName = 'Case';
caseConfig.objectType = 'Case';
caseConfig.routingEnabled = true;
caseConfig.handoffEnabled = true;
caseConfig.supportedProviders = new List<String>{'Ada', 'Intercom'};
caseConfig.subjectField = 'Subject';
caseConfig.descriptionField = 'Description';
caseConfig.priorityField = 'Priority';
caseConfig.statusField = 'Status';
caseConfig.originField = 'Origin';
caseConfig.ownerField = 'OwnerId';
caseConfig.contactField = 'ContactId';
caseConfig.accountField = 'AccountId';

// Store configuration
RouteLogicConfigurationManager.setConfigurationValue(
    'Object_Config_Case',
    JSON.serialize(caseConfig),
    false,
    'Production'
);

// Enable Lead routing
RouteLogicObjectManager.ObjectConfiguration leadConfig = new RouteLogicObjectManager.ObjectConfiguration();
leadConfig.objectApiName = 'Lead';
leadConfig.objectType = 'Lead';
leadConfig.routingEnabled = true;
leadConfig.handoffEnabled = true;
leadConfig.supportedProviders = new List<String>{'Ada', 'Intercom'};
leadConfig.subjectField = 'Company';
leadConfig.descriptionField = 'Description';
leadConfig.priorityField = 'Rating';
leadConfig.statusField = 'Status';
leadConfig.originField = 'LeadSource';
leadConfig.ownerField = 'OwnerId';
leadConfig.contactField = 'ConvertedContactId';
leadConfig.accountField = 'ConvertedAccountId';

// Store configuration
RouteLogicConfigurationManager.setConfigurationValue(
    'Object_Config_Lead',
    JSON.serialize(leadConfig),
    false,
    'Production'
);
```

### Phase 4: Permission Assignment

#### 4.1 Assign Permission Sets
```bash
# Assign admin permission set
sfdx force:user:permset:assign -n RouteLogic_Admin -u admin@company.com

# Assign user permission set
sfdx force:user:permset:assign -n RouteLogic_User -u user@company.com

# Bulk assign to multiple users
sfdx force:data:bulk:upsert -s User -f users-permset-assignment.csv -u target-org
```

#### 4.2 Configure Sharing Rules
```apex
// Create sharing rules for routing ledger
// Setup → Sharing Settings → Routing Ledger → Sharing Rules
```

### Phase 5: Testing & Validation

#### 5.1 Functional Testing
```apex
// Test routing engine
List<Id> testCaseIds = new List<Id>{/* test case IDs */};
List<AgnosticRoutingEngine.RoutingDecision> decisions = 
    AgnosticRoutingEngine.processHandoffs(testCaseIds, 'Case');

System.debug('Routing decisions: ' + decisions.size());
for (AgnosticRoutingEngine.RoutingDecision decision : decisions) {
    System.debug('Decision: ' + decision.selectedProvider + ' for ' + decision.recordId);
}

// Test configuration manager
String testValue = RouteLogicConfigurationManager.getConfigurationValue('Provider_Ada_Endpoint');
System.debug('Ada endpoint: ' + testValue);

// Test object manager
List<String> supportedObjects = RouteLogicObjectManager.getSupportedObjectTypes();
System.debug('Supported objects: ' + supportedObjects);
```

#### 5.2 Performance Testing
```apex
// Test bulk processing
List<Id> bulkCaseIds = new List<Id>();
for (Integer i = 0; i < 100; i++) {
    // Add test case IDs
}

Long startTime = System.currentTimeMillis();
RouteLogicQueueableProcessor processor = new RouteLogicQueueableProcessor(
    'performance_test_' + DateTime.now().getTime(),
    'CASE_HANDOFF',
    bulkCaseIds,
    new Map<String, Object>{'provider' => 'Ada'},
    0
);
System.enqueueJob(processor);
Long endTime = System.currentTimeMillis();

System.debug('Bulk processing initiated in: ' + (endTime - startTime) + 'ms');
```

#### 5.3 Security Testing
```apex
// Test field-level security
Boolean hasAccess = RouteLogicSecurityUtils.hasReadAccess('Case');
System.debug('Case read access: ' + hasAccess);

// Test input sanitization
String sanitized = RouteLogicSecurityUtils.sanitizeInput('<script>alert("xss")</script>');
System.debug('Sanitized input: ' + sanitized);

// Test encryption
String encrypted = RouteLogicEncryptionUtility.encrypt('sensitive-data', 'test-key');
String decrypted = RouteLogicEncryptionUtility.decrypt(encrypted, 'test-key');
System.debug('Encryption test: ' + (decrypted == 'sensitive-data'));
```

### Phase 6: Monitoring Setup

#### 6.1 Configure Dashboards
```bash
# Deploy monitoring dashboards
sfdx force:source:deploy -p force-app/main/default/dashboards -u target-org

# Deploy reports
sfdx force:source:deploy -p force-app/main/default/reports -u target-org
```

#### 6.2 Set Up Alerts
```apex
// Configure platform event monitoring
// Setup → Platform Events → Subscribe to RouteLogic events

// Set up email alerts for critical errors
// Setup → Process Builder → New Process for RouteLogic_Dead_Letter_Queue__e
```

## 🔧 Post-Deployment Configuration

### User Training
1. Schedule administrator training sessions
2. Provide user documentation and guides
3. Set up support channels and escalation procedures
4. Create video tutorials for common tasks

### Performance Optimization
```apex
// Monitor initial performance
List<RouteLogicJobTracker.JobStatus> jobs = RouteLogicJobTracker.getJobHistory(Date.today().addDays(-1), Date.today());
System.debug('Jobs processed in last 24 hours: ' + jobs.size());

// Optimize batch sizes based on volume
Integer optimalBatchSize = RouteLogicQueueableProcessor.calculateOptimalBatchSize();
System.debug('Optimal batch size: ' + optimalBatchSize);
```

### Rule Migration
```apex
// Migrate existing routing rules to new format
List</* existing rule records */> existingRules = [/* query existing rules */];
for (/* existing rule */ rule : existingRules) {
    // Convert to new rule format
    Map<String, Object> newRule = new Map<String, Object>{
        'name' => rule.Name,
        'objectType' => 'Case',
        'conditions' => /* convert conditions */,
        'actions' => /* convert actions */
    };
    
    // Store in new configuration system
    RouteLogicConfigurationManager.setConfigurationValue(
        'Rule_' + rule.Id,
        JSON.serialize(newRule),
        false,
        'Production'
    );
}
```

## 🚨 Rollback Procedures

### Emergency Rollback
```bash
# Deactivate all routing rules
sfdx force:apex:execute -f scripts/deactivate-routing.apex -u target-org

# Restore previous configuration
sfdx force:data:tree:import -p backup/RouteLogic_Configuration__mdt-plan.json -u target-org

# Revert to previous package version
sfdx force:package:install --package 04t[previous-version-id] -u target-org
```

### Partial Rollback
```apex
// Disable specific features
RouteLogicConfigurationManager.setConfigurationValue(
    'Feature_Multi_Object_Support',
    'false',
    false,
    'Production'
);

RouteLogicConfigurationManager.setConfigurationValue(
    'Feature_Async_Processing',
    'false',
    false,
    'Production'
);
```

## 📊 Deployment Validation Checklist

### Pre-Deployment
- [ ] Environment requirements validated
- [ ] Backup completed successfully
- [ ] Dependencies checked and resolved
- [ ] Test plan prepared and reviewed
- [ ] Rollback procedures documented

### During Deployment
- [ ] Metadata deployed without errors
- [ ] All tests passing (>75% code coverage)
- [ ] Configuration applied successfully
- [ ] Permission sets assigned correctly
- [ ] Monitoring dashboards accessible

### Post-Deployment
- [ ] Functional testing completed
- [ ] Performance benchmarks met
- [ ] Security validation passed
- [ ] User training completed
- [ ] Documentation updated
- [ ] Support procedures activated

## 🔍 Troubleshooting

### Common Deployment Issues

#### Metadata Deployment Failures
```bash
# Check deployment status
sfdx force:source:deploy:report -i [deployment-id] -u target-org

# Resolve conflicts
sfdx force:source:retrieve -m CustomObject:Routing_Ledger__c -u target-org
```

#### Test Failures
```bash
# Run specific failing tests
sfdx force:apex:test:run -n "FailingTestClass" -u target-org -r human

# Check test coverage
sfdx force:apex:test:report -i [test-run-id] -u target-org
```

#### Permission Issues
```bash
# Verify permission set assignments
sfdx force:user:permset:list -u target-org

# Check object permissions
sfdx force:schema:sobject:describe -s Routing_Ledger__c -u target-org
```

### Performance Issues
```apex
// Monitor job queue depth
Integer queueDepth = [SELECT COUNT() FROM AsyncApexJob WHERE Status IN ('Queued', 'Processing')];
System.debug('Current queue depth: ' + queueDepth);

// Check governor limit usage
System.debug('DML statements used: ' + Limits.getDmlStatements() + '/' + Limits.getLimitDmlStatements());
System.debug('SOQL queries used: ' + Limits.getQueries() + '/' + Limits.getLimitQueries());
```

## 📞 Support Contacts

### Technical Support
- **Email**: support@routelogic.com
- **Phone**: +1 (555) 123-4567
- **Emergency**: +1 (555) 123-4568
- **Hours**: 24/7 for critical issues

### Deployment Support
- **Email**: deployment@routelogic.com
- **Slack**: #routelogic-deployment
- **Hours**: Monday-Friday, 8 AM - 8 PM PST

---

**RouteLogic Enhanced v4.0.0 Deployment Guide**

*Ensuring successful deployment and optimal performance*

