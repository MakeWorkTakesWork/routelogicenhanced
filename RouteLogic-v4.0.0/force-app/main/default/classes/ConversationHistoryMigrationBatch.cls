/**
 * @description Batch job to migrate existing conversation history to parent-child model
 * @author RouteLogic Team
 * @date 2025-01-17
 */
public class ConversationHistoryMigrationBatch implements Database.Batchable<SObject>, Database.Stateful {
    
    private Integer recordsProcessed = 0;
    private Integer recordsFailed = 0;
    private List<String> errors = new List<String>();
    
    /**
     * @description Start method to query old conversation history records
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Query old conversation history records that haven't been migrated
        return Database.getQueryLocator([
            SELECT Id, Case__c, Conversation_Data__c, Start_Time__c, End_Time__c, 
                   Message_Count__c, Provider__c, Is_Migrated__c
            FROM AI_Conversation_History__c
            WHERE Is_Migrated__c = false
            AND Conversation_Data__c != null
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
        ]);
    }
    
    /**
     * @description Execute method to process batch of records
     */
    public void execute(Database.BatchableContext bc, List<AI_Conversation_History__c> scope) {
        List<AI_Conversation_Session__c> sessionsToInsert = new List<AI_Conversation_Session__c>();
        List<AI_Conversation_Entry__c> entriesToInsert = new List<AI_Conversation_Entry__c>();
        List<AI_Conversation_History__c> historyToUpdate = new List<AI_Conversation_History__c>();
        
        for (AI_Conversation_History__c history : scope) {
            try {
                // Create session
                AI_Conversation_Session__c session = new AI_Conversation_Session__c(
                    Case__c = history.Case__c,
                    Start_Time__c = history.Start_Time__c != null ? history.Start_Time__c : history.CreatedDate,
                    End_Time__c = history.End_Time__c,
                    Status__c = history.End_Time__c != null ? 'Completed' : 'Migrated',
                    Total_Messages__c = history.Message_Count__c != null ? history.Message_Count__c : 0,
                    AI_Provider__c = history.Provider__c != null ? history.Provider__c : 'Unknown'
                );
                
                sessionsToInsert.add(session);
                
            } catch (Exception e) {
                recordsFailed++;
                errors.add('Failed to process history ' + history.Id + ': ' + e.getMessage());
            }
        }
        
        // Insert sessions
        if (!sessionsToInsert.isEmpty()) {
            // Apply FLS before insert
            sessionsToInsert = SecurityUtils.stripInaccessibleRecords(
                AccessType.CREATABLE,
                sessionsToInsert
            );
            
            Database.SaveResult[] sessionResults = Database.insert(sessionsToInsert, false);
            
            // Process session results and create entries
            for (Integer i = 0; i < sessionResults.size(); i++) {
                if (sessionResults[i].isSuccess()) {
                    AI_Conversation_Session__c session = sessionsToInsert[i];
                    AI_Conversation_History__c history = scope[i];
                    
                    try {
                        // Parse conversation data and create entries
                        List<ConversationMessage> messages = parseConversationData(history.Conversation_Data__c);
                        Integer entryNumber = 1;
                        
                        for (ConversationMessage msg : messages) {
                            AI_Conversation_Entry__c entry = new AI_Conversation_Entry__c(
                                Session__c = session.Id,
                                Entry_Number__c = entryNumber++,
                                Timestamp__c = msg.timestamp != null ? msg.timestamp : DateTime.now(),
                                Message_Type__c = msg.messageType,
                                Message_Content__c = msg.content,
                                Metadata__c = msg.metadata != null ? JSON.serialize(msg.metadata) : null
                            );
                            
                            entriesToInsert.add(entry);
                        }
                        
                        // Mark history as migrated
                        history.Is_Migrated__c = true;
                        history.Migration_Date__c = DateTime.now();
                        historyToUpdate.add(history);
                        
                        recordsProcessed++;
                        
                    } catch (Exception e) {
                        recordsFailed++;
                        errors.add('Failed to create entries for session ' + session.Id + ': ' + e.getMessage());
                    }
                } else {
                    recordsFailed++;
                    errors.add('Failed to create session: ' + sessionResults[i].getErrors()[0].getMessage());
                }
            }
        }
        
        // Insert entries
        if (!entriesToInsert.isEmpty()) {
            // Apply FLS before insert
            entriesToInsert = SecurityUtils.stripInaccessibleRecords(
                AccessType.CREATABLE,
                entriesToInsert
            );
            
            Database.SaveResult[] entryResults = Database.insert(entriesToInsert, false);
            
            // Log any entry insertion failures
            for (Database.SaveResult sr : entryResults) {
                if (!sr.isSuccess()) {
                    errors.add('Failed to insert entry: ' + sr.getErrors()[0].getMessage());
                }
            }
        }
        
        // Update migrated history records
        if (!historyToUpdate.isEmpty()) {
            // Apply FLS before update
            historyToUpdate = SecurityUtils.stripInaccessibleRecords(
                AccessType.UPDATABLE,
                historyToUpdate
            );
            
            Database.update(historyToUpdate, false);
        }
    }
    
