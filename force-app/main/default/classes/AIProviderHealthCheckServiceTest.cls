/**
 * @description Test class for AIProviderHealthCheckService
 * @author RouteLogic Enhanced
 * @version 3.1.2
 */
@isTest
private class AIProviderHealthCheckServiceTest {
    
    @testSetup
    static void setup() {
        // Create test health check records
        List<AI_Provider_Health_Check__c> healthChecks = new List<AI_Provider_Health_Check__c>();
        
        DateTime baseTime = DateTime.now();
        
        // Create health history for OpenAI
        for (Integer i = 0; i < 10; i++) {
            healthChecks.add(new AI_Provider_Health_Check__c(
                Provider_Name__c = 'OpenAI',
                Status__c = i < 8 ? 'Healthy' : 'Degraded',
                Message__c = 'Test health check',
                Response_Time_Ms__c = 100 + (i * 10),
                Check_Time__c = baseTime.addHours(-i)
            ));
        }
        
        // Create health history for Anthropic
        for (Integer i = 0; i < 5; i++) {
            healthChecks.add(new AI_Provider_Health_Check__c(
                Provider_Name__c = 'Anthropic',
                Status__c = 'Healthy',
                Message__c = 'Test health check',
                Response_Time_Ms__c = 200,
                Check_Time__c = baseTime.addHours(-i)
            ));
        }
        
        insert healthChecks;
    }
    
    @isTest
    static void testCheckAllProviders() {
        // Create mock HTTP callout
        Test.setMock(HttpCalloutMock.class, new HealthCheckHttpMock(200, 'Healthy'));
        
        Test.startTest();
        Map<String, AIProviderHealthCheckService.HealthCheckResult> results = 
            AIProviderHealthCheckService.checkAllProviders();
        Test.stopTest();
        
        // Verify results
        System.assertNotEquals(null, results, 'Results should not be null');
        
        // Since we're mocking, we should get results for active providers
        for (String providerName : results.keySet()) {
            AIProviderHealthCheckService.HealthCheckResult result = results.get(providerName);
            System.assertEquals('Healthy', result.status, 'Provider should be healthy');
            System.assertNotEquals(null, result.lastChecked, 'Last checked should be set');
        }
    }
    
    @isTest
    static void testCheckProviderByName() {
        Test.setMock(HttpCalloutMock.class, new HealthCheckHttpMock(200, 'Healthy'));
        
        Test.startTest();
        AIProviderHealthCheckService.HealthCheckResult result = 
            AIProviderHealthCheckService.checkProviderByName('OpenAI');
        Test.stopTest();
        
        System.assertEquals('OpenAI', result.providerName, 'Provider name should match');
        System.assertEquals('Healthy', result.status, 'Status should be healthy');
        System.assertNotEquals(null, result.responseTimeMs, 'Response time should be recorded');
    }
    
    @isTest
    static void testCheckProviderByName_NotFound() {
        Test.startTest();
        AIProviderHealthCheckService.HealthCheckResult result = 
            AIProviderHealthCheckService.checkProviderByName('NonExistentProvider');
        Test.stopTest();
        
        System.assertEquals('NonExistentProvider', result.providerName, 'Provider name should match');
        System.assertEquals('Unknown', result.status, 'Status should be unknown');
        System.assertEquals('Provider not found or inactive', result.message, 'Message should indicate not found');
    }
    
    @isTest
    static void testUnhealthyProvider() {
        Test.setMock(HttpCalloutMock.class, new HealthCheckHttpMock(500, 'Server Error'));
        
        Test.startTest();
        AIProviderHealthCheckService.HealthCheckResult result = 
            AIProviderHealthCheckService.checkProviderByName('OpenAI');
        Test.stopTest();
        
        System.assertEquals('Unhealthy', result.status, 'Status should be unhealthy for 500 error');
        System.assert(result.message.contains('500'), 'Message should contain status code');
    }
    
    @isTest
    static void testDegradedProvider() {
        Test.setMock(HttpCalloutMock.class, new HealthCheckHttpMock(400, 'Bad Request'));
        
        Test.startTest();
        AIProviderHealthCheckService.HealthCheckResult result = 
            AIProviderHealthCheckService.checkProviderByName('OpenAI');
        Test.stopTest();
        
        System.assertEquals('Degraded', result.status, 'Status should be degraded for 400 error');
    }
    
    @isTest
    static void testSlowResponse() {
        Test.setMock(HttpCalloutMock.class, new HealthCheckHttpMock(200, 'Healthy', 6000));
        
        Test.startTest();
        AIProviderHealthCheckService.HealthCheckResult result = 
            AIProviderHealthCheckService.checkProviderByName('OpenAI');
        Test.stopTest();
        
        System.assertEquals('Degraded', result.status, 'Status should be degraded for slow response');
        System.assert(result.message.contains('slowly'), 'Message should indicate slow response');
    }
    
