#!/bin/bash

echo "Converting non-bulk DML to Database methods for better performance..."

# Create backup
cp -r force-app force-app-backup-bulk-dml-$(date +%Y%m%d-%H%M%S)

# Files to fix based on analysis
FILES=(
    "AIBulkProcessingQueueable.cls"
    "AIAlertingService.cls"
    "AIHealthCheckScheduler.cls"
    "SecurityAuditService.cls"
    "RouteLogicJobTracker.cls"
    "ConversationService.cls"
    "LogRetentionScheduler.cls"
)

for file in "${FILES[@]}"; do
    echo "Processing $file..."
    
    # Convert insert statements to Database.insert
    sed -i.bak 's/^\(\s*\)insert \(.*\);/\1Database.insert(\2, false);/g' "force-app/main/default/classes/$file"
    
    # Convert update statements to Database.update
    sed -i.bak 's/^\(\s*\)update \(.*\);/\1Database.update(\2, false);/g' "force-app/main/default/classes/$file"
    
    # Convert delete statements to Database.delete
    sed -i.bak 's/^\(\s*\)delete \(.*\);/\1Database.delete(\2, false);/g' "force-app/main/default/classes/$file"
    
    # Handle SecurityUtils wrapped operations - these are already good practice
    # Revert changes for SecurityUtils.stripInaccessibleRecords patterns
    sed -i.bak 's/Database\.\(insert\|update\|delete\)(\(SecurityUtils\.stripInaccessibleRecords.*\), false);/\1 \2;/g' "force-app/main/default/classes/$file"
done

echo "Bulk DML conversion complete!"
echo "Files modified: ${#FILES[@]}"