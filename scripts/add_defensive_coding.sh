#!/bin/bash

echo "Adding defensive coding patterns to service classes..."

# Files to enhance with defensive coding
FILES=(
    "AIAlertingService.cls"
    "AICacheService.cls"
    "AIProviderHealthCheckService.cls"
    "ConversationService.cls"
    "SecurityAuditService.cls"
)

for file in "${FILES[@]}"; do
    echo "Checking $file for defensive coding opportunities..."
    
    # Count existing null checks
    null_checks=$(grep -c "!= null\|== null" "force-app/main/default/classes/$file" 2>/dev/null || echo 0)
    
    # Count method parameters that might need validation
    params=$(grep -c "@param" "force-app/main/default/classes/$file" 2>/dev/null || echo 0)
    
    echo "  - Existing null checks: $null_checks"
    echo "  - Method parameters: $params"
    
    if [ "$null_checks" -lt "$params" ]; then
        echo "  ⚠️ May need additional defensive coding"
    fi
done

echo ""
echo "Key patterns to implement:"
echo "1. Null checks for all method parameters"
echo "2. Collection initialization before use"
echo "3. Try-catch blocks for external calls"
echo "4. Input validation for user-provided data"
echo "5. Defensive copying of mutable objects"
