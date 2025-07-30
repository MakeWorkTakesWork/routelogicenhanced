@isTest
private class AIMobilePerformanceServiceTest {
    
    @testSetup
    static void setupTestData() {
        // Create test routes
        List<Route__c> routes = new List<Route__c>();
        for (Integer i = 0; i < 30; i++) {
            routes.add(new Route__c(
                Name = 'Mobile Route ' + i,
                Status__c = Math.mod(i, 3) == 0 ? 'Active' : 'Pending',
                Priority__c = Math.mod(i, 5) + 1,
                Start_Location__c = 'Start ' + i,
                End_Location__c = 'End ' + i,
                Estimated_Duration__c = Math.random() * 100
            ));
        }
        insert routes;
        
        // Create test processing status
        List<AI_Processing_Status__c> statuses = new List<AI_Processing_Status__c>();
        DateTime baseTime = DateTime.now().addDays(-7);
        for (Integer i = 0; i < 50; i++) {
            statuses.add(new AI_Processing_Status__c(
                Status__c = Math.mod(i, 3) == 0 ? 'Completed' : 'Processing',
                Provider_Type__c = Math.mod(i, 2) == 0 ? 'OpenAI' : 'Claude',
                Processing_Time__c = Math.random() * 500,
                CreatedDate = baseTime.addHours(i)
            ));
        }
        insert statuses;
        
        // Create user preferences
        AI_User_Preference__c pref = new AI_User_Preference__c(
            User__c = UserInfo.getUserId(),
            Preference_Key__c = 'theme',
            Preference_Value__c = 'light'
        );
        insert pref;
    }
    
    @isTest
    static void testGetMobileRoutes() {
        AIMobilePerformanceService.MobileConfig config = 
            new AIMobilePerformanceService.MobileConfig();
        
        Map<String, Object> params = new Map<String, Object>{
            'offset' => 0,
            'includeLocation' => true
        };
        
        Test.startTest();
        
        AIMobilePerformanceService.MobileResponse response = 
            AIMobilePerformanceService.getMobileData('routes', params, config);
        
        Test.stopTest();
        
        // Verify
        System.assertEquals(true, response.success, 'Response should be successful');
        System.assertNotEquals(null, response.data, 'Should return data');
        
        List<Map<String, Object>> routes = (List<Map<String, Object>>) response.data;
        System.assert(routes.size() > 0, 'Should return routes');
        System.assert(routes.size() <= 20, 'Should respect lazy loading limit');
        
        // Verify route structure
        Map<String, Object> firstRoute = routes[0];
        System.assert(firstRoute.containsKey('id'), 'Should have id');
        System.assert(firstRoute.containsKey('name'), 'Should have name');
        System.assert(firstRoute.containsKey('start'), 'Should include location when requested');
    }
    
    @isTest
    static void testGetMobileStatus() {
        AIMobilePerformanceService.MobileConfig config = 
            new AIMobilePerformanceService.MobileConfig();
        
        Map<String, Object> params = new Map<String, Object>{
            'since' => DateTime.now().addDays(-2)
        };
        
        Test.startTest();
        
        AIMobilePerformanceService.MobileResponse response = 
            AIMobilePerformanceService.getMobileData('status', params, config);
        
        Test.stopTest();
        
        // Verify
        System.assertEquals(true, response.success, 'Response should be successful');
        List<Map<String, Object>> statusData = (List<Map<String, Object>>) response.data;
        System.assert(statusData.size() > 0, 'Should return status data');
        
        // Verify status structure
        for (Map<String, Object> status : statusData) {
            System.assert(status.containsKey('status'), 'Should have status');
            System.assert(status.containsKey('count'), 'Should have count');
        }
    }
    
    @isTest
    static void testGetMobileAnalytics() {
        AIMobilePerformanceService.MobileConfig config = 
            new AIMobilePerformanceService.MobileConfig();
        
        Map<String, Object> params = new Map<String, Object>{
            'startDate' => DateTime.now().addDays(-7)
        };
        
        Test.startTest();
        
        AIMobilePerformanceService.MobileResponse response = 
            AIMobilePerformanceService.getMobileData('analytics', params, config);
        
        Test.stopTest();
        
        // Verify
        System.assertEquals(true, response.success, 'Response should be successful');
        Map<String, Object> analytics = (Map<String, Object>) response.data;
        System.assert(analytics.containsKey('period'), 'Should have period');
        System.assert(analytics.containsKey('providers'), 'Should have providers');
        
        List<Map<String, Object>> providers = 
            (List<Map<String, Object>>) analytics.get('providers');
        System.assert(providers.size() > 0, 'Should have provider data');
    }
    
    @isTest
    static void testGetMobileConfig() {
        AIMobilePerformanceService.MobileConfig config = 
            new AIMobilePerformanceService.MobileConfig();
        
        Test.startTest();
        
        AIMobilePerformanceService.MobileResponse response = 
            AIMobilePerformanceService.getMobileData('config', new Map<String, Object>(), config);
        
        Test.stopTest();
        
        // Verify
        System.assertEquals(true, response.success, 'Response should be successful');
        Map<String, Object> configData = (Map<String, Object>) response.data;
        System.assert(configData.containsKey('syncInterval'), 'Should have sync interval');
        System.assert(configData.containsKey('offlineEnabled'), 'Should have offline flag');
        System.assert(configData.containsKey('apiVersion'), 'Should have API version');
    }
    
