/**
 * @description Performance optimizer for high-volume bulk processing (10,000+ cases/hour)
 * @author RouteLogic Team
 * @date 2025-01-18
 */
public with sharing class BulkProcessingOptimizer {
    
    // Optimized configuration for 10K+ cases/hour
    // Using centralized constants to avoid naming collisions
    
    /**
     * @description Optimize bulk processing for high volume
     * @param caseIds List of case IDs to process
     * @return Job IDs of enqueued jobs
     */
    public static List<Id> optimizeBulkProcessing(List<Id> caseIds) {
        List<Id> jobIds = new List<Id>();
        
        try {
            // Validate volume
            if (caseIds.size() > 10000) {
                // Use platform events for extreme volumes
                return processThroughPlatformEvents(caseIds);
            }
            
            // Check current job queue capacity
            Integer currentJobs = getCurrentQueuedJobs();
            Integer availableSlots = MAX_CONCURRENT_JOBS - currentJobs;
            
            if (availableSlots <= 0) {
                // Queue to staging for later processing
                queueToStagingTable(caseIds);
                return jobIds;
            }
            
            // Partition cases by priority and provider
            Map<String, List<Id>> partitionedCases = partitionCasesByOptimalCriteria(caseIds);
            
            // Process each partition
            Integer jobsQueued = 0;
            for (String partitionKey : partitionedCases.keySet()) {
                if (jobsQueued >= availableSlots) {
                    // Queue remaining to staging
                    queueToStagingTable(partitionedCases.get(partitionKey));
                    continue;
                }
                
                List<Id> partitionCaseIds = partitionedCases.get(partitionKey);
                
                // Create optimized chunks
                List<List<Id>> chunks = createOptimalChunks(partitionCaseIds, Constants.OPTIMAL_BATCH_SIZE);
                
                for (List<Id> chunk : chunks) {
                    if (jobsQueued < availableSlots) {
                        Id jobId = enqueueBulkProcessingJob(chunk, partitionKey);
                        if (jobId != null) {
                            jobIds.add(jobId);
                            jobsQueued++;
                        }
                    } else {
                        queueToStagingTable(chunk);
                    }
                }
            }
            
            // Log optimization metrics
            logOptimizationMetrics(caseIds.size(), jobIds.size());
            
        } catch (Exception e) {
            ErrorLogService.logError('BulkProcessingOptimizer.optimizeBulkProcessing', e, 
                'Failed to optimize processing for ' + caseIds.size() + ' cases');
            throw new OptimizationException('Bulk processing optimization failed: ' + e.getMessage());
        }
        
        return jobIds;
    }
    
    /**
     * @description Process extreme volumes through platform events
     */
    private static List<Id> processThroughPlatformEvents(List<Id> caseIds) {
        List<Id> eventIds = new List<Id>();
        List<AI_Case_Request__e> events = new List<AI_Case_Request__e>();
        
        // Query all cases at once to avoid SOQL-in-loop
        Map<Id, Case> allCases = new Map<Id, Case>([
            SELECT Id, Priority, AI_Processing_Status__c, AI_Last_Analysis__c
            FROM Case
            WHERE Id IN :caseIds
            WITH SECURITY_ENFORCED
            LIMIT 10000  // Safety limit
        ]);
        
        // Pre-serialize metadata once for efficiency
        String eventMetadata = JSON.serialize(new Map<String, Object>{
            'bulkOptimized' => true,
            'timestamp' => DateTime.now()
        });
        
        // Process cases and create events
        for (Case c : allCases.values()) {
            AI_Case_Request__e event = new AI_Case_Request__e(
                CaseId__c = c.Id,
                Priority__c = c.Priority,
                AI_Provider__c = 'Auto',
                Request_Type__c = 'Bulk',
                Status__c = 'Pending',
                Metadata__c = eventMetadata
            );
            events.add(event);
            
            // Publish in batches to avoid platform event limits
            if (events.size() >= Constants.PLATFORM_EVENT_BATCH_SIZE) {
                List<Database.SaveResult> results = EventBus.publish(events);
                eventIds.addAll(processPublishResults(results, events));
                events.clear();
            }
        }
        
        // Publish remaining events
        if (!events.isEmpty()) {
            List<Database.SaveResult> results = EventBus.publish(events);
            eventIds.addAll(processPublishResults(results, events));
        }
        
        return eventIds;
    }
    
    /**
     * @description Process publish results and return event IDs
     */
    private static List<Id> processPublishResults(List<Database.SaveResult> results, List<AI_Case_Request__e> events) {
        List<Id> eventIds = new List<Id>();
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                eventIds.add(results[i].getId());
            } else {
                // Log publish failures
                System.debug('Failed to publish event for case: ' + events[i].CaseId__c);
                for (Database.Error err : results[i].getErrors()) {
                    System.debug('Error: ' + err.getMessage());
                }
            }
        }
        return eventIds;
    }
    
    /**
     * @description Partition cases by optimal criteria for parallel processing
     */
    private static Map<String, List<Id>> partitionCasesByOptimalCriteria(List<Id> caseIds) {
        Map<String, List<Id>> partitions = new Map<String, List<Id>>();
        
        // Query cases with minimal fields to reduce heap usage
        List<Case> cases = [
            SELECT Id, Priority, AI_Processing_Status__c, OwnerId
            FROM Case
            WHERE Id IN :caseIds
            WITH SECURITY_ENFORCED
        ];
        
        for (Case c : cases) {
            // Create partition key based on priority and processing status
            String partitionKey = c.Priority + '_' + 
                (String.isNotBlank(c.AI_Processing_Status__c) ? c.AI_Processing_Status__c : 'New');
            
            if (!partitions.containsKey(partitionKey)) {
                partitions.put(partitionKey, new List<Id>());
            }
            partitions.get(partitionKey).add(c.Id);
        }
        
        return partitions;
    }
    
    /**
     * @description Create optimal chunks for processing
     */
    private static List<List<Id>> createOptimalChunks(List<Id> caseIds, Integer chunkSize) {
        List<List<Id>> chunks = new List<List<Id>>();
        List<Id> currentChunk = new List<Id>();
        
        for (Id caseId : caseIds) {
            currentChunk.add(caseId);
            
            if (currentChunk.size() >= chunkSize) {
                chunks.add(currentChunk);
                currentChunk = new List<Id>();
            }
        }
        
        if (!currentChunk.isEmpty()) {
            chunks.add(currentChunk);
        }
        
        return chunks;
    }
    
    /**
     * @description Enqueue optimized bulk processing job
     */
    private static Id enqueueBulkProcessingJob(List<Id> caseIds, String partitionKey) {
        try {
            // Create platform events for the cases
            List<AI_Case_Request__e> requests = new List<AI_Case_Request__e>();
            
            for (Id caseId : caseIds) {
                requests.add(new AI_Case_Request__e(
                    CaseId__c = caseId,
                    Priority__c = getPriorityFromPartitionKey(partitionKey),
                    AI_Provider__c = 'Auto',
                    Request_Type__c = 'Bulk',
                    Status__c = 'Pending'
                ));
            }
            
            // Enqueue the processing job
            AIBulkProcessingQueueable job = new AIBulkProcessingQueueable(requests);
            return System.enqueueJob(job);
            
        } catch (Exception e) {
            ErrorLogService.logError('BulkProcessingOptimizer.enqueueBulkProcessingJob', e, 
                'Failed to enqueue job for partition: ' + partitionKey);
            return null;
        }
    }
    
    /**
     * @description Queue cases to staging table for later processing
     */
    private static void queueToStagingTable(List<Id> caseIds) {
        List<AI_Processing_Queue__c> stagingRecords = new List<AI_Processing_Queue__c>();
        
        for (Id caseId : caseIds) {
            stagingRecords.add(new AI_Processing_Queue__c(
                Case__c = caseId,
                Status__c = 'Pending',
                Priority__c = 'Normal',
                Queued_Date__c = DateTime.now()
            ));
        }
        
        if (!stagingRecords.isEmpty()) {
            insert SecurityUtils.stripInaccessibleRecords(AccessType.CREATABLE, stagingRecords);
        }
    }
    
    /**
     * @description Get current number of queued jobs
     */
    private static Integer getCurrentQueuedJobs() {
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE Status IN ('Holding', 'Queued', 'Processing')
            AND JobType = 'Queueable'
        ];
    }
    
    /**
     * @description Get priority from partition key
     */
    private static String getPriorityFromPartitionKey(String partitionKey) {
        if (partitionKey.startsWith('High')) return 'High';
        if (partitionKey.startsWith('Medium')) return 'Medium';
        return 'Low';
    }
    
    /**
     * @description Log optimization metrics
     */
    private static void logOptimizationMetrics(Integer totalCases, Integer jobsQueued) {
        AI_Optimization_Metrics__c metrics = new AI_Optimization_Metrics__c(
            Total_Cases__c = totalCases,
            Jobs_Queued__c = jobsQueued,
            Optimization_Type__c = 'Bulk Processing',
            Timestamp__c = DateTime.now(),
            Average_Cases_Per_Job__c = jobsQueued > 0 ? (Decimal)totalCases / (Decimal)jobsQueued : 0
        );
        
        insert SecurityUtils.stripInaccessibleRecords(
            AccessType.CREATABLE, 
            new List<AI_Optimization_Metrics__c>{metrics}
        );
    }
    
    /**
     * @description Initialize platform cache for high-volume processing
     */
    public static void initializeHighVolumeCache() {
        Cache.OrgPartition orgPart = Cache.Org.getPartition('routelogic.AIProcessing');
        
        if (orgPart == null) {
            throw new OptimizationException('Platform cache partition not configured');
        }
        
        // Pre-populate cache with frequently accessed data
        Map<String, Object> cacheConfig = new Map<String, Object>{
            'maxBatchSize' => Constants.OPTIMAL_BATCH_SIZE,
            'maxConcurrentJobs' => Constants.MAX_CONCURRENT_JOBS,
            'priorityWeights' => new Map<String, Integer>{
                'High' => 100,
                'Medium' => 50,
                'Low' => 10
            }
        };
        
        orgPart.put('BulkProcessingConfig', cacheConfig);
    }
    
    /**
     * @description Monitor and auto-scale processing based on load
     */
    @future
    public static void autoScaleProcessing() {
        // Pre-calculate datetime to avoid inline calculation in SOQL
        DateTime oneHourAgo = DateTime.now().addHours(-1);
        
        // Get current processing metrics
        List<AI_Bulk_Processing_Metrics__c> recentMetrics = [
            SELECT Processing_Time_Ms__c, Total_Requests__c, Average_Time_Per_Request__c
            FROM AI_Bulk_Processing_Metrics__c
            WHERE CreatedDate >= :oneHourAgo
            ORDER BY CreatedDate DESC
            LIMIT 10
        ];
        
        if (recentMetrics.isEmpty()) {
            return;
        }
        
        // Calculate average processing time
        Decimal avgProcessingTime = 0;
        for (AI_Bulk_Processing_Metrics__c metric : recentMetrics) {
            avgProcessingTime += metric.Average_Time_Per_Request__c;
        }
        avgProcessingTime = avgProcessingTime / (Decimal)recentMetrics.size();
        
        // Determine if scaling is needed
        if (avgProcessingTime > 1000) { // More than 1 second per request
            // Reduce batch size for faster processing
            adjustBatchSize(Integer.valueOf(Constants.OPTIMAL_BATCH_SIZE / 2.0));
        } else if (avgProcessingTime < 200) { // Less than 200ms per request
            // Increase batch size for efficiency
            adjustBatchSize(Constants.OPTIMAL_BATCH_SIZE * 1.5);
        }
    }
    
    /**
     * @description Adjust batch size dynamically
     */
    private static void adjustBatchSize(Decimal newSize) {
        Cache.OrgPartition orgPart = Cache.Org.getPartition('routelogic.AIProcessing');
        if (orgPart != null) {
            Map<String, Object> config = (Map<String, Object>) orgPart.get('BulkProcessingConfig');
            if (config != null) {
                config.put('maxBatchSize', Integer.valueOf(newSize));
                orgPart.put('BulkProcessingConfig', config);
            }
        }
    }
    
    /**
     * @description Custom exception for optimization errors
     */
    public class OptimizationException extends Exception {}
}