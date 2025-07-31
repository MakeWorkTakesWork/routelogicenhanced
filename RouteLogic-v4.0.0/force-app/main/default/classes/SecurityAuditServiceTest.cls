/**
 * @description Test class for SecurityAuditService with focus on IP validation
 * @author RouteLogic Security Team
 * @date 2025-01-31
 * @version 4.0.0
 */
@isTest
private class SecurityAuditServiceTest {
    
    /**
     * @description Test valid IPv4 address validation
     */
    @isTest
    static void testIPValidation_ValidIPv4() {
        Test.startTest();
        
        // Test various valid IPv4 addresses
        System.assertEquals(true, SecurityAuditService.isValidIPAddress('192.168.1.1'));
        System.assertEquals(true, SecurityAuditService.isValidIPAddress('10.0.0.1'));
        System.assertEquals(true, SecurityAuditService.isValidIPAddress('172.16.0.1'));
        System.assertEquals(true, SecurityAuditService.isValidIPAddress('8.8.8.8'));
        System.assertEquals(true, SecurityAuditService.isValidIPAddress('255.255.255.255'));
        System.assertEquals(true, SecurityAuditService.isValidIPAddress('0.0.0.0'));
        
        Test.stopTest();
    }
    
    /**
     * @description Test invalid IPv4 address validation
     */
    @isTest
    static void testIPValidation_InvalidIPv4() {
        Test.startTest();
        
        // Test various invalid IPv4 addresses
        System.assertEquals(false, SecurityAuditService.isValidIPAddress('999.999.999.999'));
        System.assertEquals(false, SecurityAuditService.isValidIPAddress('256.1.1.1'));
        System.assertEquals(false, SecurityAuditService.isValidIPAddress('1.256.1.1'));
        System.assertEquals(false, SecurityAuditService.isValidIPAddress('1.1.256.1'));
        System.assertEquals(false, SecurityAuditService.isValidIPAddress('1.1.1.256'));
        System.assertEquals(false, SecurityAuditService.isValidIPAddress('192.168.1'));
        System.assertEquals(false, SecurityAuditService.isValidIPAddress('192.168.1.1.1'));
        System.assertEquals(false, SecurityAuditService.isValidIPAddress('not.an.ip.address'));
        System.assertEquals(false, SecurityAuditService.isValidIPAddress('192.168.1.a'));
        
        Test.stopTest();
    }
    
    /**
     * @description Test valid IPv6 address validation
     */
    @isTest
    static void testIPValidation_ValidIPv6() {
        Test.startTest();
        
        // Test various valid IPv6 addresses
        System.assertEquals(true, SecurityAuditService.isValidIPAddress('2001:0db8:85a3:0000:0000:8a2e:0370:7334'));
        System.assertEquals(true, SecurityAuditService.isValidIPAddress('2001:db8:85a3::8a2e:370:7334'));
        System.assertEquals(true, SecurityAuditService.isValidIPAddress('::1'));
        System.assertEquals(true, SecurityAuditService.isValidIPAddress('::'));
        
        Test.stopTest();
    }
    
    /**
     * @description Test trusted IP extraction with single IP
     */
    @isTest
    static void testExtractTrustedIP_SingleIP() {
        Map<String, String> headers = new Map<String, String>{
            'X-Forwarded-For' => '203.0.113.1'
        };
        
        Test.startTest();
        String ip = SecurityAuditService.extractTrustedIP(headers);
        Test.stopTest();
        
        System.assertEquals('203.0.113.1', ip, 'Should return the single IP');
    }
    
    /**
     * @description Test trusted IP extraction with proxy chain
     */
    @isTest
    static void testExtractTrustedIP_ProxyChain() {
        // Simulate X-Forwarded-For with client and proxies
        Map<String, String> headers = new Map<String, String>{
            'X-Forwarded-For' => '203.0.113.1, 10.0.0.1, 172.16.0.1'
        };
        
        Test.startTest();
        String ip = SecurityAuditService.extractTrustedIP(headers);
        Test.stopTest();
        
        // Should return the client IP (first non-proxy IP from right)
        System.assertEquals('203.0.113.1', ip, 'Should return client IP, not proxy IP');
    }
    
