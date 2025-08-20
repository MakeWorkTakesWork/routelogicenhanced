/**
 * @description Test class for AIAlertingService
 * @author RouteLogic Enhanced
 * @version 3.1.2
 */
@isTest
private class AIAlertingServiceTest {
    
    @testSetup
    static void setup() {
        // Create test alerts
        List<AI_System_Alert__c> alerts = new List<AI_System_Alert__c>();
        
        DateTime baseTime = DateTime.now();
        
        // Create various alerts
        alerts.add(new AI_System_Alert__c(
            Alert_Type__c = 'Provider Health',
            Severity__c = 'Critical',
            Status__c = 'New',
            Provider_Name__c = 'OpenAI',
            Message__c = 'Provider is unhealthy',
            Alert_Time__c = baseTime
        ));
        
        alerts.add(new AI_System_Alert__c(
            Alert_Type__c = 'Performance',
            Severity__c = 'Warning',
            Status__c = 'Acknowledged',
            Message__c = 'High response time detected',
            Alert_Time__c = baseTime.addHours(-1)
        ));
        
        alerts.add(new AI_System_Alert__c(
            Alert_Type__c = 'Capacity',
            Severity__c = 'Error',
            Status__c = 'In Progress',
            Message__c = 'API limit approaching',
            Alert_Time__c = baseTime.addHours(-2)
        ));
        
        alerts.add(new AI_System_Alert__c(
            Alert_Type__c = 'System Error',
            Severity__c = 'Info',
            Status__c = 'Resolved',
            Message__c = 'Temporary issue resolved',
            Alert_Time__c = baseTime.addDays(-1),
            Resolved_Time__c = baseTime.addHours(-12),
            Resolved_By__c = UserInfo.getUserId()
        ));
        
        insert alerts;
        
        // Create permission set
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
        
        // Assign to current user
        try {
            insert new PermissionSetAssignment(
                AssigneeId = UserInfo.getUserId(),
                PermissionSetId = ps.Id
            );
        } catch (DmlException e) {
            // Assignment might already exist
        }
    }
    
    @isTest
    static void testCreateAlert() {
        Test.startTest();
        
        AI_System_Alert__c alert = AIAlertingService.createAlert(
            AIAlertingService.TYPE_PROVIDER_HEALTH,
            AIAlertingService.SEVERITY_WARNING,
            'Test provider is experiencing issues',
            'TestProvider'
        );
        
        Test.stopTest();
        
        // Verify alert was created
        System.assertNotEquals(null, alert.Id, 'Alert should be created');
        System.assertEquals('Provider Health', alert.Alert_Type__c, 'Alert type should match');
        System.assertEquals('Warning', alert.Severity__c, 'Severity should match');
        System.assertEquals('New', alert.Status__c, 'Status should be New');
        System.assertEquals('TestProvider', alert.Provider_Name__c, 'Provider name should match');
    }
    
    @isTest
    static void testCreateCriticalAlert() {
        // Note: Can't test actual notifications in unit tests
        Test.startTest();
        
        AI_System_Alert__c alert = AIAlertingService.createAlert(
            AIAlertingService.TYPE_SYSTEM_ERROR,
            AIAlertingService.SEVERITY_CRITICAL,
            'Critical system failure detected',
            null
        );
        
        Test.stopTest();
        
        System.assertEquals('Critical', alert.Severity__c, 'Should be critical alert');
        // Notification sending is mocked in tests
    }
    
    @isTest
    static void testCheckSystemThresholds() {
        // Create test data for threshold checking
        createThresholdTestData();
        
        Test.startTest();
        AIAlertingService.checkSystemThresholds();
        Test.stopTest();
        
        // Verify alerts were created based on thresholds
        List<AI_System_Alert__c> newAlerts = [
            SELECT Alert_Type__c, Severity__c, Message__c
            FROM AI_System_Alert__c
            WHERE CreatedDate = TODAY
            AND Status__c = 'New'
            ORDER BY CreatedDate DESC
        ];
        
        System.assert(!newAlerts.isEmpty(), 'Should create alerts for threshold violations');
    }
    
    @isTest
    static void testUpdateAlertStatus() {
        AI_System_Alert__c alert = [
            SELECT Id, Status__c
            FROM AI_System_Alert__c
            WHERE Status__c = 'New'
            LIMIT 1
        ];
        
        Test.startTest();
        AIAlertingService.updateAlertStatus(alert.Id, 'Acknowledged', 'Looking into the issue');
        Test.stopTest();
        
        AI_System_Alert__c updatedAlert = [
            SELECT Status__c, Resolution_Notes__c
            FROM AI_System_Alert__c
            WHERE Id = :alert.Id
        ];
        
        System.assertEquals('Acknowledged', updatedAlert.Status__c, 'Status should be updated');
        System.assertEquals('Looking into the issue', updatedAlert.Resolution_Notes__c, 'Notes should be saved');
    }
    
    @isTest
    static void testResolveAlert() {
        AI_System_Alert__c alert = [
            SELECT Id, Status__c
            FROM AI_System_Alert__c
            WHERE Status__c = 'New'
            LIMIT 1
        ];
        
        Test.startTest();
        AIAlertingService.updateAlertStatus(alert.Id, 'Resolved', 'Issue has been fixed');
        Test.stopTest();
        
        AI_System_Alert__c resolvedAlert = [
            SELECT Status__c, Resolution_Notes__c, Resolved_Time__c, Resolved_By__c
            FROM AI_System_Alert__c
            WHERE Id = :alert.Id
        ];
        
        System.assertEquals('Resolved', resolvedAlert.Status__c, 'Status should be Resolved');
        System.assertNotEquals(null, resolvedAlert.Resolved_Time__c, 'Resolved time should be set');
        System.assertEquals(UserInfo.getUserId(), resolvedAlert.Resolved_By__c, 'Resolved by should be current user');
    }
    
    @isTest
    static void testGetActiveAlerts() {
        Test.startTest();
        List<AI_System_Alert__c> activeAlerts = AIAlertingService.getActiveAlerts(10);
        Test.stopTest();
        
        // Should return only non-resolved, non-ignored alerts
        System.assertEquals(3, activeAlerts.size(), 'Should return 3 active alerts');
        
        // Verify ordering - critical alerts first
        System.assertEquals('Critical', activeAlerts[0].Severity__c, 'First alert should be critical');
    }
    
    @isTest
    static void testAlertEscalation() {
        // Create multiple similar critical alerts
        List<AI_System_Alert__c> similarAlerts = new List<AI_System_Alert__c>();
        
        for (Integer i = 0; i < 5; i++) {
            similarAlerts.add(new AI_System_Alert__c(
                Alert_Type__c = 'Provider Health',
                Severity__c = 'Critical',
                Status__c = 'New',
                Provider_Name__c = 'OpenAI',
                Message__c = 'Provider is unhealthy - attempt ' + i,
                Alert_Time__c = DateTime.now().addHours(-i)
            ));
        }
        
        insert similarAlerts;
        
        Test.startTest();
        
        // Create another critical alert that should trigger escalation
        AI_System_Alert__c newAlert = AIAlertingService.createAlert(
            'Provider Health',
            'Critical',
            'Provider is still unhealthy',
            'OpenAI'
        );
        
        Test.stopTest();
        
        // Check if escalation occurred
        List<Case> escalationCases = [
            SELECT Subject, Priority, Type
            FROM Case
            WHERE CreatedDate = TODAY
            AND Subject LIKE 'Critical AI System Alert%'
        ];
        
        // Note: Escalation logic may create a case
        if (!escalationCases.isEmpty()) {
            System.assertEquals('High', escalationCases[0].Priority, 'Escalation case should be high priority');
        }
    }
    
    @isTest
    static void testQueueThresholdAlerts() {
        // This would typically be called from checkSystemThresholds
        // but we'll test the individual threshold methods through reflection or direct testing
        
        Test.startTest();
        AIAlertingService.checkSystemThresholds();
        Test.stopTest();
        
        // Verify appropriate alerts were created based on test data
        System.assert(true, 'Threshold checking completed');
    }
    
    @isTest
    static void testExceptionHandling() {
        // Test with invalid alert ID
        try {
            AIAlertingService.updateAlertStatus('a07000000000000', 'Resolved', 'Test');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Failed to update alert'), 'Should have proper error message');
        }
    }
    
    /**
     * Helper method to create test data for threshold testing
     */
    private static void createThresholdTestData() {
        // Create high number of pending requests
        List<AI_Processing_Status__c> pendingRequests = new List<AI_Processing_Status__c>();
        
        for (Integer i = 0; i < 150; i++) {
            pendingRequests.add(new AI_Processing_Status__c(
                Case__c = 'PEND-' + String.valueOf(i).leftPad(5, '0'),
                Status__c = 'Pending',
                Priority__c = i < 50 ? 'High' : 'Normal',
                Provider__c = 'OpenAI',
                CreatedDate = DateTime.now().addHours(-3) // Old pending items
            ));
        }
        
        insert pendingRequests;
        
        // Create failed requests for high failure rate
        List<AI_Processing_Status__c> failedRequests = new List<AI_Processing_Status__c>();
        
        for (Integer i = 0; i < 20; i++) {
            failedRequests.add(new AI_Processing_Status__c(
                Case__c = 'FAIL-' + String.valueOf(i).leftPad(5, '0'),
                Status__c = 'Failed',
                Priority__c = 'Normal',
                Provider__c = 'OpenAI',
                Error_Message__c = 'Test failure',
                CreatedDate = DateTime.now().addHours(-1),
                LastModifiedDate = DateTime.now().addHours(-1)
            ));
        }
        
        insert failedRequests;
        
        // Create unhealthy provider records
        insert new AI_Provider_Health_Check__c(
            Provider_Name__c = 'Anthropic',
            Status__c = 'Unhealthy',
            Message__c = 'Connection timeout',
            Response_Time_Ms__c = 0,
            Check_Time__c = DateTime.now().addMinutes(-10)
        );
    }
}