    @isTest
    static void testConnectionFailure() {
        Test.setMock(HttpCalloutMock.class, new HealthCheckHttpMock(0, 'Connection Failed'));
        
        Test.startTest();
        AIProviderHealthCheckService.HealthCheckResult result = 
            AIProviderHealthCheckService.checkProviderByName('OpenAI');
        Test.stopTest();
        
        System.assertEquals('Unhealthy', result.status, 'Status should be unhealthy for connection failure');
        System.assert(result.message.contains('Failed to connect'), 'Message should indicate connection failure');
    }
    
    @isTest
    static void testStoreHealthCheckResults() {
        Map<String, AIProviderHealthCheckService.HealthCheckResult> results = 
            new Map<String, AIProviderHealthCheckService.HealthCheckResult>();
        
        results.put('TestProvider', new AIProviderHealthCheckService.HealthCheckResult(
            'TestProvider', 'Healthy', 'Test message', 100
        ));
        
        Test.startTest();
        AIProviderHealthCheckService.storeHealthCheckResults(results);
        Test.stopTest();
        
        List<AI_Provider_Health_Check__c> checks = [
            SELECT Provider_Name__c, Status__c, Message__c, Response_Time_Ms__c
            FROM AI_Provider_Health_Check__c
            WHERE Provider_Name__c = 'TestProvider'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        System.assertEquals(1, checks.size(), 'Should create health check record');
        System.assertEquals('Healthy', checks[0].Status__c, 'Status should match');
        System.assertEquals('Test message', checks[0].Message__c, 'Message should match');
        System.assertEquals(100, checks[0].Response_Time_Ms__c, 'Response time should match');
    }
    
    @isTest
    static void testGetHealthHistory() {
        Test.startTest();
        List<AI_Provider_Health_Check__c> history = 
            AIProviderHealthCheckService.getHealthHistory('OpenAI', 5);
        Test.stopTest();
        
        System.assertEquals(5, history.size(), 'Should return requested number of records');
        System.assertEquals('OpenAI', history[0].Provider_Name__c, 'Provider name should match');
    }
    
    @isTest
    static void testCalculateUptime() {
        Test.startTest();
        Decimal uptime = AIProviderHealthCheckService.calculateUptime('OpenAI', 24);
        Test.stopTest();
        
        // Based on test data: 8 healthy out of 10 total = 80%
        System.assertEquals(80.0, uptime, 'Uptime should be 80%');
    }
    
    @isTest
    static void testCalculateUptime_NoData() {
        Test.startTest();
        Decimal uptime = AIProviderHealthCheckService.calculateUptime('UnknownProvider', 24);
        Test.stopTest();
        
        System.assertEquals(100.0, uptime, 'Uptime should be 100% when no data');
    }
    
    @isTest
    static void testHealthCheckWithAdditionalInfo() {
        // Mock response with JSON body
        String jsonBody = '{"status":"ok","version":"1.0","uptime":99.9}';
        Test.setMock(HttpCalloutMock.class, new HealthCheckHttpMock(200, jsonBody));
        
        Test.startTest();
        AIProviderHealthCheckService.HealthCheckResult result = 
            AIProviderHealthCheckService.checkProviderByName('OpenAI');
        Test.stopTest();
        
        System.assertEquals('Healthy', result.status, 'Status should be healthy');
        System.assertNotEquals(null, result.additionalInfo, 'Additional info should be parsed');
        System.assertEquals('ok', result.additionalInfo.get('status'), 'Status in additional info should match');
    }
    
    /**
     * Mock HTTP callout class for health check tests
     */
    public class HealthCheckHttpMock implements HttpCalloutMock {
        private Integer statusCode;
        private String body;
        private Integer responseTime;
        
        public HealthCheckHttpMock(Integer statusCode, String body) {
            this(statusCode, body, 100);
        }
        
        public HealthCheckHttpMock(Integer statusCode, String body, Integer responseTime) {
            this.statusCode = statusCode;
            this.body = body;
            this.responseTime = responseTime;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            // Simulate connection failure
            if (statusCode == 0) {
                throw new CalloutException('Failed to connect to provider');
            }
            
            // Simulate slow response
            if (responseTime > 5000) {
                // In real scenario, this would be actual delay
                // For testing, we'll handle this in the service
            }
            
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            res.setStatus(getStatusMessage(statusCode));
            
            return res;
        }
        
        private String getStatusMessage(Integer code) {
            Map<Integer, String> statusMessages = new Map<Integer, String>{
                200 => 'OK',
                400 => 'Bad Request',
                401 => 'Unauthorized',
                403 => 'Forbidden',
                404 => 'Not Found',
                500 => 'Internal Server Error',
                503 => 'Service Unavailable'
            };
            
            return statusMessages.containsKey(code) ? statusMessages.get(code) : 'Unknown';
        }
    }
}