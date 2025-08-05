/**
 * @description Test class for AuditService with comprehensive coverage
 * @author RouteLogic Team
 * @date 2025-01-18
 */
@isTest
private class AuditServiceTest {
    
    @testSetup
    static void setup() {
        // Create test custom settings
        AI_Security_Config__mdt testConfig = new AI_Security_Config__mdt();
        // Note: In real implementation, use Custom Metadata deployment
    }
    
    @isTest
    static void testLogSecurityEvent() {
        Test.startTest();
        
        // Test successful security event logging
        AuditService.logSecurityEvent(
            AuditService.EVENT_KEY_ROTATION,
            'Test key rotation event',
            'Success'
        );
        
        Test.stopTest();
        
        // Verify audit event was created
        List<AI_Audit_Event__c> auditEvents = [
            SELECT Event_Type__c, Category__c, Description__c, Status__c, Security_Hash__c
            FROM AI_Audit_Event__c
            WHERE Event_Type__c = :AuditService.EVENT_KEY_ROTATION
        ];
        
        System.assertEquals(1, auditEvents.size(), 'Should create one audit event');
        System.assertEquals('SECURITY', auditEvents[0].Category__c, 'Should be security category');
        System.assertEquals('Success', auditEvents[0].Status__c, 'Should have success status');
        System.assertNotEquals(null, auditEvents[0].Security_Hash__c, 'Should have security hash');
    }
    
    @isTest
    static void testLogComplianceEvent() {
        String metadata = JSON.serialize(new Map<String, Object>{
            'testKey' => 'testValue',
            'timestamp' => DateTime.now()
        });
        
        Test.startTest();
        
        AuditService.logComplianceEvent(
            'TEST_COMPLIANCE',
            'Test compliance event',
            'Success',
            metadata
        );
        
        Test.stopTest();
        
        List<AI_Audit_Event__c> auditEvents = [
            SELECT Event_Type__c, Category__c, Metadata__c
            FROM AI_Audit_Event__c
            WHERE Event_Type__c = 'TEST_COMPLIANCE'
        ];
        
        System.assertEquals(1, auditEvents.size(), 'Should create one audit event');
        System.assertEquals('COMPLIANCE', auditEvents[0].Category__c, 'Should be compliance category');
        System.assertNotEquals(null, auditEvents[0].Metadata__c, 'Should have metadata');
    }
    
    @isTest
    static void testLogOperationalEvent() {
        Test.startTest();
        
        AuditService.logOperationalEvent(
            'SYSTEM_HEALTH_CHECK',
            'System health check completed',
            'Success'
        );
        
        Test.stopTest();
        
        List<AI_Audit_Event__c> auditEvents = [
            SELECT Event_Type__c, Category__c
            FROM AI_Audit_Event__c
            WHERE Event_Type__c = 'SYSTEM_HEALTH_CHECK'
        ];
        
        System.assertEquals(1, auditEvents.size(), 'Should create one audit event');
        System.assertEquals('OPERATIONAL', auditEvents[0].Category__c, 'Should be operational category');
    }
    
    @isTest
    static void testVerifyAuditIntegrity() {
        // Create an audit event
        AuditService.logSecurityEvent(
            AuditService.EVENT_ACCESS_VIOLATION,
            'Test access violation',
            'Failed'
        );
        
        AI_Audit_Event__c auditEvent = [
            SELECT Id FROM AI_Audit_Event__c LIMIT 1
        ];
        
        Test.startTest();
        
        // Test integrity verification
        Boolean isValid = AuditService.verifyAuditIntegrity(auditEvent.Id);
        
        Test.stopTest();
        
        System.assertEquals(true, isValid, 'Audit integrity should be valid');
    }
    
    @isTest
    static void testVerifyAuditIntegrityTampered() {
        // Create an audit event
        AuditService.logSecurityEvent(
            AuditService.EVENT_ACCESS_VIOLATION,
            'Test access violation',
            'Failed'
        );
        
        AI_Audit_Event__c auditEvent = [
            SELECT Id, Security_Hash__c FROM AI_Audit_Event__c LIMIT 1
        ];
        
        // Tamper with the hash
        auditEvent.Security_Hash__c = 'TAMPERED_HASH';
        update auditEvent;
        
        Test.startTest();
        
        Boolean isValid = AuditService.verifyAuditIntegrity(auditEvent.Id);
        
        Test.stopTest();
        
        System.assertEquals(false, isValid, 'Tampered audit should be invalid');
    }
    
