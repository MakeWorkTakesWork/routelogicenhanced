/**
 * @description Utility class to prevent trigger recursion
 * @author RouteLogic Team
 * @date 2025-01-19
 */
@namespaceAccessible
public with sharing class TriggerRecursionControl {
    
    // Static variables to track trigger execution
    private static Map<String, Boolean> isExecutingMap = new Map<String, Boolean>();
    private static Map<String, Integer> executionCountMap = new Map<String, Integer>();
    private static final Integer TRIGGER_MAX_EXECUTIONS = 5;
    
    /**
     * @description Check if a trigger is currently executing
     * @param triggerName Name of the trigger
     * @return True if trigger is executing, false otherwise
     */
    public static Boolean isExecuting(String triggerName) {
        return isExecutingMap.containsKey(triggerName) && isExecutingMap.get(triggerName);
    }
    
    /**
     * @description Set trigger execution status
     * @param triggerName Name of the trigger
     * @param isExecuting Execution status
     */
    public static void setExecuting(String triggerName, Boolean isExecuting) {
        isExecutingMap.put(triggerName, isExecuting);
        
        if (isExecuting) {
            incrementExecutionCount(triggerName);
        }
    }
    
    /**
     * @description Check if trigger has exceeded max executions
     * @param triggerName Name of the trigger
     * @return True if max executions exceeded
     */
    public static Boolean hasExceededMaxExecutions(String triggerName) {
        Integer count = executionCountMap.get(triggerName);
        return count != null && count > TRIGGER_MAX_EXECUTIONS;
    }
    
    /**
     * @description Reset execution tracking for a trigger
     * @param triggerName Name of the trigger
     */
    public static void reset(String triggerName) {
        isExecutingMap.remove(triggerName);
        executionCountMap.remove(triggerName);
    }
    
    /**
     * @description Reset all trigger tracking
     */
    public static void resetAll() {
        isExecutingMap.clear();
        executionCountMap.clear();
    }
    
    /**
     * @description Increment execution count for a trigger
     * @param triggerName Name of the trigger
     */
    private static void incrementExecutionCount(String triggerName) {
        Integer count = executionCountMap.get(triggerName);
        if (count == null) {
            count = 0;
        }
        executionCountMap.put(triggerName, count + 1);
    }
}