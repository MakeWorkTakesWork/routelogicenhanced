#!/bin/bash

# Fix remaining debug statements in multiple files

echo "Fixing remaining debug statements..."

# IntercomAdapter.cls
sed -i.bak 's/System\.debug.*;//g' force-app/main/default/classes/IntercomAdapter.cls

# BulkProcessingOptimizer.cls
sed -i.bak 's/System\.debug.*;//g' force-app/main/default/classes/BulkProcessingOptimizer.cls

# AIRateLimiter.cls
sed -i.bak 's/System\.debug.*;//g' force-app/main/default/classes/AIRateLimiter.cls

# AIQueryOptimizationService.cls
sed -i.bak 's/System\.debug.*;//g' force-app/main/default/classes/AIQueryOptimizationService.cls

# AIWebhookResponseHandler.cls
sed -i.bak 's/System\.debug.*;//g' force-app/main/default/classes/AIWebhookResponseHandler.cls

# AIWebhookService.cls
sed -i.bak 's/System\.debug.*;//g' force-app/main/default/classes/AIWebhookService.cls

# ErrorLogService.cls - Special handling since it's a logging service
sed -i.bak 's/System\.debug(LoggingLevel\.ERROR/\/\/ ERROR:/g' force-app/main/default/classes/ErrorLogService.cls
sed -i.bak 's/System\.debug(/\/\/ Debug: /g' force-app/main/default/classes/ErrorLogService.cls

# RateLimitHandler.cls
sed -i.bak 's/System\.debug.*;//g' force-app/main/default/classes/RateLimitHandler.cls

# RateLimitService.cls
sed -i.bak 's/System\.debug.*;//g' force-app/main/default/classes/RateLimitService.cls

# KeyVersionManager.cls
sed -i.bak 's/System\.debug.*;//g' force-app/main/default/classes/KeyVersionManager.cls

# LicenseManager.cls
sed -i.bak 's/System\.debug.*;//g' force-app/main/default/classes/LicenseManager.cls

# LogRetentionScheduler.cls
sed -i.bak 's/System\.debug.*;//g' force-app/main/default/classes/LogRetentionScheduler.cls

# OrphanedCaseDetectionService.cls
sed -i.bak 's/System\.debug.*;//g' force-app/main/default/classes/OrphanedCaseDetectionService.cls

# PostInstallScript.cls
sed -i.bak 's/System\.debug.*;//g' force-app/main/default/classes/PostInstallScript.cls

# IntercomSecurityProvider.cls
sed -i.bak 's/System\.debug.*;//g' force-app/main/default/classes/IntercomSecurityProvider.cls

# BaseAIService.cls
sed -i.bak 's/System\.debug.*;//g' force-app/main/default/classes/BaseAIService.cls

# AIMobilePerformanceService.cls
sed -i.bak 's/System\.debug.*;//g' force-app/main/default/classes/AIMobilePerformanceService.cls

echo "Debug statement removal complete!"

# Count remaining
echo "Counting remaining debug statements..."
grep -c "System\.debug" force-app/main/default/classes/*.cls | grep -v ":0" | awk -F: '{sum+=$2} END {print "Total debug statements remaining: " sum}'