/**
 * @description Enhanced queueable class for bulk AI request processing
 * @author RouteLogic Team
 * @date 2025-01-17
 */
public class AIBulkProcessingQueueable implements Queueable, Database.AllowsCallouts {
    
    // Use centralized constants
    private static final Integer BATCH_SIZE = Constants.BATCH_THRESHOLD;
    private static final Integer MAX_CALLOUT_TIME = Constants.MAX_CALLOUT_TIME;
    private static final Integer RETRY_ATTEMPTS = Constants.RETRY_ATTEMPTS;
    
    private List<AI_Case_Request__e> requests;
    private Map<String, List<AI_Case_Request__e>> requestsByProvider;
    private BulkProcessingMetrics metrics;
    
    /**
     * @description Constructor
     * @param requests List of AI case requests to process
     */
    public AIBulkProcessingQueueable(List<AI_Case_Request__e> requests) {
        this.requests = requests;
        this.metrics = new BulkProcessingMetrics();
        this.metrics.totalRequests = requests.size();
        this.metrics.startTime = DateTime.now();
    }
    
    /**
     * @description Execute method for queueable
     */
    public void execute(QueueableContext context) {
        try {
            // Group requests by provider for efficient bulk processing
            groupRequestsByProvider();
            
            // Process each provider's requests in bulk
            for (String provider : requestsByProvider.keySet()) {
                processBulkRequests(provider, requestsByProvider.get(provider));
            }
            
            // Log metrics
            logProcessingMetrics();
            
            // Chain next batch if needed
            chainNextBatchIfNeeded();
            
        } catch (CalloutException e) {
            handleProcessingError(e);
            // Specific handling for callout errors
            if (e.getMessage().contains('Read timed out')) {
                // Queue for retry on timeout
                queueForRetry(requests, 'Callout timeout: ' + e.getMessage());
            }
        } catch (DmlException e) {
            handleProcessingError(e);
            // Log DML failures for investigation
        } catch (Exception e) {
            handleProcessingError(e);
        }
    }
    
    /**
     * @description Group requests by AI provider
     */
    private void groupRequestsByProvider() {
        requestsByProvider = new Map<String, List<AI_Case_Request__e>>();
        
        for (AI_Case_Request__e request : requests) {
            String provider = request.AI_Provider__c;
            if (!requestsByProvider.containsKey(provider)) {
                requestsByProvider.put(provider, new List<AI_Case_Request__e>());
            }
            requestsByProvider.get(provider).add(request);
        }
    }
    
    /**
     * @description Process bulk requests for a specific provider using AgnosticRoutingEngine
     */
    private void processBulkRequests(String provider, List<AI_Case_Request__e> providerRequests) {
        // Get provider adapter (new architecture)
        IAIProviderAdapter providerAdapter = AIProviderAdapterFactory.getAdapter(provider);
        
        // Extract case IDs for bulk routing decisions
        Set<Id> caseIds = new Set<Id>();
        for (AI_Case_Request__e request : providerRequests) {
            caseIds.add(request.Case_Id__c);
        }
        
        // Make bulk routing decisions using AgnosticRoutingEngine
        Map<Id, AgnosticRoutingEngine.RoutingDecision> routingDecisions = 
            AgnosticRoutingEngine.makeBulkRoutingDecisions(new List<Id>(caseIds));
        
        // Create routing ledger entries for audit trail
        List<Routing_Ledger__c> ledgerEntries = new List<Routing_Ledger__c>();
        
        // Process each request with routing decision
        for (AI_Case_Request__e request : providerRequests) {
            AgnosticRoutingEngine.RoutingDecision decision = routingDecisions.get(request.Case_Id__c);
            
            if (decision != null) {
                // Create ledger entry for immutable audit trail
                Routing_Ledger__c ledger = RoutingLedgerTriggerHandler.createLedgerEntry(decision, provider);
                ledgerEntries.add(ledger);
                
                // Prepare provider-specific request
                Object providerRequest = providerAdapter.prepareProviderRequest(decision);
                
                // Execute handoff (this replaces the old API callout logic)
                executeHandoff(provider, request, decision, providerRequest);
            }
        }
        
        // Insert ledger entries for audit trail
        if (!ledgerEntries.isEmpty()) {
            try {
                Database.SaveResult[] ledgerResults = Database.insert(ledgerEntries, false);
                metrics.successfulLedgerEntries += ledgerEntries.size();
            } catch (DmlException e) {
                metrics.failedLedgerEntries += ledgerEntries.size();
            }
        }
    }
    
