/**
 * @description Comprehensive security audit logging service for RouteLogic Enhanced
 * @author RouteLogic Security Team
 * @date 2025-01-30
 * @version 4.0.0
 * 
 * This service provides real-time security event logging with Platform Events
 * for immediate notification and persistent storage for audit trails.
 */
public with sharing class SecurityAuditService {
    
    // Severity levels
    public enum Severity {
        CRITICAL, HIGH, MEDIUM, LOW, INFO
    }
    
    // Event types (matching the picklist values)
    public enum EventType {
        AUTHENTICATION,
        AUTHORIZATION,
        DATA_ACCESS,
        DATA_MODIFICATION,
        CONFIGURATION_CHANGE,
        SECURITY_VIOLATION,
        RATE_LIMIT_EXCEEDED,
        INPUT_VALIDATION_FAILURE,
        ENCRYPTION_OPERATION,
        API_CALL
    }
    
    // Cache for session information
    private static Map<String, SessionInfo> sessionCache = new Map<String, SessionInfo>();
    
    /**
     * @description Log a security event
     * @param eventType Type of security event
     * @param className Class where event occurred
     * @param details Event details map
     */
    public static void logEvent(String eventType, String className, Map<String, Object> details) {
        logEvent(eventType, className, details, Severity.INFO);
    }
    
    /**
     * @description Log a security event with severity
     * @param eventType Type of security event
     * @param className Class where event occurred
     * @param details Event details map
     * @param severity Event severity
     */
    public static void logEvent(String eventType, String className, Map<String, Object> details, Severity severity) {
        try {
            // Get current session info
            SessionInfo sessionInfo = getCurrentSessionInfo();
            
            // Create audit log record
            Security_Audit_Log__c auditLog = new Security_Audit_Log__c(
                Event_Type__c = eventType,
                Class_Name__c = className,
                User__c = UserInfo.getUserId(),
                IP_Address__c = sessionInfo.ipAddress,
                Session_Id__c = sessionInfo.sessionId,
                Severity__c = severity.name(),
                Event_Details__c = JSON.serializePretty(details)
            );
            
            // For critical events, publish Platform Event immediately
            if (severity == Severity.CRITICAL || severity == Severity.HIGH) {
                publishSecurityEvent(auditLog, details);
            }
            
            // Insert audit log (use future method to avoid DML in triggers)
            if (System.isFuture() || System.isBatch() || System.isQueueable()) {
                insertAuditLog(auditLog);
            } else {
                insertAuditLogFuture(JSON.serialize(auditLog));
            }
            
        } catch (Exception e) {
            // Log to debug log if audit logging fails
            System.debug(LoggingLevel.ERROR, 'Security audit logging failed: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Event details: ' + JSON.serialize(details));
        }
    }
    
    /**
     * @description Log authentication event
     * @param success Whether authentication was successful
     * @param username Username attempting authentication
     * @param method Authentication method used
     */
    public static void logAuthentication(Boolean success, String username, String method) {
        Map<String, Object> details = new Map<String, Object>{
            'success' => success,
            'username' => username,
            'method' => method,
            'timestamp' => DateTime.now()
        };
        
        Severity severity = success ? Severity.INFO : Severity.HIGH;
        logEvent('Authentication', 'SecurityAuditService', details, severity);
    }
    
    /**
     * @description Log authorization event
     * @param allowed Whether access was allowed
     * @param resource Resource being accessed
     * @param permission Permission required
     */
    public static void logAuthorization(Boolean allowed, String resource, String permission) {
        Map<String, Object> details = new Map<String, Object>{
            'allowed' => allowed,
            'resource' => resource,
            'permission' => permission,
            'userId' => UserInfo.getUserId(),
            'timestamp' => DateTime.now()
        };
        
        Severity severity = allowed ? Severity.INFO : Severity.MEDIUM;
        logEvent('Authorization', 'SecurityAuditService', details, severity);
    }
    
    /**
     * @description Log data access event
     * @param objectType Object being accessed
     * @param recordIds IDs of records accessed
     * @param operation Type of access (read, write, etc.)
     */
    public static void logDataAccess(String objectType, Set<Id> recordIds, String operation) {
        Map<String, Object> details = new Map<String, Object>{
            'objectType' => objectType,
            'recordCount' => recordIds.size(),
            'recordIds' => new List<Id>(recordIds),
            'operation' => operation,
            'timestamp' => DateTime.now()
        };
        
        logEvent('Data_Access', 'SecurityAuditService', details, Severity.INFO);
    }
    
    /**
     * @description Log security violation
     * @param violationType Type of violation
     * @param details Violation details
     */
    public static void logSecurityViolation(String violationType, Map<String, Object> details) {
        details.put('violationType', violationType);
        details.put('timestamp', DateTime.now());
        details.put('userId', UserInfo.getUserId());
        
        logEvent('Security_Violation', 'SecurityAuditService', details, Severity.CRITICAL);
    }
    
    /**
     * @description Log rate limit exceeded event
     * @param limitType Type of limit exceeded
     * @param currentValue Current value
     * @param limitValue Limit value
     */
    public static void logRateLimitExceeded(String limitType, Integer currentValue, Integer limitValue) {
        Map<String, Object> details = new Map<String, Object>{
            'limitType' => limitType,
            'currentValue' => currentValue,
            'limitValue' => limitValue,
            'userId' => UserInfo.getUserId(),
            'timestamp' => DateTime.now()
        };
        
        logEvent('Rate_Limit_Exceeded', 'SecurityAuditService', details, Severity.HIGH);
    }
    
    /**
     * @description Log input validation failure
     * @param fieldName Field that failed validation
     * @param reason Reason for failure
     * @param inputValue Sanitized input value (never log raw malicious input)
     */
    public static void logInputValidationFailure(String fieldName, String reason, String inputValue) {
        Map<String, Object> details = new Map<String, Object>{
            'fieldName' => fieldName,
            'reason' => reason,
            'inputLength' => inputValue != null ? inputValue.length() : 0,
            'timestamp' => DateTime.now()
        };
        
        logEvent('Input_Validation_Failure', 'SecurityAuditService', details, Severity.HIGH);
    }
    
    /**
     * @description Log API call
     * @param endpoint API endpoint
     * @param method HTTP method
     * @param statusCode Response status code
     * @param duration Call duration in milliseconds
     */
    public static void logAPICall(String endpoint, String method, Integer statusCode, Long duration) {
        Map<String, Object> details = new Map<String, Object>{
            'endpoint' => endpoint,
            'method' => method,
            'statusCode' => statusCode,
            'duration' => duration,
            'timestamp' => DateTime.now()
        };
        
        Severity severity = (statusCode >= 400) ? Severity.HIGH : Severity.INFO;
        logEvent('API_Call', 'SecurityAuditService', details, severity);
    }
    
    /**
     * @description Get current session information
     * @return SessionInfo object
     */
    private static SessionInfo getCurrentSessionInfo() {
        String sessionId = UserInfo.getSessionId();
        
        if (!sessionCache.containsKey(sessionId)) {
            SessionInfo info = new SessionInfo();
            info.sessionId = sessionId;
            
            // Get IP address from current request
            Map<String, String> headers = ApexPages.currentPage() != null ? 
                ApexPages.currentPage().getHeaders() : new Map<String, String>();
            
            // Use secure IP extraction
            info.ipAddress = extractTrustedIP(headers);
            
            sessionCache.put(sessionId, info);
        }
        
        return sessionCache.get(sessionId);
    }
    
    /**
     * @description Publish security event to Platform Events
     * @param auditLog Audit log record
     * @param details Event details
     */
    private static void publishSecurityEvent(Security_Audit_Log__c auditLog, Map<String, Object> details) {
        try {
            Security_Alert__e alert = new Security_Alert__e(
                Event_Type__c = auditLog.Event_Type__c,
                Severity__c = auditLog.Severity__c,
                User_Id__c = auditLog.User__c,
                Class_Name__c = auditLog.Class_Name__c,
                Alert_Details__c = JSON.serialize(details),
                Timestamp__c = DateTime.now()
            );
            
            EventBus.publish(alert);
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to publish security event: ' + e.getMessage());
        }
    }
    
    /**
     * @description Insert audit log record
     * @param auditLog Audit log to insert
     */
    private static void insertAuditLog(Security_Audit_Log__c auditLog) {
        try {
            // Check if user has create access
            if (Schema.sObjectType.Security_Audit_Log__c.isCreateable()) {
                insert RouteLogicSecurityUtils.stripInaccessibleFields(
                    RouteLogicSecurityUtils.AccessType.CREATABLE,
                    new List<Security_Audit_Log__c>{auditLog}
                )[0];
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to insert audit log: ' + e.getMessage());
        }
    }
    
    /**
     * @description Future method to insert audit log
     * @param auditLogJson Serialized audit log
     */
    @future
    private static void insertAuditLogFuture(String auditLogJson) {
        Security_Audit_Log__c auditLog = (Security_Audit_Log__c) JSON.deserialize(
            auditLogJson, 
            Security_Audit_Log__c.class
        );
        insertAuditLog(auditLog);
    }
    
    /**
     * @description Query audit logs with filters
     * @param eventType Filter by event type
     * @param startDate Start date filter
     * @param endDate End date filter
     * @param severity Minimum severity filter
     * @return List of audit logs
     */
    public static List<Security_Audit_Log__c> queryAuditLogs(
        String eventType, 
        DateTime startDate, 
        DateTime endDate,
        Severity severity
    ) {
        String query = 'SELECT Id, Name, Event_Type__c, Class_Name__c, User__c, User__r.Name, ' +
                      'IP_Address__c, Session_Id__c, Severity__c, Event_Details__c, CreatedDate ' +
                      'FROM Security_Audit_Log__c WHERE Id != null';
        
        if (String.isNotBlank(eventType)) {
            query += ' AND Event_Type__c = :eventType';
        }
        
        if (startDate != null) {
            query += ' AND CreatedDate >= :startDate';
        }
        
        if (endDate != null) {
            query += ' AND CreatedDate <= :endDate';
        }
        
        if (severity != null) {
            // Filter by severity level (Critical > High > Medium > Low > Info)
            List<String> severityLevels = getSeverityLevels(severity);
            query += ' AND Severity__c IN :severityLevels';
        }
        
        query += ' WITH SECURITY_ENFORCED ORDER BY CreatedDate DESC LIMIT 1000';
        
        return Database.query(query);
    }
    
    /**
     * @description Get severity levels at or above specified level
     * @param minSeverity Minimum severity
     * @return List of severity values
     */
    private static List<String> getSeverityLevels(Severity minSeverity) {
        List<String> levels = new List<String>();
        
        if (minSeverity == Severity.INFO) {
            levels.addAll(new List<String>{'Critical', 'High', 'Medium', 'Low', 'Info'});
        } else if (minSeverity == Severity.LOW) {
            levels.addAll(new List<String>{'Critical', 'High', 'Medium', 'Low'});
        } else if (minSeverity == Severity.MEDIUM) {
            levels.addAll(new List<String>{'Critical', 'High', 'Medium'});
        } else if (minSeverity == Severity.HIGH) {
            levels.addAll(new List<String>{'Critical', 'High'});
        } else if (minSeverity == Severity.CRITICAL) {
            levels.add('Critical');
        }
        
        return levels;
    }
    
    /**
     * @description Extract trusted IP address from headers
     * @param headers HTTP headers map
     * @return Trusted IP address
     */
    private static String extractTrustedIP(Map<String, String> headers) {
        // Salesforce trusted proxy IPs (example - verify with your setup)
        Set<String> trustedProxies = new Set<String>{
            '10.0.0.0/8',
            '172.16.0.0/12',
            '192.168.0.0/16'
        };
        
        String xForwardedFor = headers.get('X-Forwarded-For');
        
        if (String.isNotBlank(xForwardedFor)) {
            // X-Forwarded-For format: client, proxy1, proxy2
            // Parse from right to left to find first non-proxy IP
            List<String> ips = xForwardedFor.split(',');
            
            // Iterate from right to left
            for (Integer i = ips.size() - 1; i >= 0; i--) {
                String ip = ips[i].trim();
                
                // Validate IP format
                if (isValidIPAddress(ip)) {
                    // Check if it's a trusted proxy
                    if (!isInTrustedRange(ip, trustedProxies)) {
                        // This is the client IP
                        return ip;
                    }
                }
            }
        }
        
        // Fallback to X-Real-IP if available and valid
        String xRealIP = headers.get('X-Real-IP');
        if (String.isNotBlank(xRealIP) && isValidIPAddress(xRealIP)) {
            return xRealIP;
        }
        
        // Final fallback
        return 'Unknown';
    }
    
    /**
     * @description Validate IP address format
     * @param ip IP address to validate
     * @return True if valid IP address
     */
    private static Boolean isValidIPAddress(String ip) {
        // IPv4 validation pattern
        String ipv4Pattern = '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}' +
                            '(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$';
        
        // IPv6 validation pattern (simplified)
        String ipv6Pattern = '^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|' +
                            '([0-9a-fA-F]{1,4}:){1,7}:|' +
                            '([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|' +
                            '::1|::)$';
        
        return Pattern.matches(ipv4Pattern, ip) || Pattern.matches(ipv6Pattern, ip);
    }
    
    /**
     * @description Check if IP is in trusted range
     * @param ip IP address to check
     * @param trustedRanges Set of trusted CIDR ranges
     * @return True if IP is in trusted range
     */
    private static Boolean isInTrustedRange(String ip, Set<String> trustedRanges) {
        // Simplified check - in production, use proper CIDR matching
        // This is a placeholder - implement proper CIDR range checking
        for (String range : trustedRanges) {
            String rangePrefix = range.substringBefore('/');
            if (ip.startsWith(rangePrefix.substringBeforeLast('.'))) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * @description Get current IP address for REST contexts
     * @return Current request IP address
     */
    public static String getCurrentIPAddress() {
        // For REST context
        if (RestContext.request != null && RestContext.request.headers != null) {
            return extractTrustedIP(RestContext.request.headers);
        }
        
        // For Visualforce context
        if (ApexPages.currentPage() != null) {
            return extractTrustedIP(ApexPages.currentPage().getHeaders());
        }
        
        return 'Unknown';
    }
    
    /**
     * @description Session information container
     */
    private class SessionInfo {
        public String sessionId;
        public String ipAddress;
    }
}