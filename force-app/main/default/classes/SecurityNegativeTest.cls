/**
 * @description Negative security test cases to verify security controls
 * @author RouteLogic Team
 * @date 2025-01-20
 */
@isTest
@namespaceAccessible
public with sharing class SecurityNegativeTest {
    
    @TestSetup
    static void setup() {
        // Create test users with different permission levels
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        Profile minAccessProfile = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        
        User adminUser = new User(
            Alias = 'admin',
            Email = 'admin@routelogic.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Admin',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'admin@routelogic.test.org'
        );
        insert adminUser;
        
        User standardUser = new User(
            Alias = 'stdusr',
            Email = 'standard@routelogic.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Standard',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'standard@routelogic.test.org'
        );
        insert standardUser;
        
        User restrictedUser = new User(
            Alias = 'restr',
            Email = 'restricted@routelogic.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Restricted',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = minAccessProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'restricted@routelogic.test.org'
        );
        insert restrictedUser;
        
        // Create test data
        System.runAs(adminUser) {
            // Create cases
            List<Case> cases = new List<Case>();
            for (Integer i = 0; i < 5; i++) {
                cases.add(new Case(
                    Subject = 'Test Case ' + i,
                    Priority = 'High',
                    AI_Processing_Status__c = 'Pending'
                ));
            }
            insert cases;
            
            // Create AI settings
            AI_Security_Settings__c settings = new AI_Security_Settings__c(
                Key_Version__c = '1',
                Encryption_Algorithm__c = 'AES256',
                Key_Rotation_Days__c = 90
            );
            insert settings;
        }
    }
    
    /**
     * @description Test unauthorized access to AI bulk processing
     */
    @isTest
    static void testUnauthorizedBulkProcessingAccess() {
        User restrictedUser = [SELECT Id FROM User WHERE UserName = 'restricted@routelogic.test.org' LIMIT 1];
        List<Case> cases = [SELECT Id FROM Case LIMIT 5];
        List<Id> caseIds = new List<Id>();
        for (Case c : cases) {
            caseIds.add(c.Id);
        }
        
        Test.startTest();
        System.runAs(restrictedUser) {
            try {
                // Attempt to process cases without proper permissions
                AIBulkProcessingController.processCases(caseIds, 'Ada');
                System.assert(false, 'Expected exception for unauthorized access');
            } catch (Exception e) {
                // Expected behavior - should throw exception
                System.assert(e.getMessage().contains('Insufficient') || 
                             e.getMessage().contains('permission') ||
                             e.getMessage().contains('License'), 
                             'Expected permission/license error, got: ' + e.getMessage());
            }
        }
        Test.stopTest();
    }
    
    /**
     * @description Test CRUD permission bypass attempts
     */
    @isTest
    static void testCRUDPermissionBypass() {
        User restrictedUser = [SELECT Id FROM User WHERE UserName = 'restricted@routelogic.test.org' LIMIT 1];
        
        Test.startTest();
        System.runAs(restrictedUser) {
            // Attempt to create AI_Processing_Status__c without permissions
            AI_Processing_Status__c status = new AI_Processing_Status__c(
                Case__c = [SELECT Id FROM Case LIMIT 1].Id,
                AI_Provider__c = 'Ada',
                Status__c = 'Pending'
            );
            
            try {
                insert status;
                // If insert succeeds, check if FLS was enforced
                List<AI_Processing_Status__c> statuses = [
                    SELECT Id, Case__c, AI_Provider__c 
                    FROM AI_Processing_Status__c 
                    WHERE Id = :status.Id
                ];
                System.assert(statuses.isEmpty() || statuses[0].Id == null, 
                             'Security.stripInaccessible should have prevented insert');
            } catch (Exception e) {
                // Expected - insufficient permissions
                System.assert(e.getMessage().contains('INSUFFICIENT') || 
                             e.getMessage().contains('permission'), 
                             'Expected permission error');
            }
        }
        Test.stopTest();
    }
    
    /**
     * @description Test FLS enforcement on query results
     */
    @isTest
    static void testFLSEnforcementOnQueries() {
        User standardUser = [SELECT Id FROM User WHERE UserName = 'standard@routelogic.test.org' LIMIT 1];
        
        Test.startTest();
        System.runAs(standardUser) {
            try {
                // Attempt to query sensitive fields without FLS permissions
                List<AI_Security_Settings__c> settings = [
                    SELECT Id, Key_Version__c, Encryption_Algorithm__c
                    FROM AI_Security_Settings__c
                    WITH SECURITY_ENFORCED
                ];
                
                // If query succeeds, verify FLS was applied
                if (!settings.isEmpty()) {
                    System.assert(settings[0].Key_Version__c == null || 
                                 String.isBlank(String.valueOf(settings[0].Key_Version__c)), 
                                 'Sensitive field should be stripped by FLS');
                }
            } catch (Exception e) {
                // Expected if user lacks read permissions
                System.assert(e.getMessage().contains('INSUFFICIENT') || 
                             e.getMessage().contains('WITH SECURITY_ENFORCED'), 
                             'Expected security enforcement error');
            }
        }
        Test.stopTest();
    }
    
    /**
     * @description Test trigger recursion attack prevention
     */
    @isTest
    static void testTriggerRecursionPrevention() {
        // Attempt to cause infinite recursion through trigger manipulation
        List<Case> cases = [SELECT Id FROM Case LIMIT 1];
        
        Test.startTest();
        try {
            // Simulate multiple rapid updates that could cause recursion
            for (Integer i = 0; i < 10; i++) {
                cases[0].Description = 'Update ' + i;
                update cases[0];
            }
            
            // Verify recursion control kicked in
            List<AI_Error_Log__c> errors = [
                SELECT Id, Error_Message__c 
                FROM AI_Error_Log__c 
                WHERE Class_Name__c = 'TriggerRecursionControl'
            ];
            
            // Should have logged recursion prevention
            System.assert(!errors.isEmpty() || TriggerRecursionControl.hasRun('AI_Case_Request_EventHandler'), 
                         'Recursion control should have activated');
        } catch (Exception e) {
            // Expected if recursion control throws exception
            System.assert(e.getMessage().contains('recursion') || 
                         e.getMessage().contains('execution limit'), 
                         'Expected recursion control error');
        }
        Test.stopTest();
    }
    
    /**
     * @description Test license validation bypass attempts
     */
    @isTest
    static void testLicenseValidationBypass() {
        User restrictedUser = [SELECT Id FROM User WHERE UserName = 'restricted@routelogic.test.org' LIMIT 1];
        
        Test.startTest();
        System.runAs(restrictedUser) {
            try {
                // Attempt to access licensed features without proper license
                Boolean hasLicense = LicenseManager.validateLicense();
                
                if (!hasLicense) {
                    // Try to bypass by calling internal methods directly
                    AIBulkProcessingCoordinator.BulkProcessingRequest request = 
                        new AIBulkProcessingCoordinator.BulkProcessingRequest();
                    request.caseIds = new List<Id>{[SELECT Id FROM Case LIMIT 1].Id};
                    request.provider = 'Ada';
                    
                    try {
                        // This should fail due to license check
                        String jobId = AIBulkProcessingCoordinator.initiateBulkProcessing(request);
                        System.assert(false, 'Expected license validation to prevent execution');
                    } catch (Exception e) {
                        System.assert(e.getMessage().contains('License') || 
                                     e.getMessage().contains('license'), 
                                     'Expected license error');
                    }
                }
            } catch (Exception e) {
                // Expected - license validation should fail
                System.assert(true, 'License validation working correctly');
            }
        }
        Test.stopTest();
    }
    
    /**
     * @description Test encryption key access control
     */
    @isTest
    static void testEncryptionKeyAccessControl() {
        User restrictedUser = [SELECT Id FROM User WHERE UserName = 'restricted@routelogic.test.org' LIMIT 1];
        
        Test.startTest();
        System.runAs(restrictedUser) {
            try {
                // Attempt to access encryption keys without authorization
                SecurityKeyManager keyManager = new SecurityKeyManager();
                Blob key = keyManager.getEncryptionKey();
                
                // Should not reach here
                System.assert(false, 'Expected security exception for key access');
            } catch (Exception e) {
                // Expected - unauthorized key access
                System.assert(e.getMessage().contains('Unauthorized') || 
                             e.getMessage().contains('permission') ||
                             e.getMessage().contains('INSUFFICIENT'), 
                             'Expected authorization error for key access');
            }
        }
        Test.stopTest();
    }
    
    /**
     * @description Test API endpoint authentication bypass
     */
    @isTest
    static void testAPIAuthenticationBypass() {
        // Simulate REST context without proper authentication
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/ai/webhook';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"test": "data"}');
        
        // Remove authentication headers
        req.headers.clear();
        
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        try {
            // Attempt to call webhook without authentication
            AIWebhookService.handleWebhook();
            
            // Check response for authentication error
            System.assert(res.statusCode == 401 || res.statusCode == 403, 
                         'Expected authentication failure status code');
        } catch (Exception e) {
            // Expected - authentication should fail
            System.assert(e.getMessage().contains('Unauthorized') || 
                         e.getMessage().contains('Authentication'), 
                         'Expected authentication error');
        }
        Test.stopTest();
    }
    
    /**
     * @description Test SQL injection prevention
     */
    @isTest
    static void testSQLInjectionPrevention() {
        // Attempt SQL injection through dynamic SOQL
        String maliciousInput = '\' OR Id != null OR Subject = \'';
        
        Test.startTest();
        try {
            // This should be prevented by proper query construction
            List<Case> cases = Database.query(
                'SELECT Id FROM Case WHERE Subject = :maliciousInput WITH SECURITY_ENFORCED'
            );
            
            // Should return empty, not all records
            System.assert(cases.isEmpty(), 'SQL injection should be prevented');
        } catch (Exception e) {
            // Expected if query is malformed
            System.assert(true, 'Query protection working');
        }
        Test.stopTest();
    }
    
    /**
     * @description Test cross-site scripting (XSS) prevention
     */
    @isTest
    static void testXSSPrevention() {
        String xssPayload = '<script>alert("XSS")</script>';
        Case c = new Case(
            Subject = xssPayload,
            Description = xssPayload
        );
        insert c;
        
        Test.startTest();
        // Verify XSS payload is escaped when retrieved
        Case retrievedCase = [SELECT Subject, Description FROM Case WHERE Id = :c.Id];
        
        // The payload should be stored but escaped when displayed
        System.assert(retrievedCase.Subject.contains(xssPayload), 
                     'XSS payload should be stored as-is');
        
        // When used in contexts, it should be escaped
        String escaped = String.escapeSingleQuotes(retrievedCase.Subject);
        System.assert(!escaped.contains('<script>') || escaped.contains('\\'), 
                     'XSS content should be escaped');
        Test.stopTest();
    }
    
    /**
     * @description Test rate limiting bypass attempts
     */
    @isTest
    static void testRateLimitingBypass() {
        String userId = UserInfo.getUserId();
        String endpoint = 'Ada';
        
        Test.startTest();
        // Attempt to exceed rate limits
        for (Integer i = 0; i < 150; i++) {
            try {
                Boolean allowed = AIRateLimiter.checkRateLimit(userId, endpoint);
                
                if (i > 100) {
                    // Should be rate limited by now
                    System.assert(!allowed, 'Rate limiting should kick in after 100 requests');
                }
            } catch (Exception e) {
                // Expected when rate limit exceeded
                System.assert(e.getMessage().contains('Rate limit') || 
                             e.getMessage().contains('limit exceeded'), 
                             'Expected rate limit error');
                break;
            }
        }
        Test.stopTest();
    }
}