    /**
     * @description Process a batch of requests
     */
    private void processBatch(String provider, List<AI_Case_Request__e> batch, IAIProviderSecurity securityProvider) {
        try {
            // Check rate limits
            if (!securityProvider.checkRateLimit('bulk_process')) {
                // Queue for retry
                queueForRetry(batch, 'Rate limit exceeded');
                metrics.rateLimitExceeded += batch.size();
                return;
            }
            
            // Prepare bulk request
            BulkAIRequest bulkRequest = prepareBulkRequest(provider, batch, securityProvider);
            
            // Make API call
            HttpResponse response = makeBulkAPICall(provider, bulkRequest, securityProvider);
            
            // Process response
            if (response.getStatusCode() == 200) {
                processBulkResponse(provider, response, batch);
                metrics.successfulRequests += batch.size();
            } else {
                handleBulkError(response, batch);
                metrics.failedRequests += batch.size();
            }
            
        } catch (Exception e) {
            handleBatchError(e, batch);
            metrics.errorRequests += batch.size();
        }
    }
    
    /**
     * @description Prepare bulk request for AI provider
     */
    private BulkAIRequest prepareBulkRequest(String provider, List<AI_Case_Request__e> batch, IAIProviderSecurity securityProvider) {
        BulkAIRequest bulkRequest = new BulkAIRequest();
        bulkRequest.provider = provider;
        bulkRequest.requests = new List<SingleAIRequest>();
        
        // Get cases for enrichment
        Set<Id> caseIds = new Set<Id>();
        for (AI_Case_Request__e request : batch) {
            caseIds.add(request.CaseId__c);
        }
        
        Map<Id, Case> casesMap = new Map<Id, Case>([
            SELECT Id, Subject, Description, Priority, Status, AccountId, ContactId,
                   Account.Name, Contact.Name, Contact.Email
            FROM Case
            WHERE Id IN :caseIds
            WITH SECURITY_ENFORCED
        ]);
        
        // Build individual requests
        for (AI_Case_Request__e request : batch) {
            SingleAIRequest singleRequest = new SingleAIRequest();
            singleRequest.requestId = generateRequestId();
            singleRequest.caseId = request.CaseId__c;
            singleRequest.requestType = request.Request_Type__c;
            singleRequest.priority = request.Priority__c;
            
            // Enrich with case data
            Case c = casesMap.get(request.CaseId__c);
            if (c != null) {
                singleRequest.context = buildContext(c);
                
                // Sanitize and mask PII in content
                String region = PIIMaskingService.detectRegion();
                String sanitizedContent = securityProvider.sanitizeRequest(c.Description);
                singleRequest.content = PIIMaskingService.maskPII(sanitizedContent, region);
            }
            
            // Add metadata
            if (String.isNotBlank(request.Metadata__c)) {
                singleRequest.metadata = (Map<String, Object>) JSON.deserializeUntyped(request.Metadata__c);
            }
            
            bulkRequest.requests.add(singleRequest);
        }
        
        // Set bulk request metadata
        bulkRequest.batchId = context != null ? context.getJobId() : generateBatchId();
        bulkRequest.timestamp = DateTime.now();
        bulkRequest.totalCount = batch.size();
        
        return bulkRequest;
    }
    
