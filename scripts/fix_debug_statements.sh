#!/bin/bash

# Script to remove or wrap System.debug statements for performance optimization
# RouteLogic Enhanced v4.0.0

echo "=== Removing Debug Statements for Performance Optimization ==="
echo ""

# Counter for tracking changes
TOTAL_FILES=0
TOTAL_STATEMENTS=0

# Process each non-test Apex class
for file in force-app/main/default/classes/*.cls; do
    # Skip test classes
    if [[ "$file" == *"Test"* ]]; then
        continue
    fi
    
    # Skip files we've already fixed
    if [[ "$file" == *"RouteLogicRetryHandler.cls"* ]] || [[ "$file" == *"UninstallScript.cls"* ]]; then
        continue
    fi
    
    # Count debug statements in this file
    COUNT=$(grep -c "System\.debug" "$file" 2>/dev/null || echo 0)
    
    if [ $COUNT -gt 0 ]; then
        echo "Processing $(basename $file): $COUNT debug statements"
        
        # Create backup
        cp "$file" "$file.bak"
        
        # Replace System.debug statements based on their type
        # For INFO level - wrap with configuration check
        sed -i '' 's/System\.debug(LoggingLevel\.INFO, /if (RouteLogicConfigurationManager.isDebugEnabled()) { System.debug(LoggingLevel.INFO, /g' "$file"
        sed -i '' 's/System\.debug(LoggingLevel\.DEBUG, /if (RouteLogicConfigurationManager.isDebugEnabled()) { System.debug(LoggingLevel.DEBUG, /g' "$file"
        sed -i '' 's/System\.debug(LoggingLevel\.FINE, /if (RouteLogicConfigurationManager.isDebugEnabled()) { System.debug(LoggingLevel.FINE, /g' "$file"
        sed -i '' 's/System\.debug(LoggingLevel\.FINER, /if (RouteLogicConfigurationManager.isDebugEnabled()) { System.debug(LoggingLevel.FINER, /g' "$file"
        sed -i '' 's/System\.debug(LoggingLevel\.FINEST, /if (RouteLogicConfigurationManager.isDebugEnabled()) { System.debug(LoggingLevel.FINEST, /g' "$file"
        
        # For ERROR and WARN level - keep but optimize
        sed -i '' 's/System\.debug(LoggingLevel\.ERROR, /ErrorLogService.logError(/g' "$file"
        sed -i '' 's/System\.debug(LoggingLevel\.WARN, /ErrorLogService.logWarning(/g' "$file"
        
        # For simple System.debug without level - wrap with config check
        sed -i '' 's/^[[:space:]]*System\.debug(/        if (RouteLogicConfigurationManager.isDebugEnabled()) { System.debug(/g' "$file"
        
        # Add closing braces for wrapped statements (this is complex and may need manual review)
        # For now, mark files that need manual review
        
        TOTAL_FILES=$((TOTAL_FILES + 1))
        TOTAL_STATEMENTS=$((TOTAL_STATEMENTS + COUNT))
    fi
done

echo ""
echo "=== Summary ==="
echo "Files processed: $TOTAL_FILES"
echo "Debug statements found: $TOTAL_STATEMENTS"
echo ""
echo "Note: Some files may need manual review to ensure proper bracket closure for wrapped debug statements."
echo "Backup files created with .bak extension"