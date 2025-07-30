/**
 * @description Handler for AI_Case_Request__e platform events
 * @author RouteLogic Team
 * @date 2025-01-17
 */
public class AI_Case_Request_EventHandler {
    
    private static final Integer BATCH_THRESHOLD = 50;
    
    /**
     * @description Handle after insert events
     * @param newEvents List of new platform events
     */
    public static void handleAfterInsert(List<AI_Case_Request__e> newEvents) {
        if (newEvents == null || newEvents.isEmpty()) {
            return;
        }
        
        try {
            // Create processing status records
            createProcessingStatusRecords(newEvents);
            
            // Check if we should initiate bulk processing
            checkAndInitiateBulkProcessing(newEvents);
            
        } catch (Exception e) {
            ErrorLogService.logError(
                'AI_Case_Request_EventHandler.handleAfterInsert',
                e,
                'Failed to handle AI case request events'
            );
        }
    }
    
    /**
     * @description Create processing status records for tracking
     */
    private static void createProcessingStatusRecords(List<AI_Case_Request__e> events) {
        List<AI_Processing_Status__c> statusRecords = new List<AI_Processing_Status__c>();
        
        for (AI_Case_Request__e event : events) {
            AI_Processing_Status__c status = new AI_Processing_Status__c(
                Case__c = event.CaseId__c,
                AI_Provider__c = event.AI_Provider__c,
                Status__c = 'Pending',
                Request_Time__c = DateTime.now(),
                Success__c = false
            );
            statusRecords.add(status);
        }
        
        if (!statusRecords.isEmpty()) {
            insert SecurityUtils.stripInaccessibleRecords(
                AccessType.CREATABLE,
                statusRecords
            );
        }
    }
    
    /**
     * @description Check if bulk processing should be initiated
     */
    private static void checkAndInitiateBulkProcessing(List<AI_Case_Request__e> events) {
        // Get count of pending requests
        Integer pendingCount = [
            SELECT COUNT()
            FROM AI_Processing_Status__c
            WHERE Status__c = 'Pending'
            WITH SECURITY_ENFORCED
        ];
        
        // If we have enough pending requests and capacity, start processing
        if (pendingCount >= BATCH_THRESHOLD) {
            List<AI_Processing_Status__c> pendingRequests = [
                SELECT Id, Case__c, AI_Provider__c
                FROM AI_Processing_Status__c
                WHERE Status__c = 'Pending'
                ORDER BY Request_Time__c ASC
                LIMIT 200
                WITH SECURITY_ENFORCED
            ];
            
            if (!pendingRequests.isEmpty()) {
                // Convert to platform events for processing
                List<AI_Case_Request__e> requestsToProcess = new List<AI_Case_Request__e>();
                
                for (AI_Processing_Status__c pending : pendingRequests) {
                    AI_Case_Request__e request = new AI_Case_Request__e(
                        CaseId__c = pending.Case__c,
                        AI_Provider__c = pending.AI_Provider__c,
                        Request_Type__c = 'Bulk Process',
                        Priority__c = 'Normal',
                        Status__c = 'Processing'
                    );
                    requestsToProcess.add(request);
                }
                
                // Update status to processing
                for (AI_Processing_Status__c pending : pendingRequests) {
                    pending.Status__c = 'Processing';
                }
                
                update SecurityUtils.stripInaccessibleRecords(
                    AccessType.UPDATABLE,
                    pendingRequests
                );
                
                // Enqueue bulk processing
                if (!requestsToProcess.isEmpty()) {
                    System.enqueueJob(new AIBulkProcessingQueueable(requestsToProcess));
                }
            }
        }
    }
}