    /**
     * @description Make bulk API call to AI provider
     */
    private HttpResponse makeBulkAPICall(String provider, BulkAIRequest bulkRequest, IAIProviderSecurity securityProvider) {
        HttpRequest req = new HttpRequest();
        
        // Get provider configuration
        Map<String, Object> config = securityProvider.getProviderConfig();
        String endpoint = (String) config.get('endpoint') + '/bulk/process';
        
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setTimeout(ConfigManager.getCalloutTimeoutMs());
        
        // Set security headers
        Map<String, String> headers = securityProvider.getSecurityHeaders();
        for (String key : headers.keySet()) {
            req.setHeader(key, headers.get(key));
        }
        
        // Serialize request body
        String requestBody = JSON.serialize(bulkRequest);
        
        // Check if compression should be enabled
        if (ConfigManager.isCompressionEnabled() && shouldCompressRequest(requestBody)) {
            // Enable gzip compression
            req.setCompressed(true);
            req.setHeader('Content-Encoding', 'gzip');
            req.setHeader('Accept-Encoding', 'gzip');
        }
        
        // Set body
        req.setBody(requestBody);
        
        // Make callout with retry logic for rate limits
        Http http = new Http();
        HttpResponse response;
        Integer retryAttempts = 0;
        Integer maxRetries = 3;
        
        while (retryAttempts <= maxRetries) {
            try {
                response = http.send(req);
                
                // Check for rate limit response
                if (response.getStatusCode() == Constants.HTTP_TOO_MANY_REQUESTS) {
                    if (retryAttempts < maxRetries) {
                        // Extract retry delay from headers
                        Integer retryAfter = extractRetryAfter(response);
                        
                        // Log rate limit hit
                        
                        // Publish rate limit metric
                        EventBus.publish(new AI_Processing_Metric__e(
                            Provider__c = provider,
                            Request_Status__c = 'Rate_Limited',
                            Retry_Count__c = retryAttempts,
                            Processing_Time_Ms__c = retryAfter * 1000
                        ));
                        
                        // Wait before retry (convert to milliseconds, max 10 seconds)
                        Integer waitTime = Math.min(retryAfter * 1000, 10000);
                        if (waitTime > 0) {
                            // Use CPU time safe delay
                            Long startTime = System.currentTimeMillis();
                            while (System.currentTimeMillis() - startTime < waitTime) {
                                // Busy wait to avoid CPU timeout
                            }
                        }
                        
                        retryAttempts++;
                        continue;
                    } else {
                        // Max retries exceeded, throw rate limit error
                        throw new AIException(Constants.RATE_LIMIT_ERROR, 
                            'Rate limit exceeded for provider ' + provider + ' after ' + maxRetries + ' retries');
                    }
                }
                
                // Check for other retryable status codes
                if (Constants.RETRYABLE_STATUS_CODES.contains(response.getStatusCode()) && retryAttempts < maxRetries) {
                    retryAttempts++;
                    // Exponential backoff
                    Integer backoffMs = Math.min(1000 * (Integer)Math.pow(2, retryAttempts), 5000);
                    Long startTime = System.currentTimeMillis();
                    while (System.currentTimeMillis() - startTime < backoffMs) {
                        // Busy wait
                    }
                    continue;
                }
                
                // Success or non-retryable error, break out of loop
                break;
                
            } catch (CalloutException e) {
                if (retryAttempts < maxRetries) {
                    retryAttempts++;
                    continue;
                }
                throw e;
            }
        }
        
        // Validate response
        if (!securityProvider.validateResponse(response)) {
            throw new AIException('Invalid response from provider');
        }
        
        return response;
    }
    
