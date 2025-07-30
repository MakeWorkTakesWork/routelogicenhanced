/**
 * @description Handler for processing AI webhook responses via Platform Events
 * @author RouteLogic Team
 * @date 2025-01-17
 */
public with sharing class AIWebhookResponseHandler {
    
    /**
     * @description Process webhook response events
     * @param events List of webhook response platform events
     */
    public static void handleWebhookResponses(List<AI_Webhook_Response__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }
        
        List<Case> casesToUpdate = new List<Case>();
        List<AI_Conversation_History__c> conversationUpdates = new List<AI_Conversation_History__c>();
        List<AI_Processing_Status__c> statusUpdates = new List<AI_Processing_Status__c>();
        Map<String, AI_Callback_Context__c> callbackContexts = new Map<String, AI_Callback_Context__c>();
        
        try {
            // Collect callback IDs
            Set<String> callbackIds = new Set<String>();
            for (AI_Webhook_Response__e event : events) {
                if (String.isNotBlank(event.Callback_Id__c)) {
                    callbackIds.add(event.Callback_Id__c);
                }
            }
            
            // Retrieve callback contexts
            if (!callbackIds.isEmpty()) {
                for (AI_Callback_Context__c context : [
                    SELECT Id, Callback_Id__c, Case__c, Request_Data__c, 
                           Provider__c, Created_Date__c
                    FROM AI_Callback_Context__c
                    WHERE Callback_Id__c IN :callbackIds
                    WITH SECURITY_ENFORCED
                ]) {
                    callbackContexts.put(context.Callback_Id__c, context);
                }
            }
            
            // Process each webhook event
            for (AI_Webhook_Response__e event : events) {
                try {
                    processWebhookEvent(
                        event, 
                        callbackContexts, 
                        casesToUpdate, 
                        conversationUpdates, 
                        statusUpdates
                    );
                } catch (Exception e) {
                    // Log individual event processing error
                    ErrorLogService.logError(
                        'Failed to process webhook event', 
                        e, 
                        event.Callback_Id__c
                    );
                }
            }
            
            // Perform bulk updates
            performBulkUpdates(casesToUpdate, conversationUpdates, statusUpdates);
            
            // Clean up callback contexts
            cleanupCallbackContexts(callbackContexts.values());
            
        } catch (Exception e) {
            ErrorLogService.logError('AIWebhookResponseHandler.handleWebhookResponses', e, null);
        }
    }
    
    /**
     * @description Process individual webhook event
     */
    private static void processWebhookEvent(
        AI_Webhook_Response__e event,
        Map<String, AI_Callback_Context__c> callbackContexts,
        List<Case> casesToUpdate,
        List<AI_Conversation_History__c> conversationUpdates,
        List<AI_Processing_Status__c> statusUpdates
    ) {
        // Get callback context
        AI_Callback_Context__c context = callbackContexts.get(event.Callback_Id__c);
        if (context == null) {
            // Handle orphaned webhook
            handleOrphanedWebhook(event);
            return;
        }
        
        // Process based on provider
        switch on event.Provider_Name__c.toLowerCase() {
            when 'ada' {
                processAdaWebhook(event, context, casesToUpdate, conversationUpdates);
            }
            when 'intercom' {
                processIntercomWebhook(event, context, casesToUpdate, conversationUpdates);
            }
            when else {
                throw new AIException('Unknown provider: ' + event.Provider_Name__c);
            }
        }
        
        // Update processing status
        updateProcessingStatus(event, context, statusUpdates);
        
        // Create audit trail
        createAuditTrail(event, context);
    }
    
    /**
     * @description Process Ada webhook response
     */
    private static void processAdaWebhook(
        AI_Webhook_Response__e event,
        AI_Callback_Context__c context,
        List<Case> casesToUpdate,
        List<AI_Conversation_History__c> conversationUpdates
    ) {
        Map<String, Object> responseData = (Map<String, Object>) JSON.deserializeUntyped(event.Response_Data__c);
        
        // Extract Ada-specific data
        String sentiment = (String) responseData.get('sentiment');
        String intent = (String) responseData.get('intent');
        Decimal confidence = (Decimal) responseData.get('confidence');
        String suggestedResponse = (String) responseData.get('suggested_response');
        List<Object> entities = (List<Object>) responseData.get('entities');
        
        // Update case if needed
        if (String.isNotBlank(context.Case__c)) {
            Case caseToUpdate = new Case(Id = context.Case__c);
            
            // Update case fields based on AI analysis
            if (String.isNotBlank(sentiment)) {
                caseToUpdate.AI_Sentiment__c = sentiment;
            }
            
            if (String.isNotBlank(intent)) {
                caseToUpdate.AI_Intent__c = intent;
                
                // Auto-categorize based on intent
                updateCaseCategory(caseToUpdate, intent);
            }
            
            if (confidence != null && confidence > 0.8) {
                caseToUpdate.AI_Confidence_Score__c = confidence;
            }
            
            caseToUpdate.AI_Last_Analysis__c = DateTime.now();
            casesToUpdate.add(caseToUpdate);
            
            // Add to conversation history
            addToConversationHistory(
                context.Case__c,
                'Ada',
                responseData,
                conversationUpdates
            );
        }
    }
    
    /**
     * @description Process Intercom webhook response
     */
    private static void processIntercomWebhook(
        AI_Webhook_Response__e event,
        AI_Callback_Context__c context,
        List<Case> casesToUpdate,
        List<AI_Conversation_History__c> conversationUpdates
    ) {
        Map<String, Object> responseData = (Map<String, Object>) JSON.deserializeUntyped(event.Response_Data__c);
        
        // Extract Intercom-specific data
        Map<String, Object> conversation = (Map<String, Object>) responseData.get('conversation');
        if (conversation != null) {
            String state = (String) conversation.get('state');
            Map<String, Object> statistics = (Map<String, Object>) conversation.get('statistics');
            
            // Update case if needed
            if (String.isNotBlank(context.Case__c)) {
                Case caseToUpdate = new Case(Id = context.Case__c);
                
                // Update based on conversation state
                if ('closed'.equals(state)) {
                    caseToUpdate.Status = 'Resolved';
                    caseToUpdate.AI_Resolution_Type__c = 'Automated';
                }
                
                // Update statistics
                if (statistics != null) {
                    Integer messageCount = (Integer) statistics.get('message_count');
                    Integer responseTime = (Integer) statistics.get('first_response_time');
                    
                    if (messageCount != null) {
                        caseToUpdate.AI_Message_Count__c = messageCount;
                    }
                    
                    if (responseTime != null) {
                        caseToUpdate.AI_Response_Time__c = responseTime;
                    }
                }
                
                caseToUpdate.AI_Last_Analysis__c = DateTime.now();
                casesToUpdate.add(caseToUpdate);
                
                // Add to conversation history
                addToConversationHistory(
                    context.Case__c,
                    'Intercom',
                    responseData,
                    conversationUpdates
                );
            }
        }
    }
    
    /**
     * @description Update case category based on AI intent
     */
    private static void updateCaseCategory(Case c, String intent) {
        Map<String, String> intentToCategoryMap = new Map<String, String>{
            'billing_inquiry' => 'Billing',
            'technical_support' => 'Technical',
            'account_management' => 'Account',
            'product_question' => 'Product',
            'complaint' => 'Complaint',
            'feature_request' => 'Enhancement'
        };
        
        String category = intentToCategoryMap.get(intent.toLowerCase());
        if (String.isNotBlank(category)) {
            c.Type = category;
        }
    }
    
    /**
     * @description Add entry to conversation history
     */
    private static void addToConversationHistory(
        Id caseId,
        String provider,
        Map<String, Object> responseData,
        List<AI_Conversation_History__c> conversationUpdates
    ) {
        AI_Conversation_History__c history = new AI_Conversation_History__c(
            Case__c = caseId,
            Provider__c = provider,
            Message_Type__c = 'AI Response',
            Message_Content__c = JSON.serializePretty(responseData),
            Timestamp__c = DateTime.now(),
            Is_From_Webhook__c = true
        );
        
        conversationUpdates.add(history);
    }
    
    /**
     * @description Update processing status
     */
    private static void updateProcessingStatus(
        AI_Webhook_Response__e event,
        AI_Callback_Context__c context,
        List<AI_Processing_Status__c> statusUpdates
    ) {
        // Find existing status record
        List<AI_Processing_Status__c> existingStatus = [
            SELECT Id, Status__c, Response_Time__c
            FROM AI_Processing_Status__c
            WHERE Case__c = :context.Case__c
            AND AI_Provider__c = :event.Provider_Name__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        if (!existingStatus.isEmpty()) {
            AI_Processing_Status__c status = existingStatus[0];
            status.Status__c = 'Completed';
            status.Response_Time__c = DateTime.now();
            status.Webhook_Received__c = true;
            statusUpdates.add(status);
        }
    }
    
    /**
     * @description Handle orphaned webhook (no matching callback context)
     */
    private static void handleOrphanedWebhook(AI_Webhook_Response__e event) {
        // Log orphaned webhook
        AI_Error_Log__c errorLog = new AI_Error_Log__c(
            Error_Type__c = 'Orphaned Webhook',
            Error_Message__c = 'No callback context found for webhook',
            Provider__c = event.Provider_Name__c,
            Callback_Id__c = event.Callback_Id__c,
            Additional_Info__c = event.Response_Data__c,
            Severity__c = 'Warning'
        );
        
        insert SecurityUtils.stripInaccessibleRecords(
            AccessType.CREATABLE,
            new List<AI_Error_Log__c>{errorLog}
        )[0];
    }
    
    /**
     * @description Create audit trail entry
     */
    private static void createAuditTrail(
        AI_Webhook_Response__e event,
        AI_Callback_Context__c context
    ) {
        AuditService.logWebhookProcessed(
            context.Case__c,
            event.Provider_Name__c,
            event.Callback_Id__c,
            event.Event_Type__c
        );
    }
    
    /**
     * @description Perform bulk updates
     */
    private static void performBulkUpdates(
        List<Case> casesToUpdate,
        List<AI_Conversation_History__c> conversationUpdates,
        List<AI_Processing_Status__c> statusUpdates
    ) {
        // Update cases
        if (!casesToUpdate.isEmpty()) {
            update SecurityUtils.stripInaccessibleRecords(
                AccessType.UPDATABLE,
                casesToUpdate
            );
        }
        
        // Insert conversation history
        if (!conversationUpdates.isEmpty()) {
            insert SecurityUtils.stripInaccessibleRecords(
                AccessType.CREATABLE,
                conversationUpdates
            );
        }
        
        // Update processing status
        if (!statusUpdates.isEmpty()) {
            update SecurityUtils.stripInaccessibleRecords(
                AccessType.UPDATABLE,
                statusUpdates
            );
        }
    }
    
    /**
     * @description Clean up processed callback contexts
     */
    private static void cleanupCallbackContexts(List<AI_Callback_Context__c> contexts) {
        if (!contexts.isEmpty()) {
            delete SecurityUtils.stripInaccessibleRecords(
                AccessType.DELETABLE,
                contexts
            );
        }
    }
}