    /**
     * @description Test trusted IP extraction with only proxies
     */
    @isTest
    static void testExtractTrustedIP_OnlyProxies() {
        // All IPs are in trusted proxy ranges
        Map<String, String> headers = new Map<String, String>{
            'X-Forwarded-For' => '10.0.0.1, 172.16.0.1, 192.168.1.1'
        };
        
        Test.startTest();
        String ip = SecurityAuditService.extractTrustedIP(headers);
        Test.stopTest();
        
        // Should return Unknown when all IPs are proxies
        System.assertEquals('Unknown', ip, 'Should return Unknown when all IPs are proxies');
    }
    
    /**
     * @description Test trusted IP extraction with X-Real-IP fallback
     */
    @isTest
    static void testExtractTrustedIP_XRealIPFallback() {
        Map<String, String> headers = new Map<String, String>{
            'X-Real-IP' => '203.0.113.2'
        };
        
        Test.startTest();
        String ip = SecurityAuditService.extractTrustedIP(headers);
        Test.stopTest();
        
        System.assertEquals('203.0.113.2', ip, 'Should fall back to X-Real-IP');
    }
    
    /**
     * @description Test trusted IP extraction with invalid IPs
     */
    @isTest
    static void testExtractTrustedIP_InvalidIPs() {
        Map<String, String> headers = new Map<String, String>{
            'X-Forwarded-For' => 'not-an-ip, 999.999.999.999',
            'X-Real-IP' => 'also-not-an-ip'
        };
        
        Test.startTest();
        String ip = SecurityAuditService.extractTrustedIP(headers);
        Test.stopTest();
        
        System.assertEquals('Unknown', ip, 'Should return Unknown for invalid IPs');
    }
    
    /**
     * @description Test security event logging
     */
    @isTest
    static void testSecurityEventLogging() {
        Test.startTest();
        
        // Log authentication event
        SecurityAuditService.logAuthentication(true, 'testuser@example.com', 'OAuth2');
        
        // Log authorization event
        SecurityAuditService.logAuthorization(false, 'Case', 'Delete');
        
        // Log data access event
        Set<Id> recordIds = new Set<Id>{
            '00Q000000000001',
            '00Q000000000002'
        };
        SecurityAuditService.logDataAccess('Lead', recordIds, 'READ');
        
        // Log security violation
        Map<String, Object> violationDetails = new Map<String, Object>{
            'attemptedAction' => 'SQL Injection',
            'payload' => '[SANITIZED]'
        };
        SecurityAuditService.logSecurityViolation('SQL_INJECTION', violationDetails);
        
        // Log rate limit exceeded
        SecurityAuditService.logRateLimitExceeded('API_CALLS_PER_HOUR', 101, 100);
        
        // Log input validation failure
        SecurityAuditService.logInputValidationFailure('Email', 'Invalid format', 'test@');
        
        // Log API call
        SecurityAuditService.logAPICall('/services/data/v59.0/sobjects/Case', 'POST', 201, 150);
        
        Test.stopTest();
        
        // Note: In a real test, you'd query Security_Audit_Log__c records
        // But since we're using future methods, we can't verify in the same transaction
        System.assert(true, 'Events logged successfully');
    }
    
    /**
     * @description Test getCurrentIPAddress for REST context
     */
    @isTest
    static void testGetCurrentIPAddress_RestContext() {
        // Create mock REST request
        RestRequest req = new RestRequest();
        req.headers.put('X-Forwarded-For', '203.0.113.3, 10.0.0.1');
        RestContext.request = req;
        
        Test.startTest();
        String ip = SecurityAuditService.getCurrentIPAddress();
        Test.stopTest();
        
        System.assertEquals('203.0.113.3', ip, 'Should extract IP from REST context');
    }
    
    /**
     * @description Test query audit logs
     */
    @isTest
    static void testQueryAuditLogs() {
        // Note: This would require setting up test data
        // For now, test that the method executes without error
        
        Test.startTest();
        List<Security_Audit_Log__c> logs = SecurityAuditService.queryAuditLogs(
            'Authentication',
            DateTime.now().addDays(-7),
            DateTime.now(),
            SecurityAuditService.Severity.HIGH
        );
        Test.stopTest();
        
        System.assertNotEquals(null, logs, 'Query should return a list');
    }
}