    /**
     * @description Process bulk API response
     */
    private void processBulkResponse(String provider, HttpResponse response, List<AI_Case_Request__e> batch) {
        BulkAIResponse bulkResponse = (BulkAIResponse) JSON.deserialize(
            response.getBody(), 
            BulkAIResponse.class
        );
        
        List<Case> casesToUpdate = new List<Case>();
        List<AI_Processing_Status__c> statusesToInsert = new List<AI_Processing_Status__c>();
        Map<String, AI_Callback_Context__c> callbackContexts = new Map<String, AI_Callback_Context__c>();
        List<AI_Processing_Metric__e> metrics = new List<AI_Processing_Metric__e>();
        
        // Process individual responses
        for (Integer i = 0; i < bulkResponse.responses.size(); i++) {
            SingleAIResponse singleResponse = bulkResponse.responses[i];
            AI_Case_Request__e originalRequest = batch[i];
            
            // Update case with AI response
            if (singleResponse.success) {
                Case c = new Case(Id = originalRequest.CaseId__c);
                updateCaseFromResponse(c, singleResponse);
                casesToUpdate.add(c);
                
                // Create processing status
                AI_Processing_Status__c status = new AI_Processing_Status__c(
                    Case__c = originalRequest.CaseId__c,
                    AI_Provider__c = provider,
                    Status__c = 'Completed',
                    Request_Time__c = bulkRequest.timestamp,
                    Response_Time__c = DateTime.now(),
                    Success__c = true
                );
                statusesToInsert.add(status);
                
                // Publish success metric
                Long processingTime = bulkRequest.timestamp != null ? 
                    DateTime.now().getTime() - bulkRequest.timestamp.getTime() : 0;
                metrics.add(new AI_Processing_Metric__e(
                    Case_ID__c = originalRequest.CaseId__c,
                    Provider__c = provider,
                    Retry_Count__c = 0, // TODO: Get actual retry count if this was a retry
                    Request_Status__c = 'Success',
                    Processing_Time_Ms__c = processingTime.intValue()
                ));
                
                // Store callback context if async
                if (singleResponse.isAsync && String.isNotBlank(singleResponse.callbackId)) {
                    AI_Callback_Context__c context = new AI_Callback_Context__c(
                        Callback_Id__c = singleResponse.callbackId,
                        Case__c = originalRequest.CaseId__c,
                        Provider__c = provider,
                        Request_Data__c = JSON.serialize(singleResponse)
                    );
                    callbackContexts.put(singleResponse.callbackId, context);
                }
            } else {
                // Handle individual request failure
                handleSingleRequestFailure(originalRequest, singleResponse);
            }
        }
        
        // Bulk updates
        if (!casesToUpdate.isEmpty()) {
            update SecurityUtils.stripInaccessibleRecords(AccessType.UPDATABLE, casesToUpdate);
        }
        
        if (!statusesToInsert.isEmpty()) {
            insert SecurityUtils.stripInaccessibleRecords(AccessType.CREATABLE, statusesToInsert);
        }
        
        if (!callbackContexts.isEmpty()) {
            insert SecurityUtils.stripInaccessibleRecords(AccessType.CREATABLE, callbackContexts.values());
        }
        
        // Publish all metrics
        if (!metrics.isEmpty()) {
            EventBus.publish(metrics);
        }
    }
    
    /**
     * @description Update case from AI response
     */
    private void updateCaseFromResponse(Case c, SingleAIResponse response) {
        if (response.sentiment != null) {
            c.AI_Sentiment__c = response.sentiment;
        }
        
        if (response.intent != null) {
            c.AI_Intent__c = response.intent;
        }
        
        if (response.suggestedPriority != null) {
            c.Priority = response.suggestedPriority;
        }
        
        if (response.suggestedResponse != null) {
            c.AI_Suggested_Response__c = response.suggestedResponse;
        }
        
        c.AI_Last_Analysis__c = DateTime.now();
        c.AI_Processing_Status__c = 'Processed';
    }
    
    /**
     * @description Handle bulk error response
     */
    private void handleBulkError(HttpResponse response, List<AI_Case_Request__e> batch) {
        String errorMessage = 'Bulk API error: ' + response.getStatusCode() + ' - ' + response.getStatus();
        
        // Log error
        ErrorLogService.logError('AIBulkProcessingQueueable', null, errorMessage);
        
        // Queue for retry if retryable
        if (isRetryableError(response.getStatusCode())) {
            queueForRetry(batch, errorMessage);
        } else {
            // Create failed status records
            createFailedStatusRecords(batch, errorMessage);
        }
    }
    
    /**
     * @description Handle batch processing error
     */
    private void handleBatchError(Exception e, List<AI_Case_Request__e> batch) {
        ErrorLogService.logError('AIBulkProcessingQueueable.processBatch', e, null);
        queueForRetry(batch, e.getMessage());
    }
    
