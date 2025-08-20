/**
 * @description Test data factory for creating comprehensive test data
 * @author RouteLogic Team
 * @date 2025-01-17
 */
@IsTest
public class TestDataFactory {
    
    /**
     * @description Create comprehensive test data for all test classes
     */
    public static void createComprehensiveTestData() {
        // Create organization-wide custom settings
        AI_Config__c config = AI_Config__c.getOrgDefaults();
        config.Enable_AI_Processing__c = true;
        config.Enable_Rate_Limiting__c = true;
        config.Default_Rate_Limit__c = 100;
        config.Default_Window_Seconds__c = 3600;
        config.Max_Retry_Attempts__c = 3;
        config.Circuit_Breaker_Threshold__c = 5;
        config.Enable_Webhook_Support__c = true;
        upsert config;
        
        // Create security settings
        AI_Security_Settings__c securitySettings = AI_Security_Settings__c.getOrgDefaults();
        securitySettings.Enable_Security_Monitoring__c = true;
        securitySettings.Log_Rate_Limit_Violations__c = true;
        securitySettings.Enable_Encryption__c = true;
        securitySettings.Key_Rotation_Days__c = 90;
        securitySettings.Enable_Threat_Detection__c = true;
        upsert securitySettings;
        
        // Create provider settings
        AI_Provider_Settings__c providerSettings = AI_Provider_Settings__c.getOrgDefaults();
        providerSettings.Ada_Endpoint__c = 'https://api.ada.cx/v1';
        providerSettings.Intercom_Endpoint__c = 'https://api.intercom.io/v2';
        providerSettings.Default_Provider__c = 'Intercom';
        providerSettings.Enable_Provider_Failover__c = true;
        upsert providerSettings;
    }
    
    /**
     * @description Create bulk cases for testing
     * @param count Number of cases to create
     * @return List of created cases
     */
    public static List<Case> createBulkCases(Integer count) {
        // Create accounts and contacts first
        List<Account> accounts = createAccounts(Math.min(count/5, 50));
        List<Contact> contacts = createContacts(accounts);
        
        // Create cases
        List<Case> cases = new List<Case>();
        List<String> priorities = new List<String>{'Low', 'Medium', 'High', 'Urgent'};
        List<String> origins = new List<String>{'Email', 'Phone', 'Web', 'Chat'};
        List<String> statuses = new List<String>{'New', 'Working', 'Escalated'};
        
        for (Integer i = 0; i < count; i++) {
            Account acc = accounts[Math.mod(i, accounts.size())];
            Contact con = contacts[Math.mod(i, contacts.size())];
            
            cases.add(new Case(
                Subject = 'Bulk Test Case ' + i + ' - ' + generateRandomString(10),
                Description = 'Test description for bulk processing. Customer issue related to ' + 
                             generateRandomString(20) + '. This requires AI analysis.',
                AccountId = acc.Id,
                ContactId = con.Id,
                Priority = priorities[Math.mod(i, priorities.size())],
                Origin = origins[Math.mod(i, origins.size())],
                Status = statuses[Math.mod(i, statuses.size())],
                Type = 'Problem',
                Reason = 'Performance',
                SuppliedEmail = 'test' + i + '@example.com',
                SuppliedName = 'Test Customer ' + i
            ));
        }
        
        insert cases;
        
        // Create related records for some cases
        createCaseRelatedRecords(cases);
        
        return cases;
    }
    
    /**
     * @description Create a single case with default values
     * @return Created case
     */
    public static Case createCase() {
        Account acc = createAccount('Test Account ' + generateRandomString(5));
        Contact con = createContact(acc);
        
        Case c = new Case(
            Subject = 'Test Case - ' + generateRandomString(10),
            Description = 'Test case for AI processing',
            AccountId = acc.Id,
            ContactId = con.Id,
            Priority = 'Medium',
            Origin = 'Web',
            Status = 'New'
        );
        insert c;
        return c;
    }
    
