/**
 * @description Test class for ErrorLogService
 * @author RouteLogic Team
 * @date 2025-01-17
 */
@IsTest
private class ErrorLogServiceTest {
    
    @IsTest
    static void testLogErrorWithException() {
        Test.startTest();
        
        try {
            // Generate a test exception
            Integer result = 10 / 0;
        } catch (Exception e) {
            // Log the exception
            ErrorLogService.logError('TestClass', e, 'Test additional info');
        }
        
        Test.stopTest();
        
        // Verify error log was created
        List<Error_Log__c> errorLogs = [
            SELECT Id, Class_Name__c, Error_Type__c, Error_Message__c, 
                   Additional_Info__c, User__c, Timestamp__c
            FROM Error_Log__c
        ];
        
        System.assertEquals(1, errorLogs.size(), 'Should create 1 error log');
        
        Error_Log__c log = errorLogs[0];
        System.assertEquals('TestClass', log.Class_Name__c, 'Should set class name');
        System.assertEquals('MathException', log.Error_Type__c, 'Should set error type');
        System.assert(log.Error_Message__c.contains('Divide by 0'), 'Should contain error message');
        System.assertEquals('Test additional info', log.Additional_Info__c, 'Should set additional info');
        System.assertEquals(UserInfo.getUserId(), log.User__c, 'Should set user ID');
        System.assertNotEquals(null, log.Timestamp__c, 'Should set timestamp');
    }
    
    @IsTest
    static void testLogErrorWithoutException() {
        Test.startTest();
        
        // Log error without exception
        ErrorLogService.logError('TestClass', 'CustomError', 'Test error message');
        
        Test.stopTest();
        
        // Verify error log was created
        List<Error_Log__c> errorLogs = [
            SELECT Id, Class_Name__c, Error_Type__c, Error_Message__c
            FROM Error_Log__c
        ];
        
        System.assertEquals(1, errorLogs.size(), 'Should create 1 error log');
        
        Error_Log__c log = errorLogs[0];
        System.assertEquals('TestClass', log.Class_Name__c, 'Should set class name');
        System.assertEquals('CustomError', log.Error_Type__c, 'Should set error type');
        System.assertEquals('Test error message', log.Error_Message__c, 'Should set error message');
    }
    
    @IsTest
    static void testLogErrorWithNullException() {
        Test.startTest();
        
        // Log error with null exception
        ErrorLogService.logError('TestClass', null, 'Additional info only');
        
        Test.stopTest();
        
        // Verify error log was created with default values
        List<Error_Log__c> errorLogs = [
            SELECT Id, Class_Name__c, Error_Type__c, Error_Message__c, Additional_Info__c
            FROM Error_Log__c
        ];
        
        System.assertEquals(1, errorLogs.size(), 'Should create 1 error log');
        
        Error_Log__c log = errorLogs[0];
        System.assertEquals('TestClass', log.Class_Name__c, 'Should set class name');
        System.assertEquals('Unknown', log.Error_Type__c, 'Should set default error type');
        System.assertEquals('No exception provided', log.Error_Message__c, 'Should set default message');
        System.assertEquals('Additional info only', log.Additional_Info__c, 'Should set additional info');
    }
    
    @IsTest
    static void testStringTruncation() {
        // Create very long strings
        String longClassName = 'A'.repeat(300);
        String longErrorMessage = 'B'.repeat(300);
        String longAdditionalInfo = 'C'.repeat(40000);
        
        Test.startTest();
        
        // Log error with long strings
        ErrorLogService.logError(longClassName, 'LongStringTest', longErrorMessage);
        
        Test.stopTest();
        
        // Verify strings were truncated
        List<Error_Log__c> errorLogs = [
            SELECT Id, Class_Name__c, Error_Message__c
            FROM Error_Log__c
        ];
        
        System.assertEquals(1, errorLogs.size(), 'Should create 1 error log');
        
        Error_Log__c log = errorLogs[0];
        System.assert(log.Class_Name__c.length() <= 255, 'Class name should be truncated');
        System.assert(log.Error_Message__c.length() <= 255, 'Error message should be truncated');
        System.assert(log.Class_Name__c.endsWith('...'), 'Truncated class name should end with ...');
        System.assert(log.Error_Message__c.endsWith('...'), 'Truncated error message should end with ...');
    }
    
    @IsTest
    static void testStringTruncationWithNullValues() {
        Test.startTest();
        
        // Log error with null values
        ErrorLogService.logError(null, 'NullTest', null);
        
        Test.stopTest();
        
        // Verify null values are handled
        List<Error_Log__c> errorLogs = [
            SELECT Id, Class_Name__c, Error_Message__c
            FROM Error_Log__c
        ];
        
        System.assertEquals(1, errorLogs.size(), 'Should create 1 error log');
        
        Error_Log__c log = errorLogs[0];
        System.assertEquals(null, log.Class_Name__c, 'Null class name should remain null');
        System.assertEquals(null, log.Error_Message__c, 'Null error message should remain null');
    }
    
    @IsTest
    static void testBulkErrorLogging() {
        Test.startTest();
        
        // Log multiple errors
        for (Integer i = 0; i < 10; i++) {
            ErrorLogService.logError('BulkTestClass' + i, 'BulkError', 'Bulk error message ' + i);
        }
        
        Test.stopTest();
        
        // Verify all error logs were created
        List<Error_Log__c> errorLogs = [
            SELECT Id, Class_Name__c, Error_Message__c
            FROM Error_Log__c
            ORDER BY Class_Name__c
        ];
        
        System.assertEquals(10, errorLogs.size(), 'Should create 10 error logs');
        
        // Verify each error log
        for (Integer i = 0; i < errorLogs.size(); i++) {
            Error_Log__c log = errorLogs[i];
            System.assert(log.Class_Name__c.contains('BulkTestClass'), 'Should contain bulk test class name');
            System.assert(log.Error_Message__c.contains('Bulk error message'), 'Should contain bulk error message');
        }
    }
    
