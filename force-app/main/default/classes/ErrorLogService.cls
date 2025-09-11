/**
 * @description Centralized error logging service
 * @author RouteLogic Team
 * @date 2025-01-17
 */
public with sharing class ErrorLogService {
    
    private static final Integer ERROR_LOG_MAX_MESSAGE_LENGTH = 255;
    private static final Integer ERROR_LOG_MAX_STACK_TRACE_LENGTH = 32768;
    
    /**
     * @description Log an error with exception
     * @param className The class where error occurred
     * @param ex The exception that was caught
     * @param additionalInfo Additional context information
     */
    public static void logError(String className, Exception ex, String additionalInfo) {
        if (ex != null) {
            createErrorLog(
                className,
                ex.getTypeName(),
                ex.getMessage(),
                ex.getStackTraceString(),
                additionalInfo
            );
        } else {
            createErrorLog(
                className,
                'Unknown',
                'No exception provided',
                null,
                additionalInfo
            );
        }
    }
    
    /**
     * @description Log an error without exception
     * @param className The class where error occurred
     * @param errorType Type of error
     * @param errorMessage Error message
     */
    public static void logError(String className, String errorType, String errorMessage) {
        createErrorLog(
            className,
            errorType,
            errorMessage,
            null,
            null
        );
    }
    
    /**
     * @description Create error log record
     */
    private static void createErrorLog(
        String className,
        String errorType,
        String errorMessage,
        String stackTrace,
        String additionalInfo
    ) {
        try {
            Error_Log__c errorLog = new Error_Log__c(
                Class_Name__c = truncateString(className, ERROR_LOG_MAX_MESSAGE_LENGTH),
                Error_Type__c = truncateString(errorType, ERROR_LOG_MAX_MESSAGE_LENGTH),
                Error_Message__c = errorMessage,
                Stack_Trace__c = truncateString(stackTrace, ERROR_LOG_MAX_STACK_TRACE_LENGTH),
                Additional_Info__c = truncateString(additionalInfo, ERROR_LOG_MAX_STACK_TRACE_LENGTH),
                User__c = UserInfo.getUserId(),
                Timestamp__c = DateTime.now()
            );
            
            // Apply FLS before insert
            List<Error_Log__c> logsToInsert = new List<Error_Log__c>{errorLog};
            logsToInsert = SecurityUtils.stripInaccessibleRecords(
                AccessType.CREATABLE,
                logsToInsert
            );
            
            // Use Database.insert with partial success to ensure logging doesn't fail
            Database.SaveResult result = Database.insert(logsToInsert[0], false);
            
            if (!result.isSuccess()) {
                /* If we can't persist the log, output it to debug so the
                 * details are still available in the execution log. */
                System.debug(formatDebugMessage(
                    className,
                    errorType,
                    errorMessage,
                    stackTrace,
                    additionalInfo
                ) + '\nDB Errors: ' + result.getErrors());
            }
        } catch (Exception e) {
            // Fallback to debug logging if database logging fails
            System.debug('ErrorLogService failed: ' + e.getMessage());
            System.debug(formatDebugMessage(
                className,
                errorType,
                errorMessage,
                stackTrace,
                additionalInfo
            ));
        }
    }
    
    /**
     * @description Truncate string to specified length
     */
    private static String truncateString(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return null;
        }
        
        if (value.length() <= maxLength) {
            return value;
        }
        
        return value.substring(0, maxLength - 3) + '...';
    }
    
    /**
     * @description Format error message for debug logging
     */
    private static String formatDebugMessage(
        String className,
        String errorType,
        String errorMessage,
        String stackTrace,
        String additionalInfo
    ) {
        List<String> parts = new List<String>();
        
        parts.add('=== ERROR LOG ===');
        parts.add('Class: ' + className);
        parts.add('Type: ' + errorType);
        parts.add('Message: ' + errorMessage);
        
        if (String.isNotBlank(stackTrace)) {
            parts.add('Stack Trace: ' + stackTrace);
        }
        
        if (String.isNotBlank(additionalInfo)) {
            parts.add('Additional Info: ' + additionalInfo);
        }
        
        parts.add('User: ' + UserInfo.getUserName());
        parts.add('Time: ' + DateTime.now().format());
        parts.add('================');
        
        return String.join(parts, '\n');
    }
    
    /**
     * @description Overload to log an error when you already have a stack trace string.
     * @param className The class where the error occurred
     * @param errorType The type/category of the error
     * @param errorMessage The error message
     * @param stackTrace The stack trace string
     */
    public static void logError(
        String className,
        String errorType,
        String errorMessage,
        String stackTrace
    ) {
        createErrorLog(
            className,
            errorType,
            errorMessage,
            stackTrace,
            null
        );
    }

    /**
     * @description Batch delete old error logs
     * @param daysToKeep Number of days to keep error logs
     */
    public static void cleanupOldLogs(Integer daysToKeep) {
        if (daysToKeep == null || daysToKeep < 1) {
            daysToKeep = 30; // Default retention period
        }
        
        DateTime cutoffDate = DateTime.now().addDays(-daysToKeep);
        
        List<Error_Log__c> logsToDelete = [
            SELECT Id
            FROM Error_Log__c
            WHERE Timestamp__c < :cutoffDate
            WITH SECURITY_ENFORCED
            LIMIT 10000
        ];
        
        if (!logsToDelete.isEmpty()) {
            delete SecurityUtils.stripInaccessibleRecords(
                AccessType.DELETABLE,
                logsToDelete
            );
        }
    }
}
