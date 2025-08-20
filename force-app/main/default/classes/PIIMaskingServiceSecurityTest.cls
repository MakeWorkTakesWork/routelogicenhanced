/**
 * @description Security test class for PIIMaskingService ReDoS and XSS fixes
 * @author RouteLogic Security Team
 * @date 2025-01-31
 */
@isTest
private class PIIMaskingServiceSecurityTest {
    
    /**
     * @description Test ReDoS mitigation for phone pattern
     */
    @isTest
    static void testReDoSMitigation() {
        // Create a malicious pattern that would cause catastrophic backtracking in old regex
        String maliciousPhone = '(+1-555-555-' + String.valueOf('5').repeat(10000) + '5555';
        
        // Mock ConfigManager response
        Test.startTest();
        
        // Measure execution time
        Long startTime = System.currentTimeMillis();
        
        try {
            // This should complete quickly without ReDoS
            String result = PIIMaskingService.maskPII(maliciousPhone, 'US');
            
            Long elapsedTime = System.currentTimeMillis() - startTime;
            
            // Should complete in less than 100ms (ReDoS would take seconds/minutes)
            System.assert(elapsedTime < 100, 'ReDoS vulnerability detected - took ' + elapsedTime + 'ms');
            
        } catch (Exception e) {
            // Expected for extremely long input
            System.assert(e.getMessage().contains('exceeds maximum'), 
                'Should throw max length exception for very long input');
        }
        
        Test.stopTest();
    }
    
    /**
     * @description Test XSS prevention in PII masking
     */
    @isTest
    static void testXSSPrevention() {
        // Test malicious script injection attempts
        String xssPayload = 'test@email.com<script>alert("XSS")</script>';
        
        Test.startTest();
        
        String result = PIIMaskingService.maskPII(xssPayload, 'US');
        
        // Should mask email but not execute script
        System.assert(!result.contains('<script>'), 'XSS payload should be sanitized');
        System.assert(result.contains('***@email.com'), 'Email should still be masked');
        
        Test.stopTest();
    }
    
    /**
     * @description Test null byte detection
     */
    @isTest
    static void testNullByteDetection() {
        String textWithNullByte = 'test@email.com\u0000malicious';
        
        Test.startTest();
        
        try {
            PIIMaskingService.maskPII(textWithNullByte, 'US');
            System.assert(false, 'Should have thrown exception for null bytes');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('null bytes'), 
                'Should detect and reject null bytes');
        }
        
        Test.stopTest();
    }
    
    /**
     * @description Test case-insensitive region comparison
     */
    @isTest
    static void testCaseInsensitiveRegion() {
        String testSSN = '123-45-6789';
        
        Test.startTest();
        
        // Test various case combinations
        String result1 = PIIMaskingService.maskPII(testSSN, 'US');
        String result2 = PIIMaskingService.maskPII(testSSN, 'us');
        String result3 = PIIMaskingService.maskPII(testSSN, 'Us');
        String result4 = PIIMaskingService.maskPII(testSSN, 'uS');
        
        // All should mask SSN the same way
        System.assertEquals('XXX-XX-6789', result1, 'US should mask SSN');
        System.assertEquals('XXX-XX-6789', result2, 'us should mask SSN');
        System.assertEquals('XXX-XX-6789', result3, 'Us should mask SSN');
        System.assertEquals('XXX-XX-6789', result4, 'uS should mask SSN');
        
        Test.stopTest();
    }
    
    /**
     * @description Test StringBuilder performance optimization
     */
    @isTest
    static void testStringBuilderPerformance() {
        // Create text with multiple PII elements
        String testText = '';
        for (Integer i = 0; i < 100; i++) {
            testText += 'Email: test' + i + '@example.com, Phone: 555-555-' + 
                String.valueOf(1000 + i) + ', ';
        }
        
        Test.startTest();
        
        Long startTime = System.currentTimeMillis();
        String result = PIIMaskingService.maskPII(testText, 'US');
        Long elapsedTime = System.currentTimeMillis() - startTime;
        
        // Should process 100 PII elements efficiently
        System.assert(elapsedTime < 500, 'Should process 100 PII elements in < 500ms');
        
        // Verify masking worked
        System.assert(!result.contains('test0@example.com'), 'Emails should be masked');
        System.assert(result.contains('XXX-XXX-'), 'Phone numbers should be masked');
        
        Test.stopTest();
    }
    
    /**
     * @description Test maximum text length validation
     */
    @isTest
    static void testMaxTextLength() {
        // Create text that exceeds maximum length
        String longText = 'a'.repeat(1000001); // 1MB + 1 byte
        
        Test.startTest();
        
        try {
            PIIMaskingService.maskPII(longText, 'US');
            System.assert(false, 'Should have thrown exception for oversized input');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('exceeds maximum'), 
                'Should enforce maximum text length');
        }
        
        Test.stopTest();
    }
    
    /**
     * @description Test edge cases in phone masking
     */
    @isTest
    static void testPhoneMaskingEdgeCases() {
        Test.startTest();
        
        // Test various phone formats
        String result1 = PIIMaskingService.maskPII('555-555-5555', 'US');
        String result2 = PIIMaskingService.maskPII('555.555.5555', 'US');
        String result3 = PIIMaskingService.maskPII('5555555555', 'US');
        
        // All should be masked to show only last 4 digits
        System.assert(result1.contains('XXX-XXX-5555'), 'Dashed phone should be masked');
        System.assert(result2.contains('XXX-XXX-5555'), 'Dotted phone should be masked');
        System.assert(result3.contains('XXX-XXX-5555'), 'Continuous phone should be masked');
        
        Test.stopTest();
    }
    
    /**
     * @description Test email masking edge cases
     */
    @isTest
    static void testEmailMaskingEdgeCases() {
        Test.startTest();
        
        // Test short email addresses
        String result1 = PIIMaskingService.maskPII('a@test.com', 'US');
        String result2 = PIIMaskingService.maskPII('ab@test.com', 'US');
        String result3 = PIIMaskingService.maskPII('abc@test.com', 'US');
        
        System.assertEquals('***@test.com', result1, 'Single char email should be fully masked');
        System.assertEquals('***@test.com', result2, 'Two char email should be fully masked');
        System.assertEquals('ab***@test.com', result3, 'Three+ char email should show first 2');
        
        Test.stopTest();
    }
}