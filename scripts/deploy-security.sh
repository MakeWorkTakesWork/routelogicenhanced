#!/bin/bash
# RouteLogic Enhanced v4.0.0 - Security Deployment Script
# This script deploys security components to a Salesforce sandbox

echo "========================================="
echo "RouteLogic Security Deployment Script"
echo "========================================="

# Check if org alias is provided
if [ -z "$1" ]; then
    echo "Error: Please provide your sandbox org alias"
    echo "Usage: ./deploy-security.sh <org-alias>"
    exit 1
fi

ORG_ALIAS=$1
echo "Deploying to org: $ORG_ALIAS"

# Step 1: Deploy metadata components
echo ""
echo "Step 1: Deploying metadata components..."
sfdx force:source:deploy -p force-app/main/default/objects/AI_Secure_Key__mdt,force-app/main/default/objects/AI_Security_Settings__c,force-app/main/default/objects/AI_Encryption_Settings__c.object-meta.xml -u $ORG_ALIAS

# Step 2: Deploy cache partition
echo ""
echo "Step 2: Deploying Platform Cache partition..."
sfdx force:source:deploy -p force-app/main/default/cachePartitions -u $ORG_ALIAS

# Step 3: Deploy permissions
echo ""
echo "Step 3: Deploying permissions..."
sfdx force:source:deploy -p force-app/main/default/customPermissions,force-app/main/default/permissionsets -u $ORG_ALIAS

# Step 4: Deploy security classes
echo ""
echo "Step 4: Deploying security classes..."
sfdx force:source:deploy -p force-app/main/default/classes/RouteLogicEncryptionUtility.cls,force-app/main/default/classes/SecureKeyVault.cls,force-app/main/default/classes/AdaSecurityProvider.cls,force-app/main/default/classes/RouteLogicConfigurationManager.cls -u $ORG_ALIAS

# Step 5: Deploy Named Credentials
echo ""
echo "Step 5: Deploying Named Credentials..."
sfdx force:source:deploy -p force-app/main/default/namedCredentials -u $ORG_ALIAS

echo ""
echo "========================================="
echo "Deployment complete!"
echo "Next steps:"
echo "1. Run ./test-security.sh $ORG_ALIAS"
echo "2. Check deployment status in Setup → Deployment Status"
echo "========================================="