    /**
     * @description Handle single request failure within bulk response
     */
    private void handleSingleRequestFailure(AI_Case_Request__e request, SingleAIResponse response) {
        // Create failed status record
        AI_Processing_Status__c status = new AI_Processing_Status__c(
            Case__c = request.CaseId__c,
            AI_Provider__c = request.AI_Provider__c,
            Status__c = 'Failed',
            Error_Message__c = response.errorMessage,
            Success__c = false
        );
        
        insert SecurityUtils.stripInaccessibleRecords(
            AccessType.CREATABLE,
            new List<AI_Processing_Status__c>{status}
        )[0];
        
        // Queue for retry if appropriate
        if (response.retryable) {
            queueForRetry(new List<AI_Case_Request__e>{request}, response.errorMessage);
        }
    }
    
    /**
     * @description Queue requests for retry
     */
    private void queueForRetry(List<AI_Case_Request__e> requests, String reason) {
        List<AI_Retry_Request__c> retryRequests = new List<AI_Retry_Request__c>();
        List<AI_Processing_Metric__e> metrics = new List<AI_Processing_Metric__e>();
        
        for (AI_Case_Request__e request : requests) {
            AI_Retry_Request__c retry = new AI_Retry_Request__c(
                Case__c = request.CaseId__c,
                Provider__c = request.AI_Provider__c,
                Request_Type__c = request.Request_Type__c,
                Request_Data__c = JSON.serialize(request),
                Retry_Count__c = 0,
                Max_Retries__c = RETRY_ATTEMPTS,
                Status__c = 'Pending',
                Error_Message__c = reason
            );
            retryRequests.add(retry);
            
            // Create metric for initial retry queue
            metrics.add(new AI_Processing_Metric__e(
                Case_ID__c = request.CaseId__c,
                Provider__c = request.AI_Provider__c,
                Retry_Count__c = 0,
                Request_Status__c = 'Queued_For_Retry',
                Processing_Time_Ms__c = 0
            ));
        }
        
        if (!retryRequests.isEmpty()) {
            insert SecurityUtils.stripInaccessibleRecords(AccessType.CREATABLE, retryRequests);
        }
        
        // Publish retry metrics
        if (!metrics.isEmpty()) {
            EventBus.publish(metrics);
        }
    }
    
    /**
     * @description Create failed status records
     */
    private void createFailedStatusRecords(List<AI_Case_Request__e> batch, String errorMessage) {
        List<AI_Processing_Status__c> failedStatuses = new List<AI_Processing_Status__c>();
        
        for (AI_Case_Request__e request : batch) {
            AI_Processing_Status__c status = new AI_Processing_Status__c(
                Case__c = request.CaseId__c,
                AI_Provider__c = request.AI_Provider__c,
                Status__c = 'Failed',
                Error_Message__c = errorMessage,
                Success__c = false
            );
            failedStatuses.add(status);
        }
        
        if (!failedStatuses.isEmpty()) {
            insert SecurityUtils.stripInaccessibleRecords(AccessType.CREATABLE, failedStatuses);
        }
    }
    
    /**
     * @description Check if error is retryable
     */
    private Boolean isRetryableError(Integer statusCode) {
        Set<Integer> retryableStatusCodes = new Set<Integer>{
            429, // Too Many Requests
            500, // Internal Server Error
            502, // Bad Gateway
            503, // Service Unavailable
            504  // Gateway Timeout
        };
        
        return retryableStatusCodes.contains(statusCode);
    }
    
    /**
     * @description Log processing metrics
     */
    private void logProcessingMetrics() {
        metrics.endTime = DateTime.now();
        metrics.processingTimeMs = metrics.endTime.getTime() - metrics.startTime.getTime();
        
        // Create metrics record
        AI_Bulk_Processing_Metrics__c metricsRecord = new AI_Bulk_Processing_Metrics__c(
            Batch_Id__c = context != null ? context.getJobId() : generateBatchId(),
            Total_Requests__c = metrics.totalRequests,
            Successful_Requests__c = metrics.successfulRequests,
            Failed_Requests__c = metrics.failedRequests,
            Error_Requests__c = metrics.errorRequests,
            Rate_Limit_Exceeded__c = metrics.rateLimitExceeded,
            Processing_Time_Ms__c = metrics.processingTimeMs,
            Average_Time_Per_Request__c = metrics.totalRequests > 0 ? 
                (Decimal)metrics.processingTimeMs / (Decimal)metrics.totalRequests : 0
        );
        
        insert SecurityUtils.stripInaccessibleRecords(
            AccessType.CREATABLE,
            new List<AI_Bulk_Processing_Metrics__c>{metricsRecord}
        )[0];
    }
    
