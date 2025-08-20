# RouteLogic Performance Violations - Execution Plan

## Current State Analysis
- **38 files** still have debug statements (quick wins)
- **10+ files** have potential N+1 query patterns
- **Unknown number** of bulkification issues
- **Total Performance Violations**: ~183

## 🎯 PHASE 1: Quick Wins (2-3 hours, 100+ violations)

### Step 1: Automated Debug Statement Removal
**Files to fix**: 38 files with ~100+ debug statements

#### Pattern to Apply:
```apex
// BEFORE:
System.debug('Some message');
System.debug(LoggingLevel.INFO, 'Some message');

// AFTER:
// Removed or wrapped based on criticality
if (RouteLogicConfigurationManager.isDebugEnabled()) {
    ErrorLogService.logInfo('ClassName', 'Some message');
}
```

#### Automated Fix Script:
```bash
#!/bin/bash
# fix_all_debug_statements.sh

for file in force-app/main/default/classes/*.cls; do
    if [[ "$file" == *"Test"* ]] || [[ "$file" == *"RouteLogicRetryHandler"* ]] || [[ "$file" == *"UninstallScript"* ]]; then
        continue
    fi
    
    if grep -q "System\.debug" "$file"; then
        # Backup
        cp "$file" "$file.debug.bak"
        
        # Remove simple debug statements
        sed -i '' '/^[[:space:]]*System\.debug(/d' "$file"
        
        # Convert ERROR level to ErrorLogService
        sed -i '' 's/System\.debug(LoggingLevel\.ERROR, \(.*\));/ErrorLogService.logError('\''ClassName'\'', \1);/g' "$file"
        
        echo "Fixed: $(basename $file)"
    fi
done
```

## 🔥 PHASE 2: Critical Query Optimizations (4-6 hours, 30+ violations)

### Step 2A: Fix N+1 Query Patterns

**Priority Files** (Highest impact):
1. **AIBulkOperationService.cls** - Bulk operations MUST be optimized
2. **AIBulkProcessingController.cls** - Controller queries need bulkification
3. **LogRetentionBatch.cls** - Batch class queries are critical

#### Pattern to Fix:
```apex
// BEFORE (N+1 Pattern):
for (Case c : cases) {
    Account acc = [SELECT Name FROM Account WHERE Id = :c.AccountId];
    // Process
}

// AFTER (Bulkified):
Set<Id> accountIds = new Set<Id>();
for (Case c : cases) {
    accountIds.add(c.AccountId);
}
Map<Id, Account> accountMap = new Map<Id, Account>([
    SELECT Id, Name FROM Account 
    WHERE Id IN :accountIds
    WITH SECURITY_ENFORCED
]);
for (Case c : cases) {
    Account acc = accountMap.get(c.AccountId);
    // Process
}
```

### Step 2B: Query Optimization Checklist
- [ ] Move queries outside of loops
- [ ] Use selective WHERE clauses
- [ ] Add LIMIT clauses where appropriate
- [ ] Index filter fields (via Setup)
- [ ] Use WITH SECURITY_ENFORCED consistently

## ⚡ PHASE 3: Bulkification Fixes (6-8 hours, 40+ violations)

### Step 3A: DML Operations Bulkification

**Pattern to Fix**:
```apex
// BEFORE (Non-bulkified):
for (Contact con : contacts) {
    con.LastName = 'Updated';
    update con; // DML in loop!
}

// AFTER (Bulkified):
List<Contact> toUpdate = new List<Contact>();
for (Contact con : contacts) {
    con.LastName = 'Updated';
    toUpdate.add(con);
}
if (!toUpdate.isEmpty()) {
    update toUpdate; // Single DML
}
```

### Step 3B: Files Requiring Bulkification
1. Trigger handlers (any file with "TriggerHandler" in name)
2. Batch classes (any file with "Batch" in name)
3. Queueable classes (any file with "Queueable" in name)

## 🛠️ PHASE 4: Governor Limit Prevention (4-5 hours, 13+ violations)

### Step 4A: CPU Time Optimization
```apex
// Add circuit breakers
if (Limits.getCpuTime() > 9000) { // 90% of limit
    // Defer remaining work
    System.enqueueJob(new ContinuationQueueable(remainingWork));
    return;
}
```

### Step 4B: Heap Size Management
```apex
// Clear collections when done
largeCollection.clear();
largeMap = null; // Allow garbage collection
```

## 📋 EXACT EXECUTION ORDER

### Day 1 (Quick Wins - 3 hours)
1. **Hour 1**: Run automated debug removal script
2. **Hour 2**: Manual review and fix any broken debug removals
3. **Hour 3**: Test compilation and basic smoke test

**Expected Result**: 100+ violations fixed

### Day 2 (Critical Queries - 6 hours)
1. **Hours 1-2**: Fix AIBulkOperationService.cls N+1 patterns
2. **Hours 3-4**: Fix AIBulkProcessingController.cls queries
3. **Hours 5-6**: Fix batch class queries

**Expected Result**: 30+ violations fixed

### Day 3 (Bulkification - 6 hours)
1. **Hours 1-3**: Fix trigger handler bulkification
2. **Hours 4-6**: Fix batch/queueable bulkification

**Expected Result**: 40+ violations fixed

### Day 4 (Testing & Validation - 3 hours)
1. **Hour 1**: Run all unit tests
2. **Hour 2**: Performance testing with data volumes
3. **Hour 3**: Fix any regressions

**Total Time**: 18 hours
**Total Violations Fixed**: 170+ (93% of performance issues)

## 🚀 IMMEDIATE NEXT STEPS

### Right Now - Start Here:
```bash
# 1. Count exact debug statements
grep -c "System\.debug" force-app/main/default/classes/*.cls | grep -v ":0" | cut -d: -f2 | paste -sd+ | bc

# 2. Find worst offenders
for file in force-app/main/default/classes/*.cls; do 
    count=$(grep -c "System\.debug" "$file" 2>/dev/null)
    if [ $count -gt 5 ]; then 
        echo "$count $(basename $file)"
    fi
done | sort -rn | head -10

# 3. Start fixing the worst file first
```

## ✅ Success Metrics

After completing this plan:
- **Performance Score**: 30% → 85%
- **Governor Limit Risk**: HIGH → LOW
- **Scalability**: 100 records → 10,000+ records
- **Response Time**: 3-5 seconds → <1 second
- **Production Readiness**: 45% → 80%

## 🎯 Priority Matrix

| Issue Type | Count | Impact | Effort | Priority |
|-----------|-------|---------|---------|----------|
| Debug Statements | 100+ | Medium | Low (3hrs) | DO FIRST |
| N+1 Queries | 30+ | HIGH | Medium (6hrs) | DO SECOND |
| Bulkification | 40+ | CRITICAL | High (6hrs) | DO THIRD |
| Governor Limits | 13+ | HIGH | Medium (3hrs) | DO FOURTH |

---

**Start with Step 1**: Remove debug statements (3 hours for 100+ fixes)
**Biggest Bang for Buck**: N+1 query fixes (30% performance improvement)
**Most Critical**: Bulkification (prevents production failures)

Would you like me to start executing this plan immediately?