    /**
     * @description Finish method to send summary email
     */
    public void finish(Database.BatchableContext bc) {
        // Send summary email
        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems
            FROM AsyncApexJob
            WHERE Id = :bc.getJobId()
        ];
        
        String subject = 'Conversation History Migration ' + 
                        (job.NumberOfErrors > 0 ? 'Completed with Errors' : 'Completed Successfully');
        
        String body = 'Migration Summary:\n\n' +
                     'Total Records: ' + job.TotalJobItems + '\n' +
                     'Records Processed: ' + recordsProcessed + '\n' +
                     'Records Failed: ' + recordsFailed + '\n' +
                     'Job Errors: ' + job.NumberOfErrors + '\n\n';
        
        if (!errors.isEmpty()) {
            body += 'Errors (first 100):\n';
            for (Integer i = 0; i < Math.min(errors.size(), 100); i++) {
                body += errors[i] + '\n';
            }
        }
        
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new String[]{UserInfo.getUserEmail()});
        email.setSubject(subject);
        email.setPlainTextBody(body);
        email.setSaveAsActivity(false);
        
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{email});
    }
    
    /**
     * @description Parse conversation data from JSON
     */
    private List<ConversationMessage> parseConversationData(String jsonData) {
        List<ConversationMessage> messages = new List<ConversationMessage>();
        
        try {
            List<Object> jsonList = (List<Object>) JSON.deserializeUntyped(jsonData);
            
            for (Object obj : jsonList) {
                Map<String, Object> msgMap = (Map<String, Object>) obj;
                
                ConversationMessage msg = new ConversationMessage();
                
                // Parse timestamp
                if (msgMap.containsKey('timestamp')) {
                    Object timestampObj = msgMap.get('timestamp');
                    if (timestampObj instanceof Long) {
                        msg.timestamp = DateTime.newInstance((Long)timestampObj);
                    } else if (timestampObj instanceof String) {
                        msg.timestamp = DateTime.parse((String)timestampObj);
                    }
                }
                
                // Parse message type
                msg.messageType = msgMap.containsKey('type') ? 
                    capitalizeMessageType((String)msgMap.get('type')) : 'User';
                
                // Parse content
                msg.content = msgMap.containsKey('message') ? 
                    (String)msgMap.get('message') : 
                    (msgMap.containsKey('content') ? (String)msgMap.get('content') : '');
                
                // Store remaining fields as metadata
                Map<String, Object> metadata = new Map<String, Object>();
                for (String key : msgMap.keySet()) {
                    if (!new Set<String>{'timestamp', 'type', 'message', 'content'}.contains(key)) {
                        metadata.put(key, msgMap.get(key));
                    }
                }
                
                if (!metadata.isEmpty()) {
                    msg.metadata = metadata;
                }
                
                messages.add(msg);
            }
            
        } catch (Exception e) {
            // If parsing fails, create a single entry with the raw data
            ConversationMessage msg = new ConversationMessage();
            msg.timestamp = DateTime.now();
            msg.messageType = 'System';
            msg.content = 'Migrated conversation data';
            msg.metadata = new Map<String, Object>{'raw_data' => jsonData};
            messages.add(msg);
        }
        
        return messages;
    }
    
    /**
     * @description Capitalize message type for picklist value
     */
    private String capitalizeMessageType(String type) {
        if (String.isBlank(type)) {
            return 'User';
        }
        
        String lowerType = type.toLowerCase();
        switch on lowerType {
            when 'user' { return 'User'; }
            when 'ai' { return 'AI'; }
            when 'system' { return 'System'; }
            when 'agent' { return 'Agent'; }
            when 'bot' { return 'Bot'; }
            when else { return 'User'; }
        }
    }
    
    /**
     * @description Inner class for conversation message
     */
    private class ConversationMessage {
        public DateTime timestamp;
        public String messageType;
        public String content;
        public Map<String, Object> metadata;
    }
}