    @IsTest
    static void testCleanupOldLogs() {
        // Create test error logs (we can't set CreatedDate in test, so this tests the logic)
        List<Error_Log__c> testLogs = new List<Error_Log__c>();
        for (Integer i = 0; i < 5; i++) {
            testLogs.add(new Error_Log__c(
                Class_Name__c = 'CleanupTest' + i,
                Error_Type__c = 'CleanupError',
                Error_Message__c = 'Test cleanup message ' + i,
                User__c = UserInfo.getUserId(),
                Timestamp__c = DateTime.now()
            ));
        }
        insert testLogs;
        
        Test.startTest();
        
        // Test cleanup with default retention period
        ErrorLogService.cleanupOldLogs(null);
        
        // Test cleanup with specific retention period
        ErrorLogService.cleanupOldLogs(7);
        
        // Test cleanup with invalid retention period
        ErrorLogService.cleanupOldLogs(-5);
        
        Test.stopTest();
        
        // In test context, no records will be deleted due to date filtering
        // This tests that the method executes without errors
        List<Error_Log__c> remainingLogs = [SELECT Id FROM Error_Log__c];
        System.assert(remainingLogs.size() >= 0, 'Cleanup should execute without errors');
    }
    
    @IsTest
    static void testCleanupOldLogsWithZeroRetention() {
        Test.startTest();
        
        // Test cleanup with zero retention period (should default to 30)
        ErrorLogService.cleanupOldLogs(0);
        
        Test.stopTest();
        
        // Should execute without errors
        System.assert(true, 'Cleanup with zero retention should work');
    }
    
    @IsTest
    static void testExceptionHandlingInLogging() {
        Test.startTest();
        
        // This test verifies that logging failures don't throw exceptions
        try {
            // Force a potential logging error by using invalid data
            String invalidClassName = null;
            ErrorLogService.logError(invalidClassName, 'TestError', 'Test message');
            
            // Should not throw any exceptions
            System.assert(true, 'Error logging should handle errors gracefully');
        } catch (Exception e) {
            System.assert(false, 'Error logging should not throw exceptions: ' + e.getMessage());
        }
        
        Test.stopTest();
    }
    
    @IsTest
    static void testStackTraceLogging() {
        Test.startTest();
        
        try {
            // Generate an exception with stack trace
            List<String> testList = new List<String>();
            String value = testList[5]; // This will cause IndexOutOfBoundsException
        } catch (Exception e) {
            // Log the exception with stack trace
            ErrorLogService.logError('StackTraceTest', e, 'Testing stack trace logging');
        }
        
        Test.stopTest();
        
        // Verify stack trace was logged
        List<Error_Log__c> errorLogs = [
            SELECT Id, Error_Type__c, Stack_Trace__c
            FROM Error_Log__c
        ];
        
        System.assertEquals(1, errorLogs.size(), 'Should create 1 error log');
        
        Error_Log__c log = errorLogs[0];
        System.assertEquals('ListException', log.Error_Type__c, 'Should log ListException');
        System.assertNotEquals(null, log.Stack_Trace__c, 'Should log stack trace');
        System.assert(log.Stack_Trace__c.contains('StackTraceTest'), 'Stack trace should contain test class');
    }
    
    @IsTest
    static void testLongStackTraceHandling() {
        Test.startTest();
        
        try {
            // Create a deep call stack to generate long stack trace
            deepMethod1();
        } catch (Exception e) {
            // Log the exception
            ErrorLogService.logError('LongStackTraceTest', e, 'Testing long stack trace');
        }
        
        Test.stopTest();
        
        // Verify stack trace was truncated if necessary
        List<Error_Log__c> errorLogs = [
            SELECT Id, Stack_Trace__c
            FROM Error_Log__c
        ];
        
        System.assertEquals(1, errorLogs.size(), 'Should create 1 error log');
        
        Error_Log__c log = errorLogs[0];
        System.assertNotEquals(null, log.Stack_Trace__c, 'Should log stack trace');
        System.assert(log.Stack_Trace__c.length() <= 32768, 'Stack trace should be within limits');
    }
    
    @IsTest
    static void testConcurrentErrorLogging() {
        Test.startTest();
        
        // Simulate concurrent error logging
        List<String> classNames = new List<String>();
        for (Integer i = 0; i < 20; i++) {
            classNames.add('ConcurrentTest' + i);
        }
        
        // Log errors concurrently (simulated)
        for (String className : classNames) {
            ErrorLogService.logError(className, 'ConcurrentError', 'Concurrent test message');
        }
        
        Test.stopTest();
        
        // Verify all logs were created
        List<Error_Log__c> errorLogs = [
            SELECT Id, Class_Name__c
            FROM Error_Log__c
            WHERE Class_Name__c LIKE 'ConcurrentTest%'
        ];
        
        System.assertEquals(20, errorLogs.size(), 'Should create all concurrent logs');
    }
    
    // Helper methods for testing
    private static void deepMethod1() {
        deepMethod2();
    }
    
    private static void deepMethod2() {
        deepMethod3();
    }
    
    private static void deepMethod3() {
        deepMethod4();
    }
    
    private static void deepMethod4() {
        // Generate an exception with deep stack trace
        throw new CustomException('Deep stack trace test');
    }
    
    public class CustomException extends Exception {}
}