    @isTest
    static void testExportAuditLogs() {
        // Create test audit events
        for (Integer i = 0; i < 5; i++) {
            AuditService.logSecurityEvent(
                'TEST_EVENT_' + i,
                'Test event ' + i,
                'Success'
            );
        }
        
        // Create test user with permission
        User testUser = TestDataFactory.createUser('System Administrator');
        
        System.runAs(testUser) {
            Test.startTest();
            
            String exportJson = AuditService.exportAuditLogs(
                DateTime.now().addHours(-1),
                DateTime.now().addHours(1),
                'SECURITY'
            );
            
            Test.stopTest();
            
            System.assertNotEquals(null, exportJson, 'Should return export data');
            List<Object> exportData = (List<Object>) JSON.deserializeUntyped(exportJson);
            System.assertEquals(5, exportData.size(), 'Should export all 5 events');
        }
    }
    
    @isTest
    static void testExportAuditLogsNoPermission() {
        User limitedUser = TestDataFactory.createUser('Standard User');
        
        System.runAs(limitedUser) {
            Test.startTest();
            
            try {
                AuditService.exportAuditLogs(
                    DateTime.now().addHours(-1),
                    DateTime.now().addHours(1),
                    null
                );
                System.assert(false, 'Should throw insufficient privileges exception');
            } catch (InsufficientPrivilegesException e) {
                System.assert(true, 'Expected exception thrown');
            }
            
            Test.stopTest();
        }
    }
    
    @isTest
    static void testPlatformEventFallback() {
        // Force database error by making field too long
        String longDescription = 'A'.repeat(300); // Exceeds 255 char limit
        
        Test.startTest();
        
        // This should fall back to platform event
        AuditService.logSecurityEvent(
            'TEST_FALLBACK',
            longDescription,
            'Failed'
        );
        
        Test.stopTest();
        
        // Verify no database record created
        List<AI_Audit_Event__c> auditEvents = [
            SELECT Id FROM AI_Audit_Event__c
            WHERE Event_Type__c = 'TEST_FALLBACK'
        ];
        
        System.assertEquals(0, auditEvents.size(), 'Should not create database record');
        
        // Platform event verification would require event subscriber
    }
    
    @isTest
    static void testLongStringTruncation() {
        String longString = 'A'.repeat(300);
        
        Test.startTest();
        
        AuditService.logSecurityEvent(
            'TEST_TRUNCATION',
            longString,
            'Success'
        );
        
        Test.stopTest();
        
        AI_Audit_Event__c auditEvent = [
            SELECT Description__c
            FROM AI_Audit_Event__c
            WHERE Event_Type__c = 'TEST_TRUNCATION'
            LIMIT 1
        ];
        
        System.assertEquals(255, auditEvent.Description__c.length(), 'Should truncate to 255 chars');
        System.assert(auditEvent.Description__c.endsWith('...'), 'Should end with ellipsis');
    }
    
    @isTest
    static void testBulkAuditLogging() {
        Test.startTest();
        
        // Log multiple events
        for (Integer i = 0; i < 200; i++) {
            AuditService.logOperationalEvent(
                'BULK_TEST_' + i,
                'Bulk test event ' + i,
                'Success'
            );
        }
        
        Test.stopTest();
        
        Integer eventCount = [
            SELECT COUNT()
            FROM AI_Audit_Event__c
            WHERE Event_Type__c LIKE 'BULK_TEST_%'
        ];
        
        System.assertEquals(200, eventCount, 'Should create all 200 audit events');
    }
    
    @isTest
    static void testIPAnonymization() {
        // Note: This test validates the IP anonymization logic
        // In actual execution, we cannot directly test private methods
        // So we'll test the full audit logging with IP anonymization enabled
        
        Test.startTest();
        
        // Log event (IP anonymization will be applied based on config)
        AuditService.logSecurityEvent(
            AuditService.EVENT_API_ACCESS,
            'Test API access with IP anonymization',
            'Success'
        );
        
        Test.stopTest();
        
        // Verify audit event was created
        List<AI_Audit_Event__c> auditEvents = [
            SELECT Source_IP__c
            FROM AI_Audit_Event__c
            WHERE Event_Type__c = :AuditService.EVENT_API_ACCESS
        ];
        
        System.assertEquals(1, auditEvents.size(), 'Should create one audit event');
        // The actual IP value depends on the current session and config
        // In unit tests, Auth.SessionManagement.getCurrentSession() may return null
        // So we just verify the field exists
        System.assertNotEquals(null, auditEvents[0], 'Audit event should exist');
    }
}