    /**
     * @description Create accounts for testing
     * @param count Number of accounts to create
     * @return List of created accounts
     */
    public static List<Account> createAccounts(Integer count) {
        List<Account> accounts = new List<Account>();
        List<String> industries = new List<String>{'Technology', 'Healthcare', 'Finance', 'Retail', 'Manufacturing'};
        List<String> types = new List<String>{'Customer', 'Partner', 'Prospect'};
        
        for (Integer i = 0; i < count; i++) {
            accounts.add(new Account(
                Name = 'Test Account ' + i + ' - ' + generateRandomString(5),
                Type = types[Math.mod(i, types.size())],
                Industry = industries[Math.mod(i, industries.size())],
                AnnualRevenue = Math.round(Math.random() * 1000000),
                NumberOfEmployees = Integer.valueOf(Math.random() * 1000),
                BillingStreet = i + ' Test Street',
                BillingCity = 'Test City',
                BillingState = 'CA',
                BillingPostalCode = '94000',
                BillingCountry = 'USA',
                Phone = '555-' + String.valueOf(i).leftPad(4, '0'),
                Website = 'https://test' + i + '.example.com'
            ));
        }
        insert accounts;
        return accounts;
    }
    
    /**
     * @description Create a single account
     * @param name Account name
     * @return Created account
     */
    public static Account createAccount(String name) {
        Account acc = new Account(
            Name = name,
            Type = 'Customer',
            Industry = 'Technology'
        );
        insert acc;
        return acc;
    }
    
    /**
     * @description Create contacts for accounts
     * @param accounts List of accounts
     * @return List of created contacts
     */
    public static List<Contact> createContacts(List<Account> accounts) {
        List<Contact> contacts = new List<Contact>();
        
        for (Account acc : accounts) {
            // Create 2 contacts per account
            for (Integer i = 0; i < 2; i++) {
                contacts.add(new Contact(
                    FirstName = 'Test',
                    LastName = 'Contact ' + acc.Name + ' ' + i,
                    AccountId = acc.Id,
                    Email = 'contact' + acc.Id + '_' + i + '@example.com',
                    Phone = '555-' + String.valueOf(Math.round(Math.random() * 9999)).leftPad(4, '0'),
                    Title = i == 0 ? 'Primary Contact' : 'Secondary Contact',
                    Department = 'Customer Service',
                    MailingStreet = acc.BillingStreet,
                    MailingCity = acc.BillingCity,
                    MailingState = acc.BillingState,
                    MailingPostalCode = acc.BillingPostalCode,
                    MailingCountry = acc.BillingCountry
                ));
            }
        }
        insert contacts;
        return contacts;
    }
    
