/**
 * @description Service class for managing AI conversation sessions and entries
 * @author RouteLogic Team
 * @date 2025-01-17
 */
public with sharing class ConversationService {
    
    // Using centralized constants to avoid naming collisions
    
    /**
     * @description Create or get active conversation session for a case
     * @param caseId The case ID
     * @param provider The AI provider
     * @return The conversation session
     */
    public static AI_Conversation_Session__c getOrCreateSession(Id caseId, String provider) {
        if (caseId == null || String.isBlank(provider)) {
            throw new AIException('Case ID and provider are required');
        }
        
        // Look for active session
        List<AI_Conversation_Session__c> activeSessions = [
            SELECT Id, Case__c, AI_Provider__c, Total_Messages__c, Start_Time__c
            FROM AI_Conversation_Session__c
            WHERE Case__c = :caseId
            AND AI_Provider__c = :provider
            AND Status__c = 'Active'
            AND Start_Time__c >= :DateTime.now().addMinutes(-Constants.SESSION_TIMEOUT_MINUTES)
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        if (!activeSessions.isEmpty()) {
            return activeSessions[0];
        }
        
        // Create new session
        return createNewSession(caseId, provider);
    }
    
    /**
     * @description Create new conversation session
     */
    private static AI_Conversation_Session__c createNewSession(Id caseId, String provider) {
        // Close any existing active sessions
        closeActiveSessions(caseId, provider);
        
        // Create new session
        AI_Conversation_Session__c session = new AI_Conversation_Session__c(
            Case__c = caseId,
            AI_Provider__c = provider,
            Status__c = 'Active',
            Start_Time__c = DateTime.now(),
            Total_Messages__c = 0
        );
        
        insert SecurityUtils.stripInaccessibleRecords(
            AccessType.CREATABLE,
            new List<AI_Conversation_Session__c>{session}
        )[0];
        
        return session;
    }
    
    /**
     * @description Add entry to conversation
     * @param sessionId The session ID
     * @param messageType Type of message
     * @param content Message content
     * @param metadata Additional metadata
     * @return The created entry
     */
    public static AI_Conversation_Entry__c addEntry(
        Id sessionId, 
        String messageType, 
        String content, 
        Map<String, Object> metadata
    ) {
        if (sessionId == null || String.isBlank(messageType) || String.isBlank(content)) {
            throw new AIException('Session ID, message type, and content are required');
        }
        
        // Get current session
        AI_Conversation_Session__c session = [
            SELECT Id, Total_Messages__c, Status__c
            FROM AI_Conversation_Session__c
            WHERE Id = :sessionId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        
        // Check if session is still active
        if (session.Status__c != 'Active') {
            throw new AIException('Cannot add entry to inactive session');
        }
        
        // Check if session has reached max entries
        if (session.Total_Messages__c >= Constants.MAX_ENTRIES_PER_SESSION) {
            // Create new session and add entry there
            AI_Conversation_Session__c newSession = createContinuationSession(session);
            return addEntry(newSession.Id, messageType, content, metadata);
        }
        
        // Create entry
        AI_Conversation_Entry__c entry = new AI_Conversation_Entry__c(
            Session__c = sessionId,
            Entry_Number__c = session.Total_Messages__c + 1,
            Message_Type__c = messageType,
            Message_Content__c = content,
            Timestamp__c = DateTime.now()
        );
        
        // Add metadata if provided
        if (metadata != null && !metadata.isEmpty()) {
            entry.Metadata__c = JSON.serialize(metadata);
        }
        
        // Insert entry
        insert SecurityUtils.stripInaccessibleRecords(
            AccessType.CREATABLE,
            new List<AI_Conversation_Entry__c>{entry}
        )[0];
        
        // Update session message count
        session.Total_Messages__c = session.Total_Messages__c + 1;
        update SecurityUtils.stripInaccessibleRecords(
            AccessType.UPDATABLE,
            new List<AI_Conversation_Session__c>{session}
        )[0];
        
        return entry;
    }
    
    /**
     * @description Get conversation history for a case
     * @param caseId The case ID
     * @param limitCount Maximum number of entries to return
     * @return List of conversation entries
     */
    public static List<ConversationEntry> getConversationHistory(Id caseId, Integer limitCount) {
        if (caseId == null) {
            throw new AIException('Case ID is required');
        }
        
        limitCount = limitCount != null ? Math.min(limitCount, 500) : 100;
        
        List<ConversationEntry> history = new List<ConversationEntry>();
        
        // Get recent sessions
        List<AI_Conversation_Session__c> sessions = [
            SELECT Id, Start_Time__c, End_Time__c, Status__c, AI_Provider__c,
                (SELECT Id, Entry_Number__c, Timestamp__c, Message_Type__c, 
                        Message_Content__c, Metadata__c
                 FROM Conversation_Entries__r
                 ORDER BY Entry_Number__c DESC)
            FROM AI_Conversation_Session__c
            WHERE Case__c = :caseId
            WITH SECURITY_ENFORCED
            ORDER BY Start_Time__c DESC
            LIMIT 10
        ];
        
        // Build conversation history
        Integer entryCount = 0;
        for (AI_Conversation_Session__c session : sessions) {
            for (AI_Conversation_Entry__c entry : session.Conversation_Entries__r) {
                if (entryCount >= limitCount) {
                    break;
                }
                
                ConversationEntry ce = new ConversationEntry();
                ce.sessionId = session.Id;
                ce.entryId = entry.Id;
                ce.timestamp = entry.Timestamp__c;
                ce.messageType = entry.Message_Type__c;
                ce.content = entry.Message_Content__c;
                ce.provider = session.AI_Provider__c;
                ce.entryNumber = entry.Entry_Number__c;
                
                // Parse metadata
                if (String.isNotBlank(entry.Metadata__c)) {
                    try {
                        ce.metadata = (Map<String, Object>) JSON.deserializeUntyped(entry.Metadata__c);
                    } catch (Exception e) {
                        // Log but don't fail
                        ErrorLogService.logError('ConversationService', e, 'Failed to parse metadata');
                    }
                }
                
                history.add(ce);
                entryCount++;
            }
            
            if (entryCount >= limitCount) {
                break;
            }
        }
        
        return history;
    }
    
    /**
     * @description Close conversation session
     * @param sessionId The session ID
     * @param status Final status
     */
    public static void closeSession(Id sessionId, String status) {
        if (sessionId == null) {
            return;
        }
        
        AI_Conversation_Session__c session = new AI_Conversation_Session__c(
            Id = sessionId,
            Status__c = String.isNotBlank(status) ? status : 'Completed',
            End_Time__c = DateTime.now()
        );
        
        update SecurityUtils.stripInaccessibleRecords(
            AccessType.UPDATABLE,
            new List<AI_Conversation_Session__c>{session}
        )[0];
    }
    
    /**
     * @description Archive old conversations
     * @param daysToKeep Number of days to keep conversations
     */
    @future
    public static void archiveOldConversations(Integer daysToKeep) {
        DateTime cutoffDate = DateTime.now().addDays(-daysToKeep);
        
        // Get old sessions
        List<AI_Conversation_Session__c> oldSessions = [
            SELECT Id
            FROM AI_Conversation_Session__c
            WHERE End_Time__c < :cutoffDate
            AND Status__c IN ('Completed', 'Abandoned', 'Error')
            WITH SECURITY_ENFORCED
            LIMIT 10000
        ];
        
        if (!oldSessions.isEmpty()) {
            // Delete old sessions (cascade delete will remove entries)
            delete SecurityUtils.stripInaccessibleRecords(
                AccessType.DELETABLE,
                oldSessions
            );
        }
    }
    
    // Helper methods
    
    /**
     * @description Close active sessions for a case
     */
    private static void closeActiveSessions(Id caseId, String provider) {
        List<AI_Conversation_Session__c> activeSessions = [
            SELECT Id
            FROM AI_Conversation_Session__c
            WHERE Case__c = :caseId
            AND AI_Provider__c = :provider
            AND Status__c = 'Active'
            WITH SECURITY_ENFORCED
        ];
        
        for (AI_Conversation_Session__c session : activeSessions) {
            session.Status__c = 'Completed';
            session.End_Time__c = DateTime.now();
        }
        
        if (!activeSessions.isEmpty()) {
            update SecurityUtils.stripInaccessibleRecords(
                AccessType.UPDATABLE,
                activeSessions
            );
        }
    }
    
    /**
     * @description Create continuation session when current session is full
     */
    private static AI_Conversation_Session__c createContinuationSession(AI_Conversation_Session__c currentSession) {
        // Close current session
        closeSession(currentSession.Id, 'Completed');
        
        // Get case info from current session
        AI_Conversation_Session__c sessionWithCase = [
            SELECT Case__c, AI_Provider__c
            FROM AI_Conversation_Session__c
            WHERE Id = :currentSession.Id
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        
        // Create new session
        return createNewSession(sessionWithCase.Case__c, sessionWithCase.AI_Provider__c);
    }
    
    /**
     * @description Inner class for conversation entry
     */
    public class ConversationEntry {
        @AuraEnabled public Id sessionId { get; set; }
        @AuraEnabled public Id entryId { get; set; }
        @AuraEnabled public DateTime timestamp { get; set; }
        @AuraEnabled public String messageType { get; set; }
        @AuraEnabled public String content { get; set; }
        @AuraEnabled public String provider { get; set; }
        @AuraEnabled public Decimal entryNumber { get; set; }
        @AuraEnabled public Map<String, Object> metadata { get; set; }
    }
}