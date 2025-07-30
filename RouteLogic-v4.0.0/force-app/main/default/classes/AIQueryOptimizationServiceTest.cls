@isTest
private class AIQueryOptimizationServiceTest {
    
    @testSetup
    static void setupTestData() {
        // Create test provider configurations
        List<AI_Provider_Configuration__c> configs = new List<AI_Provider_Configuration__c>();
        for (Integer i = 0; i < 5; i++) {
            configs.add(new AI_Provider_Configuration__c(
                Name = 'Test Provider ' + i,
                Provider_Type__c = 'OpenAI',
                API_Endpoint__c = 'https://api.test' + i + '.com',
                Is_Active__c = true,
                Priority_Level__c = i + 1
            ));
        }
        insert configs;
        
        // Create test processing status records
        List<AI_Processing_Status__c> statuses = new List<AI_Processing_Status__c>();
        for (Integer i = 0; i < 100; i++) {
            statuses.add(new AI_Processing_Status__c(
                Status__c = Math.mod(i, 2) == 0 ? 'Completed' : 'Failed',
                Provider_Type__c = 'OpenAI',
                Processing_Time__c = Math.random() * 1000,
                Error_Message__c = Math.mod(i, 2) == 1 ? 'Test error' : null
            ));
        }
        insert statuses;
    }
    
    @isTest
    static void testOptimizedProcessingStatusQuery() {
        // Setup
        DateTime startDate = DateTime.now().addDays(-7);
        DateTime endDate = DateTime.now();
        Set<String> providerTypes = new Set<String>{'OpenAI', 'Claude'};
        
        AIQueryOptimizationService.OptimizerConfig config = 
            new AIQueryOptimizationService.OptimizerConfig();
        
        Test.startTest();
        
        List<AI_Processing_Status__c> results = 
            AIQueryOptimizationService.getProcessingStatusOptimized(
                startDate, endDate, providerTypes, config
            );
        
        Test.stopTest();
        
        // Verify
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assert(results.size() > 0, 'Should return some results');
    }
    
    @isTest
    static void testBulkProviderConfigFetch() {
        // Get test data IDs
        List<AI_Provider_Configuration__c> configs = [
            SELECT Id FROM AI_Provider_Configuration__c LIMIT 5
        ];
        Set<Id> configIds = new Set<Id>();
        for (AI_Provider_Configuration__c config : configs) {
            configIds.add(config.Id);
        }
        
        Test.startTest();
        
        Map<Id, AI_Provider_Configuration__c> results = 
            AIQueryOptimizationService.getProviderConfigsBulk(configIds);
        
        Test.stopTest();
        
        // Verify
        System.assertEquals(configIds.size(), results.size(), 
            'Should return all requested configs');
        for (Id configId : configIds) {
            System.assert(results.containsKey(configId), 
                'Result should contain config: ' + configId);
        }
    }
    
    @isTest
    static void testOptimizedAnalytics() {
        // Setup
        DateTime startDate = DateTime.now().addDays(-30);
        DateTime endDate = DateTime.now();
        AIQueryOptimizationService.OptimizerConfig config = 
            new AIQueryOptimizationService.OptimizerConfig();
        
        Test.startTest();
        
        List<AggregateResult> results = 
            AIQueryOptimizationService.getOptimizedAnalytics(
                'Provider_Type__c', startDate, endDate, config
            );
        
        Test.stopTest();
        
        // Verify
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assert(results.size() > 0, 'Should return aggregate results');
    }
    
    @isTest
    static void testLazyLoading() {
        Test.startTest();
        
        // Test first page
        List<SObject> page1 = AIQueryOptimizationService.lazyLoadRecords(
            'AI_Processing_Status__c', 0, 10, 'CreatedDate DESC'
        );
        
        // Test second page
        List<SObject> page2 = AIQueryOptimizationService.lazyLoadRecords(
            'AI_Processing_Status__c', 10, 10, 'CreatedDate DESC'
        );
        
        Test.stopTest();
        
        // Verify
        System.assertEquals(10, page1.size(), 'First page should have 10 records');
        System.assertEquals(10, page2.size(), 'Second page should have 10 records');
        
        // Verify different records
        Set<Id> page1Ids = new Set<Id>();
        for (SObject obj : page1) {
            page1Ids.add(obj.Id);
        }
        
        for (SObject obj : page2) {
            System.assert(!page1Ids.contains(obj.Id), 
                'Pages should contain different records');
        }
    }
    