    @isTest
    static void testDataCompression() {
        AIMobilePerformanceService.MobileConfig config = 
            new AIMobilePerformanceService.MobileConfig();
        config.enableDataCompression = true;
        config.maxPayloadSize = 100; // Very small to force compression
        
        // Create large data set
        Map<String, Object> params = new Map<String, Object>{
            'offset' => 0,
            'includeLocation' => true
        };
        
        Test.startTest();
        
        AIMobilePerformanceService.MobileResponse response = 
            AIMobilePerformanceService.getMobileData('routes', params, config);
        
        Test.stopTest();
        
        // Verify compression
        System.assertEquals(true, response.success, 'Response should be successful');
        System.assertEquals(true, response.isCompressed, 'Data should be compressed');
        System.assert(response.dataSize < response.metadata.get('originalSize'), 
            'Compressed size should be smaller');
    }
    
    @isTest
    static void testOfflineSync() {
        AIMobilePerformanceService.MobileConfig config = 
            new AIMobilePerformanceService.MobileConfig();
        config.syncBatchSize = 10;
        
        DateTime lastSync = DateTime.now().addHours(-1);
        
        Test.startTest();
        
        List<Map<String, Object>> syncData = 
            AIMobilePerformanceService.getSyncData(lastSync, config);
        
        Test.stopTest();
        
        // Verify
        System.assertNotEquals(null, syncData, 'Should return sync data');
        System.assert(syncData.size() <= config.syncBatchSize * 2, 
            'Should respect batch size limit');
        
        // Verify sync data structure
        if (!syncData.isEmpty()) {
            Map<String, Object> firstItem = syncData[0];
            System.assert(firstItem.containsKey('id'), 'Should have id');
            System.assert(firstItem.containsKey('type'), 'Should have type');
            System.assert(firstItem.containsKey('modified'), 'Should have modified date');
            System.assert(firstItem.containsKey('data'), 'Should have data');
        }
    }
    
    @isTest
    static void testConflictResolution() {
        // Create test conflict data
        Route__c testRoute = [SELECT Id, LastModifiedDate FROM Route__c LIMIT 1];
        
        List<Map<String, Object>> clientChanges = new List<Map<String, Object>>{
            new Map<String, Object>{
                'id' => testRoute.Id,
                'modified' => testRoute.LastModifiedDate.addHours(-1),
                'data' => new Map<String, Object>{'Status__c' => 'ClientUpdate'}
            }
        };
        
        Test.startTest();
        
        // Test SERVER_WINS strategy
        Map<String, Object> result1 = 
            AIMobilePerformanceService.resolveConflicts(clientChanges, 'SERVER_WINS');
        
        // Test CLIENT_WINS strategy
        Map<String, Object> result2 = 
            AIMobilePerformanceService.resolveConflicts(clientChanges, 'CLIENT_WINS');
        
        // Test MANUAL strategy
        Map<String, Object> result3 = 
            AIMobilePerformanceService.resolveConflicts(clientChanges, 'MANUAL');
        
        Test.stopTest();
        
        // Verify
        List<Map<String, Object>> resolved1 = 
            (List<Map<String, Object>>) result1.get('resolved');
        System.assertEquals(1, resolved1.size(), 'Should resolve with server wins');
        
        List<Map<String, Object>> resolved2 = 
            (List<Map<String, Object>>) result2.get('resolved');
        System.assertEquals(1, resolved2.size(), 'Should resolve with client wins');
        
        List<Map<String, Object>> conflicts3 = 
            (List<Map<String, Object>>) result3.get('conflicts');
        System.assertEquals(1, conflicts3.size(), 'Should have conflict for manual resolution');
    }
    
    @isTest
    static void testNetworkAwareFetching() {
        Map<String, Object> params = new Map<String, Object>();
        
        Test.startTest();
        
        // Test 2G/Slow network
        AIMobilePerformanceService.MobileResponse response2G = 
            AIMobilePerformanceService.getDataForNetworkType('2G', 'routes', params);
        
        // Test 4G/Fast network
        AIMobilePerformanceService.MobileResponse response4G = 
            AIMobilePerformanceService.getDataForNetworkType('4G', 'routes', params);
        
        Test.stopTest();
        
        // Verify
        System.assertEquals(true, response2G.success, '2G response should succeed');
        System.assertEquals(true, response2G.isCompressed, '2G should use compression');
        
        System.assertEquals(true, response4G.success, '4G response should succeed');
        System.assertEquals(false, response4G.isCompressed, '4G should not compress');
    }
    
    @isTest
    static void testImageOptimization() {
        AIMobilePerformanceService.MobileConfig config = 
            new AIMobilePerformanceService.MobileConfig();
        config.imageQuality = 50;
        
        String testImage = 'base64encodedimagedata1234567890';
        
        Test.startTest();
        
        String optimized = 
            AIMobilePerformanceService.optimizeImageForMobile(testImage, config);
        
        Test.stopTest();
        
        // Verify
        System.assertNotEquals(null, optimized, 'Should return optimized image');
        System.assert(optimized.startsWith('OPTIMIZED_'), 'Should be marked as optimized');
    }
    
    @isTest
    static void testErrorHandling() {
        AIMobilePerformanceService.MobileConfig config = 
            new AIMobilePerformanceService.MobileConfig();
        
        Test.startTest();
        
        // Test with invalid data type
        AIMobilePerformanceService.MobileResponse response = 
            AIMobilePerformanceService.getMobileData(
                'invalid_type', 
                new Map<String, Object>(), 
                config
            );
        
        Test.stopTest();
        
        // Verify
        System.assertEquals(false, response.success, 'Should indicate failure');
        Map<String, String> errorData = (Map<String, String>) response.data;
        System.assert(errorData.containsKey('error'), 'Should contain error message');
    }
}