#!/bin/bash

echo "=== Performance Analysis for RouteLogic ==="
echo ""

echo "1. Checking for queries without LIMIT (excluding tests):"
grep -n "\[SELECT" force-app/main/default/classes/*.cls | grep -v "Test\.cls" | grep -v "LIMIT" | grep -v "WHERE Id =" | head -10

echo ""
echo "2. Checking for potential N+1 queries (loops with queries):"
for file in force-app/main/default/classes/*.cls; do
    if grep -q "for.*(" "$file" 2>/dev/null; then
        if grep -A 10 "for.*(" "$file" | grep -q "\[SELECT\|Database\.query" 2>/dev/null; then
            echo "Potential N+1 in: $(basename $file)"
            grep -n -A 10 "for.*(" "$file" | grep -B 2 "\[SELECT\|Database\.query" | head -5
        fi
    fi
done

echo ""
echo "3. Checking for missing bulk patterns:"
grep -l "insert \|update \|delete " force-app/main/default/classes/*.cls | grep -v Test | while read file; do
    if ! grep -q "Database\.\(insert\|update\|delete\|upsert\)" "$file"; then
        echo "Non-bulk DML in: $(basename $file)"
    fi
done

echo ""
echo "4. Large collection operations without chunking:"
grep -n "List<.*> .* = new List<" force-app/main/default/classes/*.cls | grep -v Test | head -10
