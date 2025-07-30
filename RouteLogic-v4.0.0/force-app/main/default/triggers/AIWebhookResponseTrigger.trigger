/**
 * @description Trigger for processing AI Webhook Response platform events
 * @author RouteLogic Team
 * @date 2025-01-17
 */
trigger AIWebhookResponseTrigger on AI_Webhook_Response__e (after insert) {
    // Check for recursion
    if (TriggerRecursionControl.isExecuting('AIWebhookResponseTrigger')) {
        System.debug('AIWebhookResponseTrigger recursion detected - skipping execution');
        return;
    }
    
    // Check max executions
    if (TriggerRecursionControl.hasExceededMaxExecutions('AIWebhookResponseTrigger')) {
        System.debug('AIWebhookResponseTrigger exceeded max executions - skipping');
        return;
    }
    
    try {
        // Set executing flag
        TriggerRecursionControl.setExecuting('AIWebhookResponseTrigger', true);
        
        // Process webhook responses
        AIWebhookResponseHandler.handleWebhookResponses(Trigger.new);
        
    } catch (Exception e) {
        // Log error and publish critical error event
        ErrorLogService.logError('AIWebhookResponseTrigger', e, 'Failed to process webhook responses');
        
        // Publish critical error event
        AI_Critical_Error__e errorEvent = new AI_Critical_Error__e(
            Component__c = 'AIWebhookResponseTrigger',
            Error_Type__c = 'TRIGGER_ERROR',
            Error_Message__c = e.getMessage(),
            Stack_Trace__c = e.getStackTraceString(),
            Severity__c = 'HIGH'
        );
        EventBus.publish(errorEvent);
        
    } finally {
        // Clear executing flag
        TriggerRecursionControl.setExecuting('AIWebhookResponseTrigger', false);
    }
}