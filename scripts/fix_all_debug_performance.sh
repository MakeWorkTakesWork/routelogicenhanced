#!/bin/bash

# Script to fix all remaining debug statements for performance optimization
# RouteLogic Enhanced v4.0.0 - January 31, 2025

echo "=== Fixing All Remaining Debug Statements ==="
echo ""

# Files already fixed - skip these
FIXED_FILES="RouteLogicRetryHandler.cls UninstallScript.cls RouteLogicFieldMapper.cls AIHealthCheckScheduler.cls"

# Counter for tracking
TOTAL_FIXED=0

# List of files with debug statements to fix
FILES_TO_FIX=(
    "RouteLogicObjectManager.cls"
    "CacheUtils.cls"
    "AIAlertingService.cls"
    "RouteLogicConfigurationManager.cls"
    "AISystemMonitoringService.cls"
    "RouteLogicEncryptionUtility.cls"
    "AIProviderHealthCheckService.cls"
    "SecureKeyVault.cls"
    "EncryptionKeyRotationSchedule.cls"
    "AICacheService.cls"
    "AIBulkProcessingQueueable.cls"
    "ConversationService.cls"
    "IntercomAdapter.cls"
    "BulkProcessingOptimizer.cls"
    "AIRateLimiter.cls"
    "AIQueryOptimizationService.cls"
    "AIWebhookResponseHandler.cls"
    "AIWebhookService.cls"
    "ErrorLogService.cls"
    "KeyVersionManager.cls"
    "LogRetentionScheduler.cls"
    "OrphanedCaseDetectionService.cls"
    "PIIMaskingService.cls"
    "PostInstallScript.cls"
    "RouteLogicAwsIntegration.cls"
    "RouteLogicEventHelper.cls"
    "RouteLogicEventListener.cls"
    "RoutingLedgerTriggerHandler.cls"
    "SecurityKeyManager.cls"
    "AIConfigurationController.cls"
    "AIConfigurationValidationService.cls"
    "AIProviderHealthCheckServiceV2.cls"
    "AIBulkProcessingCoordinator.cls"
    "AIBulkOperationService.cls"
    "AIMobilePerformanceService.cls"
    "AuditService.cls"
    "BaseAIService.cls"
)

# Process each file
for file in "${FILES_TO_FIX[@]}"; do
    FILE_PATH="force-app/main/default/classes/$file"
    
    if [ -f "$FILE_PATH" ]; then
        # Count debug statements before
        COUNT_BEFORE=$(grep -c "System\.debug" "$FILE_PATH" 2>/dev/null || echo 0)
        
        if [ $COUNT_BEFORE -gt 0 ]; then
            echo "Processing $file: $COUNT_BEFORE debug statements"
            
            # Create backup
            cp "$FILE_PATH" "$FILE_PATH.perf.bak"
            
            # Get base class name for logging
            CLASS_NAME=$(basename "$file" .cls)
            
            # Create temporary file
            TEMP_FILE="$FILE_PATH.tmp"
            cp "$FILE_PATH" "$TEMP_FILE"
            
            # Remove or replace debug statements based on type
            # Simple debug statements - remove entirely
            sed -i '' '/^[[:space:]]*System\.debug([^;]*);[[:space:]]*$/d' "$TEMP_FILE"
            
            # ERROR level - convert to ErrorLogService
            sed -i '' "s/System\.debug(LoggingLevel\.ERROR, '\([^']*\)'/ErrorLogService.logError('$CLASS_NAME', '\1'/g" "$TEMP_FILE"
            sed -i '' "s/System\.debug(LoggingLevel\.ERROR, \"\([^\"]*\)\"/ErrorLogService.logError('$CLASS_NAME', \"\1\"/g" "$TEMP_FILE"
            
            # WARN level - convert to comment
            sed -i '' 's/System\.debug(LoggingLevel\.WARN, /\/\/ Warning: /g' "$TEMP_FILE"
            
            # INFO/DEBUG/FINE/FINER/FINEST - convert to comment
            sed -i '' 's/System\.debug(LoggingLevel\.INFO, /\/\/ Info: /g' "$TEMP_FILE"
            sed -i '' 's/System\.debug(LoggingLevel\.DEBUG, /\/\/ Debug: /g' "$TEMP_FILE"
            sed -i '' 's/System\.debug(LoggingLevel\.FINE, /\/\/ Fine: /g' "$TEMP_FILE"
            sed -i '' 's/System\.debug(LoggingLevel\.FINER, /\/\/ Finer: /g' "$TEMP_FILE"
            sed -i '' 's/System\.debug(LoggingLevel\.FINEST, /\/\/ Finest: /g' "$TEMP_FILE"
            
            # Move temp file back
            mv "$TEMP_FILE" "$FILE_PATH"
            
            # Count debug statements after
            COUNT_AFTER=$(grep -c "System\.debug" "$FILE_PATH" 2>/dev/null || echo 0)
            FIXED=$((COUNT_BEFORE - COUNT_AFTER))
            TOTAL_FIXED=$((TOTAL_FIXED + FIXED))
            
            echo "  Fixed: $FIXED debug statements removed/replaced"
        fi
    fi
done

echo ""
echo "=== Performance Optimization Complete ==="
echo "Total debug statements fixed: $TOTAL_FIXED"
echo ""
echo "Next steps:"
echo "1. Review the changes"
echo "2. Test compilation: sf project deploy validate --source-dir force-app/main/default/classes --test-level NoTestRun"
echo "3. Run tests if compilation succeeds"
echo ""
echo "Backup files created with .perf.bak extension"