    /**
     * @description Chain next batch if needed
     */
    private void chainNextBatchIfNeeded() {
        // Check if more queueable jobs can be enqueued
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            // Check for pending cases that need AI processing
            List<Case> pendingCases = [
                SELECT Id, Priority, AI_Processing_Status__c
                FROM Case
                WHERE AI_Processing_Status__c = 'Pending'
                AND LastModifiedDate >= :DateTime.now().addHours(-24)
                WITH SECURITY_ENFORCED
                ORDER BY Priority DESC, CreatedDate ASC
                LIMIT 200
            ];
            
            if (!pendingCases.isEmpty()) {
                // Create platform events for the pending cases
                List<AI_Case_Request__e> newRequests = new List<AI_Case_Request__e>();
                for (Case c : pendingCases) {
                    AI_Case_Request__e event = new AI_Case_Request__e(
                        CaseId__c = c.Id,
                        Priority__c = c.Priority,
                        AI_Provider__c = 'Auto',
                        Request_Type__c = 'Bulk'
                    );
                    newRequests.add(event);
                }
                
                // Chain next batch with the new requests
                if (!newRequests.isEmpty()) {
                    System.enqueueJob(new AIBulkProcessingQueueable(newRequests));
                }
            }
        }
    }
    
    /**
     * @description Determine if request should be compressed
     * @param requestBody The JSON request body
     * @return True if compression should be enabled
     */
    private Boolean shouldCompressRequest(String requestBody) {
        // Get compression threshold from configuration
        Integer compressionThreshold = ConfigManager.getCompressionThreshold();
        return requestBody != null && requestBody.length() > compressionThreshold;
    }
    
    /**
     * @description Extract retry-after value from response headers
     * @param response The HTTP response
     * @return Retry delay in seconds
     */
    private Integer extractRetryAfter(HttpResponse response) {
        String retryAfterHeader = response.getHeader('Retry-After');
        
        if (String.isNotBlank(retryAfterHeader)) {
            try {
                // Retry-After can be in seconds or HTTP date format
                return Integer.valueOf(retryAfterHeader);
            } catch (Exception e) {
                // If not a number, might be a date - default to 60 seconds
                return 60;
            }
        }
        
        // Check for provider-specific headers
        String rateLimitReset = response.getHeader('X-RateLimit-Reset');
        if (String.isNotBlank(rateLimitReset)) {
            try {
                // Unix timestamp - calculate seconds until reset
                Long resetTime = Long.valueOf(rateLimitReset);
                Long currentTime = DateTime.now().getTime() / 1000L; // Convert to seconds
                return Math.max(1, Integer.valueOf(resetTime - currentTime));
            } catch (Exception e) {
                // Default fallback
            }
        }
        
        // Default retry after 60 seconds if no header found
        return 60;
    }
    
    /**
     * @description Handle processing error
     */
    private void handleProcessingError(Exception e) {
        ErrorLogService.logError('AIBulkProcessingQueueable.execute', e, null);
        
        // Send alert for critical errors
        if (e.getMessage().contains('LIMIT') || e.getMessage().contains('governor')) {
            sendCriticalErrorAlert(e);
        }
    }
    
    /**
     * @description Execute handoff using provider adapter
     */
    private void executeHandoff(String provider, AI_Case_Request__e request, 
                               AgnosticRoutingEngine.RoutingDecision decision, Object providerRequest) {
        try {
            // Get provider adapter
            IAIProviderAdapter adapter = AIProviderAdapterFactory.getAdapter(provider);
            
            // Validate request before sending
            if (providerRequest != null) {
                String requestJson = JSON.serialize(providerRequest);
                String sanitizedRequest = adapter.sanitizeRequest(requestJson);
                
                // Execute the handoff (this would typically be an API call)
                // For now, we'll update the case with routing information
                updateCaseWithRoutingDecision(request.Case_Id__c, decision);
                
                metrics.successfulHandoffs++;
            } else {
                metrics.failedHandoffs++;
            }
            
        } catch (Exception e) {
            metrics.failedHandoffs++;
            ErrorLogService.logError('executeHandoff', e, 'Provider: ' + provider + ', Case: ' + request.Case_Id__c);
        }
    }
    
    /**
     * @description Update case with routing decision
     */
    private void updateCaseWithRoutingDecision(Id caseId, AgnosticRoutingEngine.RoutingDecision decision) {
        try {
            Case caseToUpdate = new Case(
                Id = caseId,
                AI_Routing_Decision__c = JSON.serialize(decision),
                AI_Target_Skill_Group__c = decision.targetSkillGroup,
                AI_Suggested_Priority__c = decision.suggestedPriority,
                AI_Escalation_Reason__c = decision.escalationReason,
                AI_Processing_Status__c = 'Routed'
            );
            
            update SecurityUtils.stripInaccessibleRecords(
                AccessType.UPDATABLE,
                new List<Case>{caseToUpdate}
            )[0];
            
        } catch (DmlException e) {
        }
    }
    
    /**
     * @description Send critical error alert
     */
    private void sendCriticalErrorAlert(Exception e) {
        // Create platform event for real-time alerting
        AI_Critical_Error__e errorEvent = new AI_Critical_Error__e(
            Error_Type__c = 'Bulk Processing Failure',
            Error_Message__c = e.getMessage(),
            Stack_Trace__c = e.getStackTraceString(),
            Component__c = 'AIBulkProcessingQueueable',
            Severity__c = 'Critical'
        );
        
        EventBus.publish(errorEvent);
    }
    
    // Helper methods
    
    private String generateRequestId() {
        return EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-512', 
                Blob.valueOf(String.valueOf(DateTime.now().getTime()) + Math.random())
            )
        ).substring(0, 16);
    }
    
    private String generateBatchId() {
        return 'BATCH_' + DateTime.now().format('yyyyMMddHHmmss') + '_' + 
               String.valueOf(Math.random()).substring(2, 8);
    }
    
    private Map<String, Object> buildContext(Case c) {
        // Detect region for PII masking
        String region = PIIMaskingService.detectRegion();
        
        Map<String, Object> context = new Map<String, Object>{
            'caseNumber' => c.CaseNumber,
            'subject' => PIIMaskingService.maskPII(c.Subject, region),
            'priority' => c.Priority,
            'status' => c.Status
        };
        
        if (c.Account != null) {
            context.put('accountName', c.Account.Name);
        }
        
        if (c.Contact != null) {
            context.put('contactName', c.Contact.Name);
            // Mask email if PII masking is enabled for region
            context.put('contactEmail', PIIMaskingService.maskPII(c.Contact.Email, region));
        }
        
        return context;
    }
    
    // Inner classes
    
    public class BulkProcessingMetrics {
        public Integer totalRequests = 0;
        public Integer successfulRequests = 0;
        public Integer failedRequests = 0;
        public Integer errorRequests = 0;
        public Integer rateLimitExceeded = 0;
        public Integer successfulHandoffs = 0;
        public Integer failedHandoffs = 0;
        public Integer successfulLedgerEntries = 0;
        public Integer failedLedgerEntries = 0;
        public DateTime startTime;
        public DateTime endTime;
        public Long processingTimeMs;
    }
    
    public class BulkAIRequest {
        public String provider;
        public String batchId;
        public DateTime timestamp;
        public Integer totalCount;
        public List<SingleAIRequest> requests;
    }
    
    public class SingleAIRequest {
        public String requestId;
        public String caseId;
        public String requestType;
        public String priority;
        public String content;
        public Map<String, Object> context;
        public Map<String, Object> metadata;
    }
    
    public class BulkAIResponse {
        public String batchId;
        public Boolean success;
        public Integer processedCount;
        public List<SingleAIResponse> responses;
    }
    
    public class SingleAIResponse {
        public String requestId;
        public Boolean success;
        public String errorMessage;
        public Boolean retryable;
        public String sentiment;
        public String intent;
        public String suggestedPriority;
        public String suggestedResponse;
        public Boolean isAsync;
        public String callbackId;
        public Map<String, Object> additionalData;
    }
}