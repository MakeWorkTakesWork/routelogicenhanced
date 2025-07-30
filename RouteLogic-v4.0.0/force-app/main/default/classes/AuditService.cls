/**
 * @description Comprehensive audit logging service for security and compliance events
 * @author RouteLogic Team
 * @date 2025-01-18
 */
public with sharing class AuditService {
    
    // Audit event types
    public static final String EVENT_KEY_ROTATION = 'KEY_ROTATION';
    public static final String EVENT_EMERGENCY_KEY_ROTATION = 'EMERGENCY_KEY_ROTATION';
    public static final String EVENT_KEY_CLEANUP = 'KEY_CLEANUP';
    public static final String EVENT_ACCESS_VIOLATION = 'ACCESS_VIOLATION';
    public static final String EVENT_DATA_EXPORT = 'DATA_EXPORT';
    public static final String EVENT_PERMISSION_CHANGE = 'PERMISSION_CHANGE';
    public static final String EVENT_FAILED_LOGIN = 'FAILED_LOGIN';
    public static final String EVENT_API_ACCESS = 'API_ACCESS';
    
    /**
     * @description Log a security event with immutable audit trail
     * @param eventType Type of security event
     * @param description Event description
     * @param status Event status (Success, Failed, Warning)
     */
    public static void logSecurityEvent(String eventType, String description, String status) {
        logAuditEvent(eventType, description, status, 'SECURITY', null);
    }
    
    /**
     * @description Log a compliance event
     * @param eventType Type of compliance event
     * @param description Event description
     * @param status Event status
     * @param metadata Additional metadata as JSON
     */
    public static void logComplianceEvent(String eventType, String description, String status, String metadata) {
        logAuditEvent(eventType, description, status, 'COMPLIANCE', metadata);
    }
    
    /**
     * @description Log an operational event
     * @param eventType Type of operational event
     * @param description Event description
     * @param status Event status
     */
    public static void logOperationalEvent(String eventType, String description, String status) {
        logAuditEvent(eventType, description, status, 'OPERATIONAL', null);
    }
    
    /**
     * @description Core audit logging method
     */
    private static void logAuditEvent(String eventType, String description, String status, String category, String metadata) {
        try {
            // Create audit event
            AI_Audit_Event__c auditEvent = new AI_Audit_Event__c(
                Event_Type__c = eventType,
                Category__c = category,
                Description__c = truncateString(description, 255),
                Status__c = status,
                User_Id__c = UserInfo.getUserId(),
                User_Name__c = UserInfo.getUserName(),
                Profile_Name__c = getProfileName(),
                Session_Id__c = UserInfo.getSessionId(),
                Source_IP__c = getAnonymizedIP(Auth.SessionManagement.getCurrentSession().get('SourceIp')),
                Timestamp__c = DateTime.now(),
                Organization_Id__c = UserInfo.getOrganizationId()
            );
            
            // Add metadata if provided
            if (String.isNotBlank(metadata)) {
                auditEvent.Metadata__c = truncateString(metadata, 32768);
            }
            
            // Add security hash for immutability
            auditEvent.Security_Hash__c = generateSecurityHash(auditEvent);
            
            // Apply FLS before insert
            List<AI_Audit_Event__c> eventsToInsert = new List<AI_Audit_Event__c>{auditEvent};
            eventsToInsert = SecurityUtils.stripInaccessibleRecords(
                AccessType.CREATABLE,
                eventsToInsert
            );
            
            // Insert with system mode to ensure logging always works
            Database.SaveResult result = Database.insert(eventsToInsert[0], false);
            
            if (!result.isSuccess()) {
                // Log to platform events if database insert fails
                publishAuditEvent(eventType, description, status, category);
            }
            
        } catch (Exception e) {
            // Final fallback to platform events
            publishAuditEvent(eventType, description, status, category);
            System.debug(LoggingLevel.ERROR, 'Audit logging failed: ' + e.getMessage());
        }
    }
    
    /**
     * @description Generate security hash for audit immutability
     */
    private static String generateSecurityHash(AI_Audit_Event__c auditEvent) {
        String dataToHash = auditEvent.Event_Type__c + '|' +
                           auditEvent.Description__c + '|' +
                           auditEvent.User_Id__c + '|' +
                           auditEvent.Timestamp__c.getTime() + '|' +
                           auditEvent.Organization_Id__c;
        
        Blob hash = Crypto.generateDigest('SHA-512', Blob.valueOf(dataToHash));
        return EncodingUtil.base64Encode(hash);
    }
    
    /**
     * @description Publish audit event as platform event for guaranteed delivery
     */
    private static void publishAuditEvent(String eventType, String description, String status, String category) {
        AI_Audit_Platform_Event__e platformEvent = new AI_Audit_Platform_Event__e(
            Event_Type__c = eventType,
            Category__c = category,
            Description__c = truncateString(description, 255),
            Status__c = status,
            User_Id__c = UserInfo.getUserId(),
            Timestamp__c = DateTime.now()
        );
        
        EventBus.publish(platformEvent);
    }
    
    /**
     * @description Get current user's profile name
     */
    private static String getProfileName() {
        try {
            return [SELECT Name FROM Profile WHERE Id = :UserInfo.getProfileId() LIMIT 1].Name;
        } catch (Exception e) {
            return 'Unknown';
        }
    }
    
    /**
     * @description Verify audit trail integrity
     * @param auditEventId The audit event to verify
     * @return Boolean indicating if the audit record is valid
     */
    public static Boolean verifyAuditIntegrity(Id auditEventId) {
        try {
            AI_Audit_Event__c auditEvent = [
                SELECT Event_Type__c, Description__c, User_Id__c, Timestamp__c, 
                       Organization_Id__c, Security_Hash__c
                FROM AI_Audit_Event__c
                WHERE Id = :auditEventId
                LIMIT 1
            ];
            
            // Regenerate hash
            String dataToHash = auditEvent.Event_Type__c + '|' +
                               auditEvent.Description__c + '|' +
                               auditEvent.User_Id__c + '|' +
                               auditEvent.Timestamp__c.getTime() + '|' +
                               auditEvent.Organization_Id__c;
            
            Blob hash = Crypto.generateDigest('SHA-512', Blob.valueOf(dataToHash));
            String expectedHash = EncodingUtil.base64Encode(hash);
            
            return auditEvent.Security_Hash__c == expectedHash;
            
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
     * @description Export audit logs for compliance reporting
     * @param startDate Start date for export
     * @param endDate End date for export
     * @param category Category filter (optional)
     * @return JSON string of audit events
     */
    public static String exportAuditLogs(DateTime startDate, DateTime endDate, String category) {
        // Check permissions
        if (!FeatureManagement.checkPermission('AI_Audit_Export')) {
            throw new InsufficientPrivilegesException('Audit export permission required');
        }
        
        // Log the export event itself
        logComplianceEvent(
            EVENT_DATA_EXPORT,
            'Audit log export requested for period: ' + startDate.format() + ' to ' + endDate.format(),
            'Initiated',
            JSON.serialize(new Map<String, Object>{
                'startDate' => startDate,
                'endDate' => endDate,
                'category' => category,
                'exportedBy' => UserInfo.getUserId()
            })
        );
        
        // Build query
        String query = 'SELECT Event_Type__c, Category__c, Description__c, Status__c, ' +
                      'User_Id__c, User_Name__c, Profile_Name__c, Timestamp__c, ' +
                      'Security_Hash__c, Metadata__c ' +
                      'FROM AI_Audit_Event__c ' +
                      'WHERE Timestamp__c >= :startDate AND Timestamp__c <= :endDate';
        
        if (String.isNotBlank(category)) {
            query += ' AND Category__c = :category';
        }
        
        query += ' ORDER BY Timestamp__c DESC LIMIT 10000';
        
        List<AI_Audit_Event__c> auditEvents = Database.query(query);
        
        // Verify integrity of each record
        List<Map<String, Object>> exportData = new List<Map<String, Object>>();
        for (AI_Audit_Event__c event : auditEvents) {
            Map<String, Object> eventData = new Map<String, Object>{
                'eventType' => event.Event_Type__c,
                'category' => event.Category__c,
                'description' => event.Description__c,
                'status' => event.Status__c,
                'userId' => event.User_Id__c,
                'userName' => event.User_Name__c,
                'profileName' => event.Profile_Name__c,
                'timestamp' => event.Timestamp__c,
                'integrityValid' => verifyAuditIntegrity(event.Id)
            };
            
            if (String.isNotBlank(event.Metadata__c)) {
                eventData.put('metadata', event.Metadata__c);
            }
            
            exportData.add(eventData);
        }
        
        return JSON.serialize(exportData);
    }
    
    /**
     * @description Truncate string to specified length
     */
    private static String truncateString(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return null;
        }
        
        if (value.length() <= maxLength) {
            return value;
        }
        
        return value.substring(0, maxLength - 3) + '...';
    }
    
    /**
     * @description Anonymize IP address if configured
     * @param ipAddress The original IP address
     * @return Anonymized IP address or original if anonymization disabled
     */
    private static String getAnonymizedIP(String ipAddress) {
        if (String.isBlank(ipAddress)) {
            return null;
        }
        
        // Check if anonymization is enabled
        if (!ConfigManager.isIPAnonymizationEnabled()) {
            return ipAddress;
        }
        
        // Anonymize IPv4 addresses (e.g., 192.168.1.100 -> 192.168.1.0)
        if (ipAddress.contains('.')) {
            List<String> octets = ipAddress.split('\\.');
            if (octets.size() == 4) {
                octets[3] = '0';
                return String.join(octets, '.');
            }
        }
        // Anonymize IPv6 addresses (zero out last 4 segments)
        else if (ipAddress.contains(':')) {
            List<String> segments = ipAddress.split(':');
            if (segments.size() >= 4) {
                Integer segmentsToAnonymize = Math.min(4, segments.size());
                for (Integer i = segments.size() - segmentsToAnonymize; i < segments.size(); i++) {
                    segments[i] = '0';
                }
                return String.join(segments, ':');
            }
        }
        
        // If format is unrecognized, return masked IP
        return 'ANONYMIZED';
    }
}