/**
 * @description Trigger for AI_Case_Request__e platform events
 * @author RouteLogic Team
 * @date 2025-01-17
 */
trigger AI_Case_Request_EventTrigger on AI_Case_Request__e (after insert) {
    
    // Check for recursion
    if (TriggerRecursionControl.isExecuting('AI_Case_Request_EventTrigger')) {
        System.debug('AI_Case_Request_EventTrigger recursion detected - skipping execution');
        return;
    }
    
    // Check max executions
    if (TriggerRecursionControl.hasExceededMaxExecutions('AI_Case_Request_EventTrigger')) {
        System.debug('AI_Case_Request_EventTrigger exceeded max executions - skipping');
        return;
    }
    
    if (Trigger.isAfter && Trigger.isInsert) {
        try {
            // Set executing flag
            TriggerRecursionControl.setExecuting('AI_Case_Request_EventTrigger', true);
            
            // Handle events
            AI_Case_Request_EventHandler.handleAfterInsert(Trigger.new);
            
        } catch (Exception e) {
            // Log error and publish critical error event
            ErrorLogService.logError('AI_Case_Request_EventTrigger', e, 'Failed to process case request events');
            
            // Publish critical error event
            AI_Critical_Error__e errorEvent = new AI_Critical_Error__e(
                Component__c = 'AI_Case_Request_EventTrigger',
                Error_Type__c = 'TRIGGER_ERROR',
                Error_Message__c = e.getMessage(),
                Stack_Trace__c = e.getStackTraceString(),
                Severity__c = 'HIGH'
            );
            EventBus.publish(errorEvent);
            
        } finally {
            // Clear executing flag
            TriggerRecursionControl.setExecuting('AI_Case_Request_EventTrigger', false);
        }
    }
}