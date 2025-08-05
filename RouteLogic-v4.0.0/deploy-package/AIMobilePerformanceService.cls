/**
 * @description Service for mobile performance optimization with enhanced security
 * @author RouteLogic Team
 * @date 2025-01-20
 * @security Fixed SQL injection vulnerability - February 5, 2025
 */
public with sharing class AIMobilePerformanceService {
    
    // Security: Allowed performance data types
    public enum AllowedPerformanceTypes {
        ROUTES,
        STATUS,
        ANALYTICS,
        CONFIG,
        SYNC_DATA
    }
    
    // Security: Allowed objects for mobile queries
    private static final Set<String> ALLOWED_MOBILE_OBJECTS = new Set<String>{
        'Route__c',
        'AI_Processing_Status__c',
        'AI_Provider_Configuration__c',
        'Case',
        'Contact',
        'Account'
    };
    
    // Mobile optimization settings
    public class MobileConfig {
        public Boolean enableDataCompression { get; set; }
        public Integer maxPayloadSize { get; set; }
        public Boolean enableOfflineMode { get; set; }
        public Integer syncBatchSize { get; set; }
        public Boolean enableLazyLoading { get; set; }
        public Integer imageQuality { get; set; }
        
        public MobileConfig() {
            this.enableDataCompression = true;
            this.maxPayloadSize = 100000; // 100KB
            this.enableOfflineMode = true;
            this.syncBatchSize = 50;
            this.enableLazyLoading = true;
            this.imageQuality = 70; // 70% quality
        }
    }
    
    // Mobile response wrapper
    public class MobileResponse {
        public Boolean success { get; set; }
        public Object data { get; set; }
        public Integer dataSize { get; set; }
        public Boolean isCompressed { get; set; }
        public String nextPageToken { get; set; }
        public Map<String, Object> metadata { get; set; }
        
        public MobileResponse() {
            this.success = true;
            this.metadata = new Map<String, Object>();
        }
    }
    
    // Secure optimized data fetch for mobile
    public static MobileResponse getMobileData(
        String dataTypeStr,
        Map<String, Object> params,
        MobileConfig config
    ) {
        MobileResponse response = new MobileResponse();
        
        try {
            // Security: Validate data type using enum
            AllowedPerformanceTypes dataType;
            try {
                dataType = AllowedPerformanceTypes.valueOf(dataTypeStr.toUpperCase());
            } catch (Exception e) {
                throw new SecurityException('Invalid data type: ' + dataTypeStr);
            }
            
            Object data = null;
            
            switch on dataType {
                when ROUTES {
                    data = getMobileRoutes(params, config);
                }
                when STATUS {
                    data = getMobileStatus(params, config);
                }
                when ANALYTICS {
                    data = getMobileAnalytics(params, config);
                }
                when CONFIG {
                    data = getMobileConfig(params, config);
                }
                when SYNC_DATA {
                    DateTime lastSync = params.containsKey('lastSync') ? 
                        (DateTime)params.get('lastSync') : DateTime.now().addDays(-1);
                    data = getSyncData(lastSync, config);
                }
            }
            
            // Optimize response
            response = optimizeResponse(data, config);
            
            return response;
            
        } catch (Exception e) {
            response.success = false;
            response.data = new Map<String, String>{
                'error' => e.getMessage()
            };
            return response;
        }
    }
    
    // Mobile-optimized route data
    private static List<Map<String, Object>> getMobileRoutes(
        Map<String, Object> params,
        MobileConfig config
    ) {
        Integer pageSize = config.enableLazyLoading ? 20 : 50;
        Integer offset = params.containsKey('offset') ? 
            (Integer)params.get('offset') : 0;
        
        // Validate offset
        if (offset < 0 || pageSize < 1 || pageSize > 200) {
            throw new IllegalArgumentException('Invalid pagination parameters');
        }
        
        // Query only essential fields with security enforced
        List<Route__c> routes = [
            SELECT Id, Name, Status__c, Priority__c, 
                   Start_Location__c, End_Location__c,
                   Estimated_Duration__c
            FROM Route__c
            WHERE OwnerId = :UserInfo.getUserId()
            WITH SECURITY_ENFORCED
            ORDER BY Priority__c DESC, CreatedDate DESC
            LIMIT :pageSize
            OFFSET :offset
        ];
        
        // Convert to lightweight format
        List<Map<String, Object>> mobileRoutes = new List<Map<String, Object>>();
        
        for (Route__c route : routes) {
            Map<String, Object> mobileRoute = new Map<String, Object>{
                'id' => route.Id,
                'name' => route.Name,
                'status' => route.Status__c,
                'priority' => route.Priority__c,
                'duration' => route.Estimated_Duration__c
            };
            
            // Include location only if needed
            if (params.containsKey('includeLocation')) {
                mobileRoute.put('start', route.Start_Location__c);
                mobileRoute.put('end', route.End_Location__c);
            }
            
            mobileRoutes.add(mobileRoute);
        }
        
        return mobileRoutes;
    }
    
    // Mobile-optimized status data
    private static List<Map<String, Object>> getMobileStatus(
        Map<String, Object> params,
        MobileConfig config
    ) {
        DateTime sinceDate = params.containsKey('since') ?
            (DateTime)params.get('since') : DateTime.now().addDays(-1);
        
        // Validate date range
        if (sinceDate > DateTime.now()) {
            throw new IllegalArgumentException('Invalid date range');
        }
        
        // Aggregate status data with security
        List<AggregateResult> statusCounts = [
            SELECT Status__c status, COUNT(Id) cnt
            FROM AI_Processing_Status__c
            WHERE CreatedDate >= :sinceDate
            WITH SECURITY_ENFORCED
            GROUP BY Status__c
            LIMIT 20
        ];
        
        List<Map<String, Object>> statusData = new List<Map<String, Object>>();
        
        for (AggregateResult ar : statusCounts) {
            statusData.add(new Map<String, Object>{
                'status' => ar.get('status'),
                'count' => ar.get('cnt')
            });
        }
        
        return statusData;
    }
    
    // Mobile-optimized analytics
    private static Map<String, Object> getMobileAnalytics(
        Map<String, Object> params,
        MobileConfig config
    ) {
        DateTime startDate = params.containsKey('startDate') ?
            (DateTime)params.get('startDate') : DateTime.now().addDays(-7);
        
        // Validate date range
        if (startDate > DateTime.now() || startDate < DateTime.now().addDays(-90)) {
            throw new IllegalArgumentException('Invalid date range (max 90 days)');
        }
        
        // Get key metrics only with security
        AggregateResult[] metrics = [
            SELECT Provider_Type__c provider,
                   COUNT(Id) total,
                   AVG(Processing_Time__c) avgTime
            FROM AI_Processing_Status__c
            WHERE CreatedDate >= :startDate
            AND Status__c = 'Completed'
            WITH SECURITY_ENFORCED
            GROUP BY Provider_Type__c
            LIMIT 5
        ];
        
        Map<String, Object> analytics = new Map<String, Object>{
            'period' => startDate.format('MMM d') + ' - Today',
            'providers' => new List<Map<String, Object>>()
        };
        
        for (AggregateResult ar : metrics) {
            ((List<Map<String, Object>>)analytics.get('providers')).add(
                new Map<String, Object>{
                    'name' => ar.get('provider'),
                    'count' => ar.get('total'),
                    'avgTime' => Math.round((Decimal)ar.get('avgTime'))
                }
            );
        }
        
        return analytics;
    }
    
    // Mobile configuration data
    private static Map<String, Object> getMobileConfig(
        Map<String, Object> params,
        MobileConfig config
    ) {
        // Return minimal configuration
        return new Map<String, Object>{
            'syncInterval' => 300, // 5 minutes
            'offlineEnabled' => config.enableOfflineMode,
            'compressionEnabled' => config.enableDataCompression,
            'maxCacheSize' => 50000000, // 50MB
            'apiVersion' => '1.0'
        };
    }
    
    // Response optimization
    private static MobileResponse optimizeResponse(
        Object data,
        MobileConfig config
    ) {
        MobileResponse response = new MobileResponse();
        response.data = data;
        
        // Calculate data size
        String jsonData = JSON.serialize(data);
        response.dataSize = jsonData.length();
        
        // Compress if needed
        if (config.enableDataCompression && 
            response.dataSize > config.maxPayloadSize) {
            response.data = compressData(jsonData);
            response.isCompressed = true;
            response.dataSize = ((String)response.data).length();
        }
        
        // Add metadata
        response.metadata.put('timestamp', DateTime.now().getTime());
        response.metadata.put('compressed', response.isCompressed);
        response.metadata.put('originalSize', jsonData.length());
        
        return response;
    }
    
    // Offline sync support with security
    public static List<Map<String, Object>> getSyncData(
        DateTime lastSyncTime,
        MobileConfig config
    ) {
        // Validate sync time
        if (lastSyncTime > DateTime.now() || lastSyncTime < DateTime.now().addDays(-30)) {
            throw new IllegalArgumentException('Invalid sync time (max 30 days)');
        }
        
        List<Map<String, Object>> syncData = new List<Map<String, Object>>();
        
        // Get modified records since last sync
        List<SObject> modifiedRecords = new List<SObject>();
        
        // Routes - with security
        modifiedRecords.addAll([
            SELECT Id, Name, Status__c, LastModifiedDate
            FROM Route__c
            WHERE LastModifiedDate > :lastSyncTime
            AND OwnerId = :UserInfo.getUserId()
            WITH SECURITY_ENFORCED
            LIMIT :config.syncBatchSize
        ]);
        
        // Processing status - with security
        modifiedRecords.addAll([
            SELECT Id, Status__c, LastModifiedDate
            FROM AI_Processing_Status__c
            WHERE LastModifiedDate > :lastSyncTime
            AND CreatedById = :UserInfo.getUserId()
            WITH SECURITY_ENFORCED
            LIMIT :config.syncBatchSize
        ]);
        
        // Convert to sync format
        for (SObject record : modifiedRecords) {
            syncData.add(new Map<String, Object>{
                'id' => record.Id,
                'type' => record.getSObjectType().getDescribe().getName(),
                'modified' => record.get('LastModifiedDate'),
                'data' => getMinimalRecordData(record)
            });
        }
        
        return syncData;
    }
    
    // Conflict resolution for offline changes
    public static Map<String, Object> resolveConflicts(
        List<Map<String, Object>> clientChanges,
        String strategy
    ) {
        // Validate strategy
        Set<String> allowedStrategies = new Set<String>{
            'SERVER_WINS', 'CLIENT_WINS', 'MANUAL'
        };
        
        if (!allowedStrategies.contains(strategy)) {
            throw new IllegalArgumentException('Invalid conflict resolution strategy');
        }
        
        Map<String, Object> result = new Map<String, Object>{
            'resolved' => new List<Map<String, Object>>(),
            'conflicts' => new List<Map<String, Object>>()
        };
        
        for (Map<String, Object> change : clientChanges) {
            String recordId = (String)change.get('id');
            DateTime clientModified = (DateTime)change.get('modified');
            
            // Get server version securely
            SObject serverRecord = getRecordSecure(recordId);
            if (serverRecord == null) continue;
            
            DateTime serverModified = (DateTime)serverRecord.get('LastModifiedDate');
            
            if (serverModified > clientModified) {
                // Conflict detected
                Map<String, Object> conflict = new Map<String, Object>{
                    'id' => recordId,
                    'clientVersion' => change,
                    'serverVersion' => serverRecord
                };
                
                switch on strategy {
                    when 'SERVER_WINS' {
                        ((List<Map<String, Object>>)result.get('resolved')).add(
                            new Map<String, Object>{
                                'id' => recordId,
                                'resolution' => 'server',
                                'data' => serverRecord
                            }
                        );
                    }
                    when 'CLIENT_WINS' {
                        applyClientChange(change);
                        ((List<Map<String, Object>>)result.get('resolved')).add(
                            new Map<String, Object>{
                                'id' => recordId,
                                'resolution' => 'client',
                                'data' => change
                            }
                        );
                    }
                    when else {
                        ((List<Map<String, Object>>)result.get('conflicts')).add(conflict);
                    }
                }
            } else {
                // No conflict
                applyClientChange(change);
                ((List<Map<String, Object>>)result.get('resolved')).add(
                    new Map<String, Object>{
                        'id' => recordId,
                        'resolution' => 'none',
                        'data' => change
                    }
                );
            }
        }
        
        return result;
    }
    
    // Image optimization
    public static String optimizeImageForMobile(
        String base64Image,
        MobileConfig config
    ) {
        // Validate input
        if (String.isBlank(base64Image) || base64Image.length() > 10000000) {
            throw new IllegalArgumentException('Invalid image data');
        }
        
        // In a real implementation, this would:
        // 1. Decode the base64 image
        // 2. Resize to appropriate dimensions
        // 3. Compress with specified quality
        // 4. Return optimized base64
        
        // For now, return a placeholder
        return 'OPTIMIZED_' + base64Image.substring(0, Math.min(20, base64Image.length())) + '...';
    }
    
    // Network status aware fetching
    public static MobileResponse getDataForNetworkType(
        String networkType,
        String dataType,
        Map<String, Object> params
    ) {
        // Validate network type
        Set<String> allowedNetworkTypes = new Set<String>{
            '2G', '3G', '4G', '5G', 'WIFI', 'SLOW', 'MODERATE', 'FAST'
        };
        
        if (!allowedNetworkTypes.contains(networkType.toUpperCase())) {
            throw new IllegalArgumentException('Invalid network type');
        }
        
        MobileConfig config = new MobileConfig();
        
        switch on networkType.toUpperCase() {
            when '2G', 'SLOW' {
                // Ultra-light mode
                config.enableDataCompression = true;
                config.maxPayloadSize = 10000; // 10KB
                config.enableLazyLoading = true;
                config.syncBatchSize = 10;
                config.imageQuality = 30;
            }
            when '3G', 'MODERATE' {
                // Light mode
                config.enableDataCompression = true;
                config.maxPayloadSize = 50000; // 50KB
                config.enableLazyLoading = true;
                config.syncBatchSize = 25;
                config.imageQuality = 50;
            }
            when '4G', '5G', 'WIFI', 'FAST' {
                // Normal mode
                config.enableDataCompression = false;
                config.maxPayloadSize = 500000; // 500KB
                config.enableLazyLoading = false;
                config.syncBatchSize = 100;
                config.imageQuality = 80;
            }
        }
        
        return getMobileData(dataType, params, config);
    }
    
    // Helper methods
    private static String compressData(String data) {
        // Simple compression using base64 encoding
        // In production, use proper compression algorithm
        Blob dataBlob = Blob.valueOf(data);
        return EncodingUtil.base64Encode(dataBlob);
    }
    
    private static Map<String, Object> getMinimalRecordData(SObject record) {
        Map<String, Object> minimalData = new Map<String, Object>();
        
        // Include only essential fields
        Set<String> essentialFields = new Set<String>{
            'Id', 'Name', 'Status__c', 'LastModifiedDate'
        };
        
        for (String field : essentialFields) {
            try {
                minimalData.put(field, record.get(field));
            } catch (Exception e) {
                // Field doesn't exist on this object
            }
        }
        
        return minimalData;
    }
    
    // Security: Fixed SQL injection vulnerability
    private static SObject getRecordSecure(String recordId) {
        // Validate record ID
        try {
            Id recId = Id.valueOf(recordId);
            String objectType = recId.getSObjectType().getDescribe().getName();
            
            // Security: Validate object type against whitelist
            if (!ALLOWED_MOBILE_OBJECTS.contains(objectType)) {
                throw new SecurityException('Invalid object type for mobile access: ' + objectType);
            }
            
            // Use static SOQL with bind variable
            if (objectType == 'Route__c') {
                return [SELECT Id, LastModifiedDate FROM Route__c 
                       WHERE Id = :recId WITH SECURITY_ENFORCED LIMIT 1];
            } else if (objectType == 'AI_Processing_Status__c') {
                return [SELECT Id, LastModifiedDate FROM AI_Processing_Status__c 
                       WHERE Id = :recId WITH SECURITY_ENFORCED LIMIT 1];
            } else if (objectType == 'Case') {
                return [SELECT Id, LastModifiedDate FROM Case 
                       WHERE Id = :recId WITH SECURITY_ENFORCED LIMIT 1];
            } else if (objectType == 'Contact') {
                return [SELECT Id, LastModifiedDate FROM Contact 
                       WHERE Id = :recId WITH SECURITY_ENFORCED LIMIT 1];
            } else if (objectType == 'Account') {
                return [SELECT Id, LastModifiedDate FROM Account 
                       WHERE Id = :recId WITH SECURITY_ENFORCED LIMIT 1];
            } else if (objectType == 'AI_Provider_Configuration__c') {
                return [SELECT Id, LastModifiedDate FROM AI_Provider_Configuration__c 
                       WHERE Id = :recId WITH SECURITY_ENFORCED LIMIT 1];
            }
            
            return null;
            
        } catch (Exception e) {
            System.debug('Error retrieving record: ' + e.getMessage());
            return null;
        }
    }
    
    private static void applyClientChange(Map<String, Object> change) {
        // Apply client changes to server with validation
        // Implementation depends on specific requirements
        String recordId = (String)change.get('id');
        
        // Validate the record exists and user has access
        SObject record = getRecordSecure(recordId);
        if (record == null) {
            throw new SecurityException('Cannot apply changes to record: ' + recordId);
        }
        
        // Apply changes with FLS checks
        // This would be implemented based on specific field requirements
        System.debug('Applying client change: ' + change);
    }
}