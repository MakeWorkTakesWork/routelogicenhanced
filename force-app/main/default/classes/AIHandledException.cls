/**
 * @description Custom exception class for AI processing that prevents stack trace exposure
 * @author RouteLogic Team
 * @date 2025-01-19
 */
@namespaceAccessible
public with sharing class AIHandledException extends AuraHandledException {
    
    /**
     * @description Constructor that wraps error message without exposing stack trace
     * @param message User-friendly error message
     */
    public AIHandledException(String message) {
        super(message);
        this.setMessage(message);
    }
}