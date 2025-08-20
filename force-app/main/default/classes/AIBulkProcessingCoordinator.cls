/**
 * @description Service class that coordinates AI bulk processing operations
 * This class orchestrates the bulk processing of AI requests, managing batches,
 * retries, and provider allocation.
 * @author RouteLogic Team
 * @date 2025-01-20
 * @group AI Processing
 * 
 * PHASE 1 UPDATE: Completed getPendingRequests implementation
 */
public with sharing class AIBulkProcessingCoordinator {
    
    // Class constants for configuration
    private static final Integer DEFAULT_BATCH_SIZE = 100;
    private static final Integer MAX_RETRY_ATTEMPTS = 3;
    private static final Integer CIRCUIT_BREAKER_THRESHOLD = 5;
    private static final Integer CIRCUIT_BREAKER_TIMEOUT_MINUTES = 30;
    
    /**
     * @description Initiates bulk processing for pending AI requests
     * @param batchSize Optional batch size override
     * @return Job ID of the initiated process
     */
    @AuraEnabled
    public static String initiateBulkProcessing(Integer batchSize) {
        try {
            if (batchSize == null || batchSize <= 0) {
                batchSize = DEFAULT_BATCH_SIZE;
            }
            
            // Check circuit breaker status
            if (isCircuitBreakerOpen()) {
                throw new AIHandledException('Circuit breaker is open. Too many failures detected.');
            }
            
            // Get pending requests
            List<AI_Case_Request__e> pendingRequests = getPendingRequests(batchSize);
            
            if (pendingRequests.isEmpty()) {
                return 'No pending requests to process';
            }
            
            // Queue the bulk processing job
            AIBulkProcessingQueueable job = new AIBulkProcessingQueueable(pendingRequests);
            String jobId = System.enqueueJob(job);
            
            // Log the initiation
            MetricsLogger.logEvent('AI_BULK_PROCESSING_INITIATED', new Map<String, Object>{
                'jobId' => jobId,
                'batchSize' => pendingRequests.size(),
                'timestamp' => System.now()
            });
            
            return jobId;
            
        } catch (Exception e) {
            ErrorLogService.logError(
                'AIBulkProcessingCoordinator.initiateBulkProcessing',
                e.getMessage(),
                e.getStackTraceString(),
                null
            );
            throw new AIHandledException('Failed to initiate bulk processing: ' + e.getMessage());
        }
    }
    
    /**
     * @description PHASE 1 IMPLEMENTATION - Gets pending AI requests for processing
     * Since platform events cannot be queried directly, this method queries
     * AI_Processing_Status__c records with 'Pending' status and converts them
     * to platform events for processing
     * @param batchSize Number of requests to retrieve
     * @return List of pending platform events
     */
    private static List<AI_Case_Request__e> getPendingRequests(Integer batchSize) {
        // Query pending processing status records ordered by request time
        List<AI_Processing_Status__c> pendingStatuses = [
            SELECT Id, Case__c, AI_Provider__c, Request_Time__c, Priority__c,
                   Request_Type__c, Retry_Count__c, Original_Request_Id__c
            FROM AI_Processing_Status__c
            WHERE Status__c = 'Pending'
            AND Is_Active__c = true
            ORDER BY Priority__c DESC, Request_Time__c ASC
            LIMIT :batchSize
            WITH SECURITY_ENFORCED
        ];
        
        if (pendingStatuses.isEmpty()) {
            return new List<AI_Case_Request__e>();
        }
        
        // Convert status records to platform events
        List<AI_Case_Request__e> pendingRequests = new List<AI_Case_Request__e>();
        Set<Id> statusIdsToUpdate = new Set<Id>();
        
        for (AI_Processing_Status__c status : pendingStatuses) {
            // Create platform event from status record
            AI_Case_Request__e request = new AI_Case_Request__e(
                CaseId__c = status.Case__c,
                AI_Provider__c = status.AI_Provider__c,
                Request_Type__c = status.Request_Type__c != null ? status.Request_Type__c : 'Bulk Process',
                Priority__c = status.Priority__c != null ? status.Priority__c : 'Normal',
                Status__c = 'Processing',
                Processing_Status_Id__c = status.Id,
                Original_Request_Id__c = status.Original_Request_Id__c
            );
            pendingRequests.add(request);
            statusIdsToUpdate.add(status.Id);
        }
        
        // Update status records to 'Processing' to prevent duplicate processing
        if (!statusIdsToUpdate.isEmpty()) {
            updateStatusRecords(statusIdsToUpdate, 'Processing');
        }
        
        // Log retrieval
        MetricsLogger.logEvent('PENDING_REQUESTS_RETRIEVED', new Map<String, Object>{
            'count' => pendingRequests.size(),
            'batchSize' => batchSize,
            'timestamp' => System.now()
        });
        
        return pendingRequests;
    }
    
    /**
     * @description Updates AI Processing Status records to a new status
     * @param statusIds Set of record IDs to update
     * @param newStatus New status value
     */
    private static void updateStatusRecords(Set<Id> statusIds, String newStatus) {
        List<AI_Processing_Status__c> statusesToUpdate = new List<AI_Processing_Status__c>();
        
        for (Id statusId : statusIds) {
            statusesToUpdate.add(new AI_Processing_Status__c(
                Id = statusId,
                Status__c = newStatus,
                Last_Modified_Time__c = System.now(),
                Processing_Start_Time__c = (newStatus == 'Processing') ? System.now() : null
            ));
        }
        
        // Use security utils to strip inaccessible fields before update
        List<AI_Processing_Status__c> accessibleRecords = 
            SecurityUtils.stripInaccessibleRecords(AccessType.UPDATABLE, statusesToUpdate);
        
        if (!accessibleRecords.isEmpty()) {
            Database.SaveResult[] results = Database.update(accessibleRecords, false);
        }
    }
    
    /**
     * @description Processes the retry queue for failed AI requests
     * @return Number of retries processed
     */
    @AuraEnabled
    public static Integer processRetryQueue() {
        try {
            List<AI_Retry_Request__c> retryRequests = [
                SELECT Id, Case__c, AI_Provider__c, Retry_Count__c, Error_Message__c,
                       Last_Retry_Time__c, Original_Request_Id__c
                FROM AI_Retry_Request__c
                WHERE Status__c = 'Pending'
                AND Retry_Count__c < :MAX_RETRY_ATTEMPTS
                AND (Last_Retry_Time__c = null OR 
                     Last_Retry_Time__c < :DateTime.now().addMinutes(-5))
                ORDER BY Retry_Count__c ASC, CreatedDate ASC
                LIMIT 50
                WITH SECURITY_ENFORCED
            ];
            
            if (retryRequests.isEmpty()) {
                return 0;
            }
            
            // Convert retry requests to platform events
            List<AI_Case_Request__e> eventsToPublish = new List<AI_Case_Request__e>();
            List<AI_Retry_Request__c> requestsToUpdate = new List<AI_Retry_Request__c>();
            
            for (AI_Retry_Request__c retry : retryRequests) {
                AI_Case_Request__e event = new AI_Case_Request__e(
                    CaseId__c = retry.Case__c,
                    AI_Provider__c = retry.AI_Provider__c,
                    Request_Type__c = 'Retry',
                    Priority__c = 'High',
                    Retry_Count__c = retry.Retry_Count__c + 1,
                    Original_Request_Id__c = retry.Original_Request_Id__c
                );
                eventsToPublish.add(event);
                
                retry.Status__c = 'Processing';
                retry.Retry_Count__c += 1;
                retry.Last_Retry_Time__c = DateTime.now();
                requestsToUpdate.add(retry);
            }
            
            // Update retry records
            update SecurityUtils.stripInaccessibleRecords(
                AccessType.UPDATABLE, 
                requestsToUpdate
            );
            
            // Publish platform events
            List<Database.SaveResult> publishResults = EventBus.publish(eventsToPublish);
            
            // Log results
            Integer successCount = 0;
            for (Database.SaveResult result : publishResults) {
                if (result.isSuccess()) {
                    successCount++;
                }
            }
            
            MetricsLogger.logEvent('RETRY_QUEUE_PROCESSED', new Map<String, Object>{
                'totalRetries' => retryRequests.size(),
                'successfulPublish' => successCount,
                'timestamp' => System.now()
            });
            
            return successCount;
            
        } catch (Exception e) {
            ErrorLogService.logError(
                'AIBulkProcessingCoordinator.processRetryQueue',
                e.getMessage(),
                e.getStackTraceString(),
                null
            );
            throw new AIHandledException('Failed to process retry queue: ' + e.getMessage());
        }
    }
    
    /**
     * @description Checks if circuit breaker is open due to excessive failures
     * @return True if circuit breaker is open
     */
    private static Boolean isCircuitBreakerOpen() {
        // Query recent failures
        Integer recentFailures = [
            SELECT COUNT()
            FROM Error_Log__c
            WHERE Class_Name__c = 'AIBulkProcessingCoordinator'
            AND CreatedDate >= :DateTime.now().addMinutes(-CIRCUIT_BREAKER_TIMEOUT_MINUTES)
            WITH SECURITY_ENFORCED
        ];
        
        return recentFailures >= CIRCUIT_BREAKER_THRESHOLD;
    }
    
    /**
     * @description Cancels all pending AI processing jobs
     * @return Number of jobs cancelled
     */
    @AuraEnabled
    public static Integer cancelAllPendingJobs() {
        try {
            // Update all pending status records to cancelled
            List<AI_Processing_Status__c> pendingStatuses = [
                SELECT Id
                FROM AI_Processing_Status__c
                WHERE Status__c IN ('Pending', 'Processing')
                WITH SECURITY_ENFORCED
            ];
            
            if (pendingStatuses.isEmpty()) {
                return 0;
            }
            
            for (AI_Processing_Status__c status : pendingStatuses) {
                status.Status__c = 'Cancelled';
                status.Completion_Time__c = System.now();
                status.Error_Message__c = 'Cancelled by user';
            }
            
            update SecurityUtils.stripInaccessibleRecords(
                AccessType.UPDATABLE,
                pendingStatuses
            );
            
            // Cancel any queued Apex jobs
            List<AsyncApexJob> queuedJobs = [
                SELECT Id
                FROM AsyncApexJob
                WHERE ApexClass.Name = 'AIBulkProcessingQueueable'
                AND Status IN ('Queued', 'Preparing')
            ];
            
            for (AsyncApexJob job : queuedJobs) {
                System.abortJob(job.Id);
            }
            
            MetricsLogger.logEvent('BULK_PROCESSING_CANCELLED', new Map<String, Object>{
                'cancelledCount' => pendingStatuses.size(),
                'timestamp' => System.now()
            });
            
            return pendingStatuses.size();
            
        } catch (Exception e) {
            ErrorLogService.logError(
                'AIBulkProcessingCoordinator.cancelAllPendingJobs',
                e.getMessage(),
                e.getStackTraceString(),
                null
            );
            throw new AIHandledException('Failed to cancel pending jobs: ' + e.getMessage());
        }
    }
    
    /**
     * @description Gets the current processing status metrics
     * @return ProcessingStatus object with current metrics
     */
    @AuraEnabled(cacheable=true)
    public static ProcessingStatus getProcessingStatus() {
        try {
            ProcessingStatus status = new ProcessingStatus();
            
            // Get counts by status
            List<AggregateResult> statusCounts = [
                SELECT Status__c, COUNT(Id) cnt
                FROM AI_Processing_Status__c
                WHERE CreatedDate = TODAY
                GROUP BY Status__c
                WITH SECURITY_ENFORCED
            ];
            
            for (AggregateResult ar : statusCounts) {
                String statusValue = (String)ar.get('Status__c');
                Integer count = (Integer)ar.get('cnt');
                
                if (statusValue == 'Pending') {
                    status.pendingCount = count;
                } else if (statusValue == 'Processing') {
                    status.processingCount = count;
                } else if (statusValue == 'Completed') {
                    status.completedCount = count;
                } else if (statusValue == 'Failed') {
                    status.failedCount = count;
                }
            }
            
            // Calculate totals
            status.totalCount = status.pendingCount + status.processingCount + 
                               status.completedCount + status.failedCount;
            
            // Get active jobs
            status.activeJobs = [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE ApexClass.Name = 'AIBulkProcessingQueueable'
                AND Status IN ('Queued', 'Processing', 'Preparing')
            ];
            
            return status;
            
        } catch (Exception e) {
            ErrorLogService.logError(
                'AIBulkProcessingCoordinator.getProcessingStatus',
                e.getMessage(),
                e.getStackTraceString(),
                null
            );
            throw new AIHandledException('Failed to get processing status: ' + e.getMessage());
        }
    }
    
    /**
     * @description Inner class to hold processing status information
     */
    public class ProcessingStatus {
        @AuraEnabled public Integer pendingCount { get; set; }
        @AuraEnabled public Integer processingCount { get; set; }
        @AuraEnabled public Integer completedCount { get; set; }
        @AuraEnabled public Integer failedCount { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
        @AuraEnabled public Integer activeJobs { get; set; }
        
        public ProcessingStatus() {
            this.pendingCount = 0;
            this.processingCount = 0;
            this.completedCount = 0;
            this.failedCount = 0;
            this.totalCount = 0;
            this.activeJobs = 0;
        }
    }
}