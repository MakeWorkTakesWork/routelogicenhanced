/**
 * @description Test class for AIHealthCheckScheduler
 * @author RouteLogic Enhanced
 * @version 3.1.2
 */
@isTest
private class AIHealthCheckSchedulerTest {
    
    @testSetup
    static void setup() {
        // Create test configuration
        // Note: In production, this would be custom metadata which can't be created in tests
        // So we'll test with default behavior
        
        // Create test permission set
        PermissionSet ps;
        List<PermissionSet> existingPS = [
            SELECT Id FROM PermissionSet 
            WHERE Name = 'AI_Configuration_Manager' 
            LIMIT 1
        ];
        
        if (existingPS.isEmpty()) {
            ps = new PermissionSet(
                Name = 'AI_Configuration_Manager',
                Label = 'AI Configuration Manager'
            );
            insert ps;
        } else {
            ps = existingPS[0];
        }
        
        // Create and assign to current user
        try {
            insert new PermissionSetAssignment(
                AssigneeId = UserInfo.getUserId(),
                PermissionSetId = ps.Id
            );
        } catch (DmlException e) {
            // Assignment might already exist
        }
        
        // Create custom notification type
        // Note: This can't be created in test, will be mocked
    }
    
    @isTest
    static void testSchedulerExecution() {
        // Mock HTTP callouts
        Test.setMock(HttpCalloutMock.class, new MultiProviderHealthCheckMock());
        
        Test.startTest();
        
        // Create and execute scheduler
        AIHealthCheckScheduler scheduler = new AIHealthCheckScheduler();
        scheduler.execute(null);
        
        Test.stopTest();
        
        // Verify health checks were created
        List<AI_Provider_Health_Check__c> healthChecks = [
            SELECT Provider_Name__c, Status__c, Response_Time_Ms__c
            FROM AI_Provider_Health_Check__c
            WHERE CreatedDate = TODAY
        ];
        
        System.assert(!healthChecks.isEmpty(), 'Health checks should be created');
        
        // Verify metrics were created
        List<AI_System_Metric__c> metrics = [
            SELECT Metric_Type__c, Metric_Name__c, Metric_Value__c
            FROM AI_System_Metric__c
            WHERE Metric_Type__c = 'System Health'
            AND CreatedDate = TODAY
        ];
        
        System.assert(!metrics.isEmpty(), 'System health metrics should be created');
    }
    
    @isTest
    static void testSchedulerWithUnhealthyProviders() {
        // Mock unhealthy providers
        Test.setMock(HttpCalloutMock.class, new UnhealthyProviderMock());
        
        Test.startTest();
        
        AIHealthCheckScheduler scheduler = new AIHealthCheckScheduler();
        scheduler.execute(null);
        
        Test.stopTest();
        
        // Verify alerts were created
        List<AI_System_Alert__c> alerts = [
            SELECT Alert_Type__c, Severity__c, Provider_Name__c, Message__c
            FROM AI_System_Alert__c
            WHERE Alert_Type__c = 'Provider Health'
            AND CreatedDate = TODAY
        ];
        
        System.assert(!alerts.isEmpty(), 'Alerts should be created for unhealthy providers');
        
        Boolean hasCriticalAlert = false;
        for (AI_System_Alert__c alert : alerts) {
            if (alert.Severity__c == 'Critical') {
                hasCriticalAlert = true;
                break;
            }
        }
        
        System.assert(hasCriticalAlert, 'Should have at least one critical alert');
    }
    
    @isTest
    static void testSchedulerWithSlowProviders() {
        // Mock slow provider responses
        Test.setMock(HttpCalloutMock.class, new SlowProviderMock());
        
        Test.startTest();
        
        AIHealthCheckScheduler scheduler = new AIHealthCheckScheduler();
        scheduler.execute(null);
        
        Test.stopTest();
        
        // Verify performance alerts
        List<AI_System_Alert__c> alerts = [
            SELECT Alert_Type__c, Severity__c, Message__c
            FROM AI_System_Alert__c
            WHERE Alert_Type__c = 'Performance'
            AND CreatedDate = TODAY
        ];
        
        System.assert(!alerts.isEmpty(), 'Performance alerts should be created for slow providers');
        
        for (AI_System_Alert__c alert : alerts) {
            System.assert(alert.Message__c.contains('slowly'), 'Alert should mention slow response');
        }
    }
    
    @isTest
    static void testSchedulerError() {
        // Mock callout failure
        Test.setMock(HttpCalloutMock.class, new FailedCalloutMock());
        
        Test.startTest();
        
        AIHealthCheckScheduler scheduler = new AIHealthCheckScheduler();
        scheduler.execute(null);
        
        Test.stopTest();
        
        // Verify error alert was created
        List<AI_System_Alert__c> alerts = [
            SELECT Alert_Type__c, Severity__c, Message__c
            FROM AI_System_Alert__c
            WHERE Alert_Type__c = 'System Error'
            AND CreatedDate = TODAY
        ];
        
        System.assert(!alerts.isEmpty(), 'System error alert should be created');
    }
    
    @isTest
    static void testScheduleHealthCheck() {
        Test.startTest();
        
        String jobId = AIHealthCheckScheduler.scheduleHealthCheck('0 0 * * * ?');
        
        Test.stopTest();
        
        // Verify job was scheduled
        CronTrigger ct = [
            SELECT Id, CronExpression, State
            FROM CronTrigger
            WHERE Id = :jobId
        ];
        
        System.assertEquals('0 0 * * * ?', ct.CronExpression, 'Cron expression should match');
        System.assertNotEquals('DELETED', ct.State, 'Job should not be deleted');
    }
    
    @isTest
    static void testGetDefaultCronExpression() {
        String cron = AIHealthCheckScheduler.getDefaultCronExpression();
        
        System.assertEquals('0 0,15,30,45 * * * ?', cron, 'Should return every 15 minutes cron');
    }
    
    @isTest
    static void testConfigurationCheck() {
        // Test with no configuration (should default to running)
        Test.startTest();
        
        AIHealthCheckScheduler scheduler = new AIHealthCheckScheduler();
        scheduler.execute(null);
        
        Test.stopTest();
        
        // Should still execute with default behavior
        System.assert(true, 'Scheduler should execute without error');
    }
    
    /**
     * Mock for multiple healthy providers
     */
    public class MultiProviderHealthCheckMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"healthy","uptime":99.9}');
            res.setStatus('OK');
            return res;
        }
    }
    
    /**
     * Mock for unhealthy providers
     */
    public class UnhealthyProviderMock implements HttpCalloutMock {
        private Integer callCount = 0;
        
        public HTTPResponse respond(HTTPRequest req) {
            callCount++;
            
            HTTPResponse res = new HTTPResponse();
            
            // Make first provider unhealthy, second degraded
            if (callCount == 1) {
                res.setStatusCode(500);
                res.setBody('Internal Server Error');
                res.setStatus('Internal Server Error');
            } else {
                res.setStatusCode(400);
                res.setBody('Bad Request');
                res.setStatus('Bad Request');
            }
            
            return res;
        }
    }
    
    /**
     * Mock for slow provider responses
     */
    public class SlowProviderMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Note: In real scenario, we'd simulate actual delay
            // For testing, the service will check response time
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"healthy","responseTime":6000}');
            res.setStatus('OK');
            return res;
        }
    }
    
    /**
     * Mock for failed callouts
     */
    public class FailedCalloutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            throw new CalloutException('Connection timeout');
        }
    }
}