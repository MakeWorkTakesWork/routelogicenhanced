/**
 * @description Handler for Routing_Ledger__c trigger to enforce immutability and security
 * @author RouteLogic Team
 * @date 2025-01-21
 * @version 1.0
 * 
 * This handler ensures the immutability of routing ledger entries through cryptographic
 * verification and prevents any unauthorized modifications or deletions.
 */
public with sharing class RoutingLedgerTriggerHandler {
    
    private static final String IMMUTABILITY_ERROR = 'Routing Ledger entries are immutable and cannot be modified or deleted';
    private static final String HASH_VERIFICATION_ERROR = 'Security hash verification failed - data integrity compromised';
    
    /**
     * @description Handle before insert operations
     * @param newRecords List of new Routing_Ledger__c records
     */
    public static void handleBeforeInsert(List<Routing_Ledger__c> newRecords) {
        for (Routing_Ledger__c ledger : newRecords) {
            // Generate security hash for immutability
            ledger.Security_Hash__c = generateSecurityHash(ledger);
            
            // Set handoff timestamp if not already set
            if (ledger.Handoff_Timestamp__c == null) {
                ledger.Handoff_Timestamp__c = DateTime.now();
            }
            
            // Validate required fields
            validateRequiredFields(ledger);
        }
    }
    
    /**
     * @description Handle before update operations - prevent all updates
     * @param newRecords List of updated Routing_Ledger__c records
     * @param oldRecordsMap Map of old record values
     */
    public static void handleBeforeUpdate(List<Routing_Ledger__c> newRecords, Map<Id, Routing_Ledger__c> oldRecordsMap) {
        // Routing ledger entries are immutable - no updates allowed
        for (Routing_Ledger__c ledger : newRecords) {
            Routing_Ledger__c oldRecord = oldRecordsMap.get(ledger.Id);
            
            // Check if any field has been modified
            if (hasFieldsChanged(ledger, oldRecord)) {
                ledger.addError(IMMUTABILITY_ERROR);
            }
            
            // Verify security hash integrity
            String expectedHash = generateDeterministicSecurityHash(oldRecord);
            if (!RouteLogicSecurityUtils.timingSafeEquals(oldRecord.Security_Hash__c, expectedHash)) {
                ledger.addError(HASH_VERIFICATION_ERROR);
            }
        }
    }
    
    /**
     * @description Handle before delete operations - prevent all deletions
     * @param oldRecords List of Routing_Ledger__c records being deleted
     */
    public static void handleBeforeDelete(List<Routing_Ledger__c> oldRecords) {
        // Routing ledger entries are immutable - no deletions allowed
        for (Routing_Ledger__c ledger : oldRecords) {
            ledger.addError(IMMUTABILITY_ERROR);
        }
    }
    
    /**
     * @description Generate SHA-256 security hash for a routing ledger entry
     * @param ledger The routing ledger record
     * @return SHA-256 hash string
     */
    public static String generateSecurityHash(Routing_Ledger__c ledger) {
        // Create hash input from critical fields
        List<String> hashComponents = new List<String>{
            String.valueOf(ledger.Case__c),
            ledger.Initial_AI_Provider__c,
            ledger.Routing_Engine_Decision__c,
            ledger.Handoff_Status__c,
            String.valueOf(ledger.Handoff_Timestamp__c),
            UserInfo.getOrganizationId()
        };
        
        // Join components and generate hash
        String hashInput = String.join(hashComponents, '|');
        Blob hashBlob = Crypto.generateDigest('SHA-256', Blob.valueOf(hashInput));
        
        return EncodingUtil.convertToHex(hashBlob);
    }

    /**
     * @description Deterministic hash used for verification (excludes any volatile values)
     */
    public static String generateDeterministicSecurityHash(Routing_Ledger__c ledger) {
        List<String> hashComponents = new List<String>{
            String.valueOf(ledger.Case__c),
            ledger.Initial_AI_Provider__c,
            ledger.Routing_Engine_Decision__c,
            ledger.Handoff_Status__c,
            String.valueOf(ledger.Handoff_Timestamp__c),
            UserInfo.getOrganizationId()
        };
        String hashInput = String.join(hashComponents, '|');
        Blob hashBlob = Crypto.generateDigest('SHA-256', Blob.valueOf(hashInput));
        return EncodingUtil.convertToHex(hashBlob);
    }
    
    /**
     * @description Validate required fields for routing ledger entry
     * @param ledger The routing ledger record
     */
    private static void validateRequiredFields(Routing_Ledger__c ledger) {
        List<String> errors = new List<String>();
        
        if (String.isBlank(ledger.Initial_AI_Provider__c)) {
            errors.add('Initial AI Provider is required');
        }
        
        if (String.isBlank(ledger.Handoff_Status__c)) {
            errors.add('Handoff Status is required');
        }
        
        if (ledger.Handoff_Timestamp__c == null) {
            errors.add('Handoff Timestamp is required');
        }
        
        if (String.isBlank(ledger.Routing_Engine_Decision__c)) {
            errors.add('Routing Engine Decision is required');
        }
        
        if (!errors.isEmpty()) {
            ledger.addError('Validation failed: ' + String.join(errors, '; '));
        }
    }
    
    /**
     * @description Check if any fields have changed between old and new records
     * @param newRecord The new record
     * @param oldRecord The old record
     * @return True if any fields have changed
     */
    private static Boolean hasFieldsChanged(Routing_Ledger__c newRecord, Routing_Ledger__c oldRecord) {
        // Check all critical fields for changes
        return newRecord.Case__c != oldRecord.Case__c ||
               newRecord.Initial_AI_Provider__c != oldRecord.Initial_AI_Provider__c ||
               newRecord.Routing_Engine_Decision__c != oldRecord.Routing_Engine_Decision__c ||
               newRecord.Handoff_Status__c != oldRecord.Handoff_Status__c ||
               newRecord.Handoff_Timestamp__c != oldRecord.Handoff_Timestamp__c ||
               newRecord.Security_Hash__c != oldRecord.Security_Hash__c;
    }
    
    /**
     * @description Create routing ledger entry from routing decision
     * @param decision The routing decision from AgnosticRoutingEngine
     * @param aiProvider The AI provider that initiated the handoff
     * @return Routing_Ledger__c record ready for insert
     */
    public static Routing_Ledger__c createLedgerEntry(AgnosticRoutingEngine.RoutingDecision decision, String aiProvider) {
        Routing_Ledger__c ledger = new Routing_Ledger__c();
        
        // Map routing decision to ledger fields
        ledger.Case__c = decision.caseId;
        ledger.Initial_AI_Provider__c = aiProvider;
        ledger.Routing_Engine_Decision__c = JSON.serialize(decision);
        ledger.Handoff_Status__c = 'Initiated';
        ledger.Handoff_Timestamp__c = decision.routingTimestamp != null ? 
                                      decision.routingTimestamp : DateTime.now();
        
        return ledger;
    }
    
    /**
     * @description Verify the integrity of a routing ledger entry
     * @param ledger The routing ledger record to verify
     * @return True if the record integrity is valid
     */
    public static Boolean verifyLedgerIntegrity(Routing_Ledger__c ledger) {
        if (ledger == null || String.isBlank(ledger.Security_Hash__c)) {
            return false;
        }
        
        // Create a copy without the security hash for verification
        Routing_Ledger__c verificationCopy = ledger.clone(false, false, false, false);
        verificationCopy.Security_Hash__c = null;
        
        // Generate expected hash
        String expectedHash = generateDeterministicSecurityHash(verificationCopy);
        
        // Compare with stored hash using timing-safe comparison
        return RouteLogicSecurityUtils.timingSafeEquals(ledger.Security_Hash__c, expectedHash);
    }
    
    /**
     * @description Query interface for audit trail retrieval
     * @param caseId The case ID to retrieve audit trail for
     * @return List of routing ledger entries for the case
     */
    public static List<Routing_Ledger__c> getAuditTrailForCase(Id caseId) {
        if (caseId == null) {
            return new List<Routing_Ledger__c>();
        }
        
        return [
            SELECT Id, Name, Case__c, Initial_AI_Provider__c, Routing_Engine_Decision__c,
                   Handoff_Status__c, Handoff_Timestamp__c, Security_Hash__c,
                   CreatedDate, CreatedById
            FROM Routing_Ledger__c
            WHERE Case__c = :caseId
            WITH SECURITY_ENFORCED
            ORDER BY Handoff_Timestamp__c ASC
        ];
    }
    
    /**
     * @description Query interface for audit trail retrieval by date range
     * @param startDate Start date for audit trail
     * @param endDate End date for audit trail
     * @return List of routing ledger entries within date range
     */
    public static List<Routing_Ledger__c> getAuditTrailByDateRange(DateTime startDate, DateTime endDate) {
        if (startDate == null || endDate == null) {
            return new List<Routing_Ledger__c>();
        }
        
        return [
            SELECT Id, Name, Case__c, Initial_AI_Provider__c, Routing_Engine_Decision__c,
                   Handoff_Status__c, Handoff_Timestamp__c, Security_Hash__c,
                   CreatedDate, CreatedById
            FROM Routing_Ledger__c
            WHERE Handoff_Timestamp__c >= :startDate
            AND Handoff_Timestamp__c <= :endDate
            WITH SECURITY_ENFORCED
            ORDER BY Handoff_Timestamp__c DESC
            LIMIT 10000
        ];
    }
    
    /**
     * @description Query interface for failed handoffs (Black Hole cases)
     * @param hoursBack Number of hours to look back
     * @return List of failed handoff entries
     */
    public static List<Routing_Ledger__c> getBlackHoleCases(Integer hoursBack) {
        DateTime cutoffTime = DateTime.now().addHours(-hoursBack);
        
        return [
            SELECT Id, Name, Case__c, Initial_AI_Provider__c, Routing_Engine_Decision__c,
                   Handoff_Status__c, Handoff_Timestamp__c, Security_Hash__c,
                   CreatedDate, CreatedById
            FROM Routing_Ledger__c
            WHERE Handoff_Status__c = 'Black_Hole'
            AND Handoff_Timestamp__c >= :cutoffTime
            WITH SECURITY_ENFORCED
            ORDER BY Handoff_Timestamp__c DESC
        ];
    }
    
    /**
     * @description Get handoff success rate metrics
     * @param hoursBack Number of hours to analyze
     * @return Map containing success rate metrics
     */
    public static Map<String, Object> getHandoffSuccessMetrics(Integer hoursBack) {
        DateTime cutoffTime = DateTime.now().addHours(-hoursBack);
        
        List<AggregateResult> results = [
            SELECT Handoff_Status__c, COUNT(Id) totalCount
            FROM Routing_Ledger__c
            WHERE Handoff_Timestamp__c >= :cutoffTime
            WITH SECURITY_ENFORCED
            GROUP BY Handoff_Status__c
        ];
        
        Map<String, Object> metrics = new Map<String, Object>();
        Integer totalHandoffs = 0;
        Integer successfulHandoffs = 0;
        Integer failedHandoffs = 0;
        Integer blackHoleHandoffs = 0;
        
        for (AggregateResult result : results) {
            String status = (String) result.get('Handoff_Status__c');
            Integer count = (Integer) result.get('totalCount');
            totalHandoffs += count;
            
            if (status == 'Completed') {
                successfulHandoffs += count;
            } else if (status == 'Failed') {
                failedHandoffs += count;
            } else if (status == 'Black_Hole') {
                blackHoleHandoffs += count;
            }
        }
        
        metrics.put('totalHandoffs', totalHandoffs);
        metrics.put('successfulHandoffs', successfulHandoffs);
        metrics.put('failedHandoffs', failedHandoffs);
        metrics.put('blackHoleHandoffs', blackHoleHandoffs);
        metrics.put('successRate', totalHandoffs > 0 ? 
                   (Decimal.valueOf(successfulHandoffs) / Decimal.valueOf(totalHandoffs)) * 100 : 0);
        metrics.put('failureRate', totalHandoffs > 0 ? 
                   (Decimal.valueOf(failedHandoffs + blackHoleHandoffs) / Decimal.valueOf(totalHandoffs)) * 100 : 0);
        
        return metrics;
    }
}