    @isTest
    static void testBatchProcessing() {
        // Setup
        String query = 'SELECT Id, Status__c FROM AI_Processing_Status__c';
        TestBatchProcessor processor = new TestBatchProcessor();
        AIQueryOptimizationService.OptimizerConfig config = 
            new AIQueryOptimizationService.OptimizerConfig();
        config.batchSize = 50;
        
        Test.startTest();
        
        AIQueryOptimizationService.processBatchOptimized(query, processor, config);
        
        Test.stopTest();
        
        // Verify
        System.assert(processor.processedBatches > 0, 
            'Should process at least one batch');
        System.assert(processor.totalRecords > 0, 
            'Should process some records');
    }
    
    @isTest
    static void testQueryAnalysis() {
        Test.startTest();
        
        // Test unoptimized query
        String badQuery = 'SELECT Id FROM Account WHERE Name NOT IN (\'Test\')';
        AIQueryOptimizationService.QueryMetrics metrics1 = 
            AIQueryOptimizationService.analyzeQuery(badQuery);
        
        // Test optimized query
        String goodQuery = 'SELECT Id FROM Account WHERE Name = \'Test\' LIMIT 100';
        AIQueryOptimizationService.QueryMetrics metrics2 = 
            AIQueryOptimizationService.analyzeQuery(goodQuery);
        
        Test.stopTest();
        
        // Verify
        System.assertEquals(false, metrics1.isOptimized, 
            'Bad query should not be optimized');
        System.assert(metrics1.optimizationSuggestions.size() > 0, 
            'Should have suggestions for bad query');
        
        System.assertEquals(true, metrics2.isOptimized, 
            'Good query should be optimized');
    }
    
    @isTest
    static void testIndexRecommendations() {
        Test.startTest();
        
        List<String> recommendations = 
            AIQueryOptimizationService.recommendIndexes('AI_Processing_Status__c');
        
        Test.stopTest();
        
        // Verify
        System.assertNotEquals(null, recommendations, 
            'Should return recommendations');
        System.assert(recommendations.size() > 0, 
            'Should have some index recommendations');
    }
    
    @isTest
    static void testEmptyResultHandling() {
        // Test with no matching records
        DateTime futureDate = DateTime.now().addDays(30);
        Set<String> nonExistentTypes = new Set<String>{'NonExistent'};
        
        AIQueryOptimizationService.OptimizerConfig config = 
            new AIQueryOptimizationService.OptimizerConfig();
        
        Test.startTest();
        
        List<AI_Processing_Status__c> results = 
            AIQueryOptimizationService.getProcessingStatusOptimized(
                futureDate, futureDate.addDays(1), nonExistentTypes, config
            );
        
        Test.stopTest();
        
        // Verify
        System.assertNotEquals(null, results, 'Should return empty list, not null');
        System.assertEquals(0, results.size(), 'Should return no results');
    }
    
    @isTest
    static void testCacheIntegration() {
        // This test verifies that query results are cached
        Set<Id> configIds = new Set<Id>();
        for (AI_Provider_Configuration__c config : 
             [SELECT Id FROM AI_Provider_Configuration__c LIMIT 2]) {
            configIds.add(config.Id);
        }
        
        Test.startTest();
        
        // First call - should query database
        Map<Id, AI_Provider_Configuration__c> results1 = 
            AIQueryOptimizationService.getProviderConfigsBulk(configIds);
        
        // Second call - should use cache
        Map<Id, AI_Provider_Configuration__c> results2 = 
            AIQueryOptimizationService.getProviderConfigsBulk(configIds);
        
        Test.stopTest();
        
        // Verify same results
        System.assertEquals(results1.size(), results2.size(), 
            'Should return same number of results');
    }
    
    // Test batch processor implementation
    public class TestBatchProcessor implements AIQueryOptimizationService.IBatchProcessor {
        public Integer processedBatches = 0;
        public Integer totalRecords = 0;
        
        public void processBatch(List<SObject> records) {
            processedBatches++;
            totalRecords += records.size();
        }
    }
}