    /**
     * @description Create a single contact
     * @param acc Account to associate with
     * @return Created contact
     */
    public static Contact createContact(Account acc) {
        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Contact ' + generateRandomString(5),
            AccountId = acc.Id,
            Email = 'test' + generateRandomString(5) + '@example.com'
        );
        insert con;
        return con;
    }
    
    /**
     * @description Create case-related records
     * @param cases List of cases
     */
    private static void createCaseRelatedRecords(List<Case> cases) {
        // Create AI conversation history for some cases
        List<AI_Conversation_History__c> histories = new List<AI_Conversation_History__c>();
        
        for (Integer i = 0; i < Math.min(cases.size(), 20); i++) {
            histories.add(new AI_Conversation_History__c(
                Case__c = cases[i].Id,
                Conversation_Data__c = generateSampleConversation(),
                Start_Time__c = DateTime.now().addHours(-i),
                End_Time__c = DateTime.now().addHours(-i).addMinutes(30),
                Message_Count__c = 5 + Math.round(Math.random() * 10)
            ));
        }
        if (!histories.isEmpty()) {
            insert histories;
        }
        
        // Create AI processing status records
        List<AI_Processing_Status__c> statuses = new List<AI_Processing_Status__c>();
        
        for (Integer i = 0; i < Math.min(cases.size(), 30); i++) {
            statuses.add(new AI_Processing_Status__c(
                Case__c = cases[i].Id,
                Status__c = 'Pending',
                AI_Provider__c = Math.mod(i, 2) == 0 ? 'Intercom' : 'Ada',
                Request_Time__c = DateTime.now().addMinutes(-i),
                Priority__c = cases[i].Priority
            ));
        }
        if (!statuses.isEmpty()) {
            insert statuses;
        }
    }
    
    /**
     * @description Create admin user for testing
     * @return Created admin user
     */
    public static User createAdminUser() {
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        
        User adminUser = new User(
            Alias = 'tadmin',
            Email = 'testadmin@routelogic.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TestAdmin',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testadmin' + DateTime.now().getTime() + '@routelogic.test',
            IsActive = true
        );
        
        // Insert user first
        insert adminUser;
        
        // Assign permission set if available
        try {
            PermissionSet adminPS = [SELECT Id FROM PermissionSet WHERE Name = 'AI_Case_Management_Admin' LIMIT 1];
            insert new PermissionSetAssignment(
                AssigneeId = adminUser.Id,
                PermissionSetId = adminPS.Id
            );
        } catch (Exception e) {
            // Permission set might not exist in test context
            // Admin permission set not found - test continues without it
        }
        
        return adminUser;
    }
    
    /**
     * @description Create standard user for testing
     * @return Created standard user
     */
    public static User createStandardUser() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        User standardUser = new User(
            Alias = 'tuser',
            Email = 'testuser@routelogic.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TestUser',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testuser' + DateTime.now().getTime() + '@routelogic.test',
            IsActive = true
        );
        
        insert standardUser;
        
        // Assign user permission set if available
        try {
            PermissionSet userPS = [SELECT Id FROM PermissionSet WHERE Name = 'AI_Case_Management_User' LIMIT 1];
            insert new PermissionSetAssignment(
                AssigneeId = standardUser.Id,
                PermissionSetId = userPS.Id
            );
        } catch (Exception e) {
            // Permission set might not exist in test context
            // User permission set not found - test continues without it
        }
        
        return standardUser;
    }
    
    /**
     * @description Generate random string for test data
     * @param length Length of string to generate
     * @return Random string
     */
    private static String generateRandomString(Integer length) {
        String chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
        String randomString = '';
        
        for (Integer i = 0; i < length; i++) {
            Integer idx = Math.mod(Math.abs(Crypto.getRandomInteger()), chars.length());
            randomString += chars.substring(idx, idx + 1);
        }
        
        return randomString;
    }
    
    /**
     * @description Generate sample conversation JSON
     * @return Sample conversation data
     */
    private static String generateSampleConversation() {
        List<Map<String, Object>> conversation = new List<Map<String, Object>>();
        
        conversation.add(new Map<String, Object>{
            'timestamp' => DateTime.now().addMinutes(-30).getTime(),
            'type' => 'user',
            'message' => 'I need help with my account settings'
        });
        
        conversation.add(new Map<String, Object>{
            'timestamp' => DateTime.now().addMinutes(-29).getTime(),
            'type' => 'ai',
            'message' => 'I can help you with your account settings. What specific issue are you experiencing?'
        });
        
        conversation.add(new Map<String, Object>{
            'timestamp' => DateTime.now().addMinutes(-28).getTime(),
            'type' => 'user',
            'message' => 'I cannot update my billing information'
        });
        
        conversation.add(new Map<String, Object>{
            'timestamp' => DateTime.now().addMinutes(-27).getTime(),
            'type' => 'ai',
            'message' => 'Let me help you update your billing information. I will need to verify your account first.',
            'sentiment' => 'helpful',
            'confidence' => 0.95
        });
        
        return JSON.serialize(conversation);
    }
    
    /**
     * @description Create test webhook payload
     * @param provider AI provider name
     * @return Webhook payload
     */
    public static String createWebhookPayload(String provider) {
        Map<String, Object> payload = new Map<String, Object>();
        
        if (provider == 'Intercom') {
            payload.put('type', 'conversation.updated');
            payload.put('id', 'conv_' + generateRandomString(10));
            payload.put('data', new Map<String, Object>{
                'conversation_id' => generateRandomString(10),
                'status' => 'resolved',
                'sentiment' => 'positive'
            });
        } else if (provider == 'Ada') {
            payload.put('event', 'message.received');
            payload.put('conversation_id', generateRandomString(10));
            payload.put('message', new Map<String, Object>{
                'text' => 'Customer query resolved',
                'intent' => 'billing_support',
                'confidence' => 0.92
            });
        }
        
        return JSON.serialize(payload);
    }
}