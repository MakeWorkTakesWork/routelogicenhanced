/**
 * @description Test class for AISystemMonitoringService
 * @author RouteLogic Enhanced
 * @version 3.1.2
 */
@isTest
private class AISystemMonitoringServiceTest {
    
    @testSetup
    static void setup() {
        // Create test processing status records
        List<AI_Processing_Status__c> statusRecords = new List<AI_Processing_Status__c>();
        
        DateTime baseTime = DateTime.now();
        
        // Create various status records
        for (Integer i = 0; i < 20; i++) {
            String status;
            String priority = 'Normal';
            
            if (i < 5) {
                status = 'Pending';
                if (i < 2) priority = 'High';
            } else if (i < 8) {
                status = 'Processing';
            } else if (i < 15) {
                status = 'Completed';
            } else {
                status = 'Failed';
            }
            
            statusRecords.add(new AI_Processing_Status__c(
                Case__c = 'TEST-' + String.valueOf(i).leftPad(5, '0'),
                Status__c = status,
                Priority__c = priority,
                Provider__c = 'OpenAI',
                Processing_Duration_Ms__c = status == 'Completed' ? 1000 + (i * 100) : null,
                Error_Message__c = status == 'Failed' ? 'Test error ' + i : null,
                CreatedDate = baseTime.addDays(-i % 7),
                LastModifiedDate = baseTime.addHours(-i)
            ));
        }
        
        insert statusRecords;
        
        // Create health check records
        List<AI_Provider_Health_Check__c> healthChecks = new List<AI_Provider_Health_Check__c>();
        
        for (Integer i = 0; i < 10; i++) {
            healthChecks.add(new AI_Provider_Health_Check__c(
                Provider_Name__c = 'OpenAI',
                Status__c = i < 8 ? 'Healthy' : 'Degraded',
                Message__c = 'Test health check',
                Response_Time_Ms__c = 100 + (i * 10),
                Check_Time__c = baseTime.addHours(-i)
            ));
        }
        
        healthChecks.add(new AI_Provider_Health_Check__c(
            Provider_Name__c = 'Anthropic',
            Status__c = 'Healthy',
            Message__c = 'Test health check',
            Response_Time_Ms__c = 200,
            Check_Time__c = baseTime
        ));
        
        insert healthChecks;
        
        // Create test configuration overrides
        List<AI_Config_Override__c> configOverrides = new List<AI_Config_Override__c>();
        configOverrides.add(new AI_Config_Override__c(
            Setting_Name__c = 'Max_Batch_Size',
            Setting_Value__c = '50',
            Is_Active__c = true
        ));
        
        insert configOverrides;
        
        // Create test user with permission
        User testUser = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            LastName = 'Test',
            Email = 'test@example.com',
            Username = 'test@example.com.routelogic',
            CompanyName = 'TEST',
            Title = 'Test User',
            Alias = 'test',
            TimeZoneSidKey = 'America/Los_Angeles',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US'
        );
        insert testUser;
        
        // Create permission set if it doesn't exist
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
        
        // Assign permission
        insert new PermissionSetAssignment(
            AssigneeId = testUser.Id,
            PermissionSetId = ps.Id
        );
    }
    
    @isTest
    static void testGetSystemDiagnostics_Success() {
        User testUser = [SELECT Id FROM User WHERE Username = 'test@example.com.routelogic' LIMIT 1];
        
        System.runAs(testUser) {
            Test.startTest();
            AISystemMonitoringService.SystemDiagnostics diagnostics = 
                AISystemMonitoringService.getSystemDiagnostics();
            Test.stopTest();
            
            // Verify diagnostics data
            System.assertNotEquals(null, diagnostics, 'Diagnostics should not be null');
            System.assertNotEquals(null, diagnostics.queueMetrics, 'Queue metrics should not be null');
            System.assertNotEquals(null, diagnostics.providerHealth, 'Provider health should not be null');
            System.assertNotEquals(null, diagnostics.performanceMetrics, 'Performance metrics should not be null');
            System.assertNotEquals(null, diagnostics.configurationStatus, 'Configuration status should not be null');
            System.assertNotEquals(null, diagnostics.systemLimits, 'System limits should not be null');
            System.assertNotEquals(null, diagnostics.overallHealth, 'Overall health should not be null');
            
            // Verify queue metrics
            System.assertEquals(5, diagnostics.queueMetrics.pendingCount, 'Should have 5 pending');
            System.assertEquals(3, diagnostics.queueMetrics.processingCount, 'Should have 3 processing');
            System.assertEquals(5, diagnostics.queueMetrics.failedCount, 'Should have 5 failed');
            System.assertEquals(2, diagnostics.queueMetrics.highPriorityPending, 'Should have 2 high priority pending');
        }
    }
    
    @isTest
    static void testGetSystemDiagnostics_NoPermission() {
        // Create user without permission
        User unprivilegedUser = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            LastName = 'NoAccess',
            Email = 'noaccess@example.com',
            Username = 'noaccess@example.com.routelogic',
            CompanyName = 'TEST',
            Title = 'No Access User',
            Alias = 'noac',
            TimeZoneSidKey = 'America/Los_Angeles',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US'
        );
        insert unprivilegedUser;
        
        System.runAs(unprivilegedUser) {
            Test.startTest();
            AISystemMonitoringService.SystemDiagnostics diagnostics = 
                AISystemMonitoringService.getSystemDiagnostics();
            Test.stopTest();
            
            // Should return diagnostics with error
            System.assertNotEquals(null, diagnostics, 'Diagnostics should not be null');
            System.assertNotEquals(null, diagnostics.errorMessage, 'Should have error message');
            System.assert(diagnostics.errorMessage.contains('permission'), 'Error should mention permission');
        }
    }
    
    @isTest
    static void testQueueMetrics() {
        User testUser = [SELECT Id FROM User WHERE Username = 'test@example.com.routelogic' LIMIT 1];
        
        System.runAs(testUser) {
            // Create an old pending record
            AI_Processing_Status__c oldPending = new AI_Processing_Status__c(
                Case__c = 'OLD-00001',
                Status__c = 'Pending',
                Priority__c = 'Normal',
                Provider__c = 'OpenAI',
                CreatedDate = DateTime.now().addHours(-3)
            );
            insert oldPending;
            
            Test.startTest();
            AISystemMonitoringService.SystemDiagnostics diagnostics = 
                AISystemMonitoringService.getSystemDiagnostics();
            Test.stopTest();
            
            // Verify old pending age is detected
            System.assert(diagnostics.queueMetrics.oldestPendingAge > 0, 'Should have oldest pending age');
            System.assert(diagnostics.queueMetrics.averageProcessingTime > 0, 'Should have average processing time');
        }
    }
    
    @isTest
    static void testProviderHealthSummary() {
        User testUser = [SELECT Id FROM User WHERE Username = 'test@example.com.routelogic' LIMIT 1];
        
        System.runAs(testUser) {
            Test.startTest();
            AISystemMonitoringService.SystemDiagnostics diagnostics = 
                AISystemMonitoringService.getSystemDiagnostics();
            Test.stopTest();
            
            // Verify provider health data
            System.assert(!diagnostics.providerHealth.isEmpty(), 'Should have provider health data');
            
            AISystemMonitoringService.ProviderHealthSummary openAIHealth = 
                diagnostics.providerHealth.get('OpenAI');
            
            if (openAIHealth != null) {
                System.assertNotEquals(null, openAIHealth.status, 'Should have status');
                System.assertNotEquals(null, openAIHealth.lastCheckTime, 'Should have last check time');
                System.assert(openAIHealth.uptimePercentage >= 0, 'Should have uptime percentage');
            }
        }
    }
    
    @isTest
    static void testPerformanceMetrics() {
        User testUser = [SELECT Id FROM User WHERE Username = 'test@example.com.routelogic' LIMIT 1];
        
        System.runAs(testUser) {
            Test.startTest();
            AISystemMonitoringService.SystemDiagnostics diagnostics = 
                AISystemMonitoringService.getSystemDiagnostics();
            Test.stopTest();
            
            // Verify performance metrics
            AISystemMonitoringService.PerformanceMetrics perfMetrics = diagnostics.performanceMetrics;
            
            System.assert(perfMetrics.successRate >= 0 && perfMetrics.successRate <= 100, 
                'Success rate should be between 0 and 100');
            System.assert(perfMetrics.throughputPerHour >= 0, 'Throughput should be non-negative');
            System.assertNotEquals(null, perfMetrics.averageResponseTimeByProvider, 
                'Should have response time map');
        }
    }
    
    @isTest
    static void testConfigurationStatus() {
        User testUser = [SELECT Id FROM User WHERE Username = 'test@example.com.routelogic' LIMIT 1];
        
        System.runAs(testUser) {
            Test.startTest();
            AISystemMonitoringService.SystemDiagnostics diagnostics = 
                AISystemMonitoringService.getSystemDiagnostics();
            Test.stopTest();
            
            // Verify configuration status
            AISystemMonitoringService.ConfigurationStatus configStatus = diagnostics.configurationStatus;
            
            System.assertNotEquals(null, configStatus.isValid, 'Should have valid flag');
            System.assert(configStatus.errorCount >= 0, 'Error count should be non-negative');
            System.assert(configStatus.warningCount >= 0, 'Warning count should be non-negative');
            System.assertNotEquals(null, configStatus.lastValidated, 'Should have last validated time');
        }
    }
    
    @isTest
    static void testSystemLimits() {
        User testUser = [SELECT Id FROM User WHERE Username = 'test@example.com.routelogic' LIMIT 1];
        
        System.runAs(testUser) {
            Test.startTest();
            AISystemMonitoringService.SystemDiagnostics diagnostics = 
                AISystemMonitoringService.getSystemDiagnostics();
            Test.stopTest();
            
            // Verify system limits
            AISystemMonitoringService.SystemLimits limits = diagnostics.systemLimits;
            
            System.assert(limits.apiCallsUsed >= 0, 'API calls used should be non-negative');
            System.assert(limits.apiCallsLimit > 0, 'API calls limit should be positive');
            System.assert(limits.apiCallsPercentage >= 0 && limits.apiCallsPercentage <= 100, 
                'API percentage should be between 0 and 100');
            
            System.assert(limits.storageUsedMB >= 0, 'Storage used should be non-negative');
            System.assert(limits.storageLimitMB > 0, 'Storage limit should be positive');
            
            System.assert(limits.platformEventsUsed >= 0, 'Platform events used should be non-negative');
            System.assert(limits.platformEventsLimit > 0, 'Platform events limit should be positive');
        }
    }
    
    @isTest
    static void testRecentErrors() {
        User testUser = [SELECT Id FROM User WHERE Username = 'test@example.com.routelogic' LIMIT 1];
        
        System.runAs(testUser) {
            Test.startTest();
            AISystemMonitoringService.SystemDiagnostics diagnostics = 
                AISystemMonitoringService.getSystemDiagnostics();
            Test.stopTest();
            
            // Verify recent errors
            System.assertNotEquals(null, diagnostics.recentErrors, 'Should have recent errors list');
            System.assert(diagnostics.recentErrors.size() > 0, 'Should have some errors from test data');
            
            for (AISystemMonitoringService.ErrorEvent error : diagnostics.recentErrors) {
                System.assertNotEquals(null, error.timestamp, 'Error should have timestamp');
                System.assertNotEquals(null, error.errorType, 'Error should have type');
                System.assertNotEquals(null, error.message, 'Error should have message');
            }
        }
    }
    
    @isTest
    static void testOverallHealthCalculation() {
        User testUser = [SELECT Id FROM User WHERE Username = 'test@example.com.routelogic' LIMIT 1];
        
        System.runAs(testUser) {
            Test.startTest();
            AISystemMonitoringService.SystemDiagnostics diagnostics = 
                AISystemMonitoringService.getSystemDiagnostics();
            Test.stopTest();
            
            // Verify overall health calculation
            System.assert(diagnostics.overallHealth >= 0 && diagnostics.overallHealth <= 100, 
                'Overall health should be between 0 and 100');
            
            // With test data having some failures and issues, health should be less than 100
            System.assert(diagnostics.overallHealth < 100, 
                'Overall health should be less than 100 with test issues');
        }
    }
    
    @isTest
    static void testEmptyMetrics() {
        User testUser = [SELECT Id FROM User WHERE Username = 'test@example.com.routelogic' LIMIT 1];
        
        // Delete all test data
        delete [SELECT Id FROM AI_Processing_Status__c];
        delete [SELECT Id FROM AI_Provider_Health_Check__c];
        
        System.runAs(testUser) {
            Test.startTest();
            AISystemMonitoringService.SystemDiagnostics diagnostics = 
                AISystemMonitoringService.getSystemDiagnostics();
            Test.stopTest();
            
            // Should handle empty data gracefully
            System.assertNotEquals(null, diagnostics, 'Diagnostics should not be null');
            System.assertEquals(0, diagnostics.queueMetrics.pendingCount, 'Should have 0 pending');
            System.assertEquals(100.0, diagnostics.performanceMetrics.successRate, 
                'Success rate should default to 100 with no data');
        }
    }
}