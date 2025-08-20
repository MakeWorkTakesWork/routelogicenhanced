#!/bin/bash

echo "Removing final debug statements..."

# IntercomAdapter.cls - line 415
sed -i.bak '415,416d' force-app/main/default/classes/IntercomAdapter.cls

# IntercomSecurityProvider.cls - line 310
sed -i.bak '310,311d' force-app/main/default/classes/IntercomSecurityProvider.cls

# RateLimitHandler.cls - line 159
sed -i.bak '159,161d' force-app/main/default/classes/RateLimitHandler.cls

# RouteLogicJobTracker.cls - lines 313, 324, 347
sed -i.bak '313s/.*/            ErrorLogService.logError('\''RouteLogicJobTracker'\'', '\''publishJobStatusEvent'\'', '\''Failed to publish job status event: '\'' + e.getMessage(), e.getStackTraceString());/' force-app/main/default/classes/RouteLogicJobTracker.cls
sed -i.bak '324d' force-app/main/default/classes/RouteLogicJobTracker.cls
sed -i.bak '347d' force-app/main/default/classes/RouteLogicJobTracker.cls

# RouteLogicQueueableProcessor.cls - lines 263, 362, 397
sed -i.bak '263s/.*/                    ErrorLogService.logError('\''RouteLogicQueueableProcessor'\'', '\''executeProviderHandoff'\'', '\''Handoff execution failed: '\'' + e.getMessage(), e.getStackTraceString());/' force-app/main/default/classes/RouteLogicQueueableProcessor.cls
sed -i.bak '362s/.*/            ErrorLogService.logError('\''RouteLogicQueueableProcessor'\'', '\''executeProviderHandoff'\'', '\''Provider handoff failed: '\'' + e.getMessage(), e.getStackTraceString());/' force-app/main/default/classes/RouteLogicQueueableProcessor.cls
sed -i.bak '397s/.*/        ErrorLogService.logError('\''RouteLogicQueueableProcessor'\'', '\''logError'\'', errorMessage, e.getStackTraceString());/' force-app/main/default/classes/RouteLogicQueueableProcessor.cls

# SecurityAuditService.cls - lines 81, 82, 252, 270
sed -i.bak '81,82s/.*/            ErrorLogService.logError('\''SecurityAuditService'\'', '\''logEvent'\'', '\''Security audit logging failed: '\'' + e.getMessage() + '\''. Event: '\'' + JSON.serialize(details), e.getStackTraceString());/' force-app/main/default/classes/SecurityAuditService.cls
sed -i.bak '252s/.*/            ErrorLogService.logError('\''SecurityAuditService'\'', '\''publishSecurityEvent'\'', '\''Failed to publish security event: '\'' + e.getMessage(), e.getStackTraceString());/' force-app/main/default/classes/SecurityAuditService.cls
sed -i.bak '270s/.*/            ErrorLogService.logError('\''SecurityAuditService'\'', '\''logToCustomObject'\'', '\''Failed to insert audit log: '\'' + e.getMessage(), e.getStackTraceString());/' force-app/main/default/classes/SecurityAuditService.cls

# SecurityKeyManager.cls - lines 384, 449, 514 (these are permission checks, just remove)
sed -i.bak '384d' force-app/main/default/classes/SecurityKeyManager.cls
sed -i.bak '449d' force-app/main/default/classes/SecurityKeyManager.cls  
sed -i.bak '514d' force-app/main/default/classes/SecurityKeyManager.cls

# UninstallScript.cls - line 30 (comment indicates can't use ErrorLogService, so just remove)
sed -i.bak '30d' force-app/main/default/classes/UninstallScript.cls

# RouteLogicSecurityUtils.cls - just remove debug statements
sed -i.bak '/System\.debug/d' force-app/main/default/classes/RouteLogicSecurityUtils.cls

echo "Debug removal complete!"
