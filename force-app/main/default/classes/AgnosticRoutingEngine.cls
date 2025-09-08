/**
 * @description Agnostic Routing Engine - Core IP for AI chatbot-to-human handoff orchestration
 * @author RouteLogic Team
 * @date 2025-01-21
 * @version 4.0.0
 * 
 * This class contains the core routing intelligence that is completely decoupled from
 * any specific AI provider implementation. It focuses exclusively on making intelligent
 * handoff decisions based on case context enrichment.
 * 
 * v4.0.0 Security Enhancements:
 * - Enhanced Field-Level Security validation
 * - Comprehensive input sanitization
 * - Improved error handling with security context
 * - Multi-object support preparation
 */
public inherited sharing class AgnosticRoutingEngine {
    
    // Core routing constants
    private static final String HIGH_PRIORITY = 'High';
    private static final String MEDIUM_PRIORITY = 'Medium';
    private static final String LOW_PRIORITY = 'Low';
    
    // Escalation thresholds
    private static final Integer URGENT_RESPONSE_THRESHOLD_HOURS = 2;
    private static final Integer STANDARD_RESPONSE_THRESHOLD_HOURS = 24;
    private static final Integer LOW_RESPONSE_THRESHOLD_HOURS = 72;
    
    /**
     * @description Make routing decision based on enriched case context
     * @param caseId The case ID to route
     * @return RoutingDecision containing routing intelligence
     */
    public static RoutingDecision makeRoutingDecision(Id caseId) {
        if (caseId == null) {
            throw new IllegalArgumentException('Case ID cannot be null');
        }
        
        // Enrich case context
        EnrichedCaseContext context = enrichCaseContext(caseId);
        
        // Apply routing intelligence
        return applyRoutingLogic(context);
    }
    
    /**
     * @description Make bulk routing decisions for multiple cases
     * @param caseIds Set of case IDs to route
     * @return Map of case ID to routing decision
     */
    public static Map<Id, RoutingDecision> makeBulkRoutingDecisions(Set<Id> caseIds) {
        if (caseIds == null || caseIds.isEmpty()) {
            return new Map<Id, RoutingDecision>();
        }
        
        Map<Id, RoutingDecision> decisions = new Map<Id, RoutingDecision>();
        
        // Bulk enrich case contexts
        Map<Id, EnrichedCaseContext> contexts = bulkEnrichCaseContexts(caseIds);
        
        // Apply routing logic to each context
        for (Id caseId : contexts.keySet()) {
            decisions.put(caseId, applyRoutingLogic(contexts.get(caseId)));
        }
        
        return decisions;
    }
    
    /**
     * @description Enrich case context with all relevant data for routing decisions
     * @param caseId The case ID to enrich
     * @return EnrichedCaseContext with all routing-relevant data
     */
    private static EnrichedCaseContext enrichCaseContext(Id caseId) {
        // Validate input
        if (caseId == null) {
            throw new IllegalArgumentException('Case ID cannot be null');
        }
        
        // Validate field-level security for Case object
        Set<String> caseFields = new Set<String>{
            'Id', 'CaseNumber', 'Subject', 'Description', 'Priority', 'Status', 'Origin',
            'Type', 'Reason', 'CreatedDate', 'LastModifiedDate', 'ClosedDate',
            'AccountId', 'ContactId', 'OwnerId', 'ParentId',
            'AI_Sentiment__c', 'AI_Intent__c', 'AI_Processing_Status__c',
            'AI_Last_Analysis__c', 'AI_Suggested_Response__c'
        };
        
        try {
            RouteLogicSecurityUtils.validateFieldAccess('Case', caseFields, RouteLogicSecurityUtils.AccessType.READABLE);
        } catch (RouteLogicSecurityUtils.SecurityException e) {
            throw new SecurityException('Insufficient permissions to access Case fields: ' + e.getMessage());
        }
        
        List<Case> cases = [
            SELECT Id, CaseNumber, Subject, Description, Priority, Status, Origin,
                   Type, Reason, CreatedDate, LastModifiedDate, ClosedDate,
                   AccountId, ContactId, OwnerId, ParentId,
                   Account.Name, Account.Type, Account.Industry, Account.AnnualRevenue,
                   Contact.Name, Contact.Email, Contact.Phone,
                   Owner.Name, Owner.Type,
                   AI_Sentiment__c, AI_Intent__c, AI_Processing_Status__c,
                   AI_Last_Analysis__c, AI_Suggested_Response__c,
                   (SELECT Id, CommentBody, CreatedDate, CreatedBy.Name 
                    FROM CaseComments 
                    ORDER BY CreatedDate DESC 
                    LIMIT 10)
            FROM Case
            WHERE Id = :caseId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        
        if (cases.isEmpty()) {
            throw new NotFoundException('Case not found or not accessible: ' + caseId);
        }
        
        Case c = cases[0];
        EnrichedCaseContext context = new EnrichedCaseContext();
        
        // Basic case data with input sanitization for user-provided fields
        context.caseId = c.Id;
        context.caseNumber = c.CaseNumber;
        context.subject = RouteLogicSecurityUtils.sanitizeInput(c.Subject);
        context.description = RouteLogicSecurityUtils.sanitizeInput(c.Description);
        context.priority = c.Priority;
        context.status = c.Status;
        context.origin = c.Origin;
        context.type = c.Type;
        context.reason = c.Reason;
        context.createdDate = c.CreatedDate;
        context.lastModifiedDate = c.LastModifiedDate;
        context.closedDate = c.ClosedDate;
        
        // Account context with sanitization
        if (c.Account != null) {
            context.accountName = RouteLogicSecurityUtils.sanitizeInput(c.Account.Name);
            context.accountType = c.Account.Type;
            context.accountIndustry = c.Account.Industry;
            context.accountRevenue = c.Account.AnnualRevenue;
        }
        
        // Contact context with sanitization
        if (c.Contact != null) {
            context.contactName = RouteLogicSecurityUtils.sanitizeInput(c.Contact.Name);
            context.contactEmail = RouteLogicSecurityUtils.sanitizeInput(c.Contact.Email);
            context.contactPhone = RouteLogicSecurityUtils.sanitizeInput(c.Contact.Phone);
        }
        
        // Owner context
        if (c.Owner != null) {
            context.ownerName = c.Owner.Name;
            context.ownerType = c.Owner.Type;
        }
        
        // AI analysis context
        context.aiSentiment = c.AI_Sentiment__c;
        context.aiIntent = c.AI_Intent__c;
        context.aiProcessingStatus = c.AI_Processing_Status__c;
        context.aiLastAnalysis = c.AI_Last_Analysis__c;
        context.aiSuggestedResponse = c.AI_Suggested_Response__c;
        
        // Case history context
        context.commentCount = c.CaseComments.size();
        context.recentComments = new List<String>();
        for (CaseComment comment : c.CaseComments) {
            context.recentComments.add(comment.CommentBody);
        }
        
        // Calculate derived metrics
        context.ageInHours = calculateAgeInHours(c.CreatedDate);
        context.timeSinceLastUpdate = calculateTimeSinceLastUpdate(c.LastModifiedDate);
        context.isEscalated = c.ParentId != null;
        context.hasAIAnalysis = c.AI_Last_Analysis__c != null;
        
        return context;
    }
    
    /**
     * @description Bulk enrich case contexts for efficient processing
     * @param caseIds Set of case IDs to enrich
     * @return Map of case ID to enriched context
     */
    private static Map<Id, EnrichedCaseContext> bulkEnrichCaseContexts(Set<Id> caseIds) {
        Map<Id, EnrichedCaseContext> contexts = new Map<Id, EnrichedCaseContext>();
        
        List<Case> cases = [
            SELECT Id, CaseNumber, Subject, Description, Priority, Status, Origin,
                   Type, Reason, CreatedDate, LastModifiedDate, ClosedDate,
                   AccountId, ContactId, OwnerId, ParentId,
                   Account.Name, Account.Type, Account.Industry, Account.AnnualRevenue,
                   Contact.Name, Contact.Email, Contact.Phone,
                   Owner.Name, Owner.Type,
                   AI_Sentiment__c, AI_Intent__c, AI_Processing_Status__c,
                   AI_Last_Analysis__c, AI_Suggested_Response__c
            FROM Case
            WHERE Id IN :caseIds
            WITH SECURITY_ENFORCED
        ];
        
        // Get case comments in bulk
        Map<Id, List<CaseComment>> commentsMap = new Map<Id, List<CaseComment>>();
        for (CaseComment comment : [
            SELECT Id, ParentId, CommentBody, CreatedDate, CreatedBy.Name
            FROM CaseComment
            WHERE ParentId IN :caseIds
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
        ]) {
            if (!commentsMap.containsKey(comment.ParentId)) {
                commentsMap.put(comment.ParentId, new List<CaseComment>());
            }
            if (commentsMap.get(comment.ParentId).size() < 10) {
                commentsMap.get(comment.ParentId).add(comment);
            }
        }
        
        // Build contexts
        for (Case c : cases) {
            EnrichedCaseContext context = new EnrichedCaseContext();
            
            // Basic case data
            context.caseId = c.Id;
            context.caseNumber = c.CaseNumber;
            context.subject = c.Subject;
            context.description = c.Description;
            context.priority = c.Priority;
            context.status = c.Status;
            context.origin = c.Origin;
            context.type = c.Type;
            context.reason = c.Reason;
            context.createdDate = c.CreatedDate;
            context.lastModifiedDate = c.LastModifiedDate;
            context.closedDate = c.ClosedDate;
            
            // Account context
            if (c.Account != null) {
                context.accountName = c.Account.Name;
                context.accountType = c.Account.Type;
                context.accountIndustry = c.Account.Industry;
                context.accountRevenue = c.Account.AnnualRevenue;
            }
            
            // Contact context
            if (c.Contact != null) {
                context.contactName = c.Contact.Name;
                context.contactEmail = c.Contact.Email;
                context.contactPhone = c.Contact.Phone;
            }
            
            // Owner context
            if (c.Owner != null) {
                context.ownerName = c.Owner.Name;
                context.ownerType = c.Owner.Type;
            }
            
            // AI analysis context
            context.aiSentiment = c.AI_Sentiment__c;
            context.aiIntent = c.AI_Intent__c;
            context.aiProcessingStatus = c.AI_Processing_Status__c;
            context.aiLastAnalysis = c.AI_Last_Analysis__c;
            context.aiSuggestedResponse = c.AI_Suggested_Response__c;
            
            // Case history context
            List<CaseComment> caseComments = commentsMap.get(c.Id);
            if (caseComments != null) {
                context.commentCount = caseComments.size();
                context.recentComments = new List<String>();
                for (CaseComment comment : caseComments) {
                    context.recentComments.add(comment.CommentBody);
                }
            } else {
                context.commentCount = 0;
                context.recentComments = new List<String>();
            }
            
            // Calculate derived metrics
            context.ageInHours = calculateAgeInHours(c.CreatedDate);
            context.timeSinceLastUpdate = calculateTimeSinceLastUpdate(c.LastModifiedDate);
            context.isEscalated = c.ParentId != null;
            context.hasAIAnalysis = c.AI_Last_Analysis__c != null;
            
            contexts.put(c.Id, context);
        }
        
        return contexts;
    }
    
    /**
     * @description Apply core routing logic to enriched case context
     * @param context The enriched case context
     * @return RoutingDecision with routing intelligence
     */
    private static RoutingDecision applyRoutingLogic(EnrichedCaseContext context) {
        RoutingDecision decision = new RoutingDecision();
        decision.caseId = context.caseId;
        decision.routingTimestamp = DateTime.now();
        
        // Determine target skill group based on case attributes
        decision.targetSkillGroup = determineTargetSkillGroup(context);
        
        // Calculate suggested priority based on multiple factors
        decision.suggestedPriority = calculateSuggestedPriority(context);
        
        // Determine escalation reason if escalation is needed
        decision.escalationReason = determineEscalationReason(context);
        
        // Generate summary for agent handoff
        decision.summaryForAgent = generateAgentSummary(context);
        
        // Calculate routing confidence score
        decision.confidenceScore = calculateConfidenceScore(context);
        
        // Determine if immediate handoff is required
        decision.requiresImmediateHandoff = requiresImmediateHandoff(context);
        
        return decision;
    }
    
    /**
     * @description Determine target skill group based on case context
     * @param context The enriched case context
     * @return Target skill group name
     */
    private static String determineTargetSkillGroup(EnrichedCaseContext context) {
        // Technical issues
        if (isTechnicalIssue(context)) {
            if (context.priority == HIGH_PRIORITY) {
                return 'Technical Support - Tier 2';
            }
            return 'Technical Support - Tier 1';
        }
        
        // Billing and financial issues
        if (isBillingIssue(context)) {
            if (context.accountRevenue != null && context.accountRevenue > 1000000) {
                return 'Enterprise Billing Support';
            }
            return 'Billing Support';
        }
        
        // Sales and account management
        if (isSalesIssue(context)) {
            if (context.accountType == 'Customer - Direct') {
                return 'Account Management';
            }
            return 'Sales Support';
        }
        
        // Escalated or complex cases
        if (context.isEscalated || context.commentCount > 5) {
            return 'Escalation Team';
        }
        
        // High-value accounts
        if (context.accountRevenue != null && context.accountRevenue > 5000000) {
            return 'VIP Support';
        }
        
        // Default to general support
        return 'General Support';
    }
    
    /**
     * @description Calculate suggested priority based on multiple factors
     * @param context The enriched case context
     * @return Suggested priority level
     */
    private static String calculateSuggestedPriority(EnrichedCaseContext context) {
        Integer priorityScore = 0;
        
        // Current priority weight
        if (context.priority == HIGH_PRIORITY) {
            priorityScore += 30;
        } else if (context.priority == MEDIUM_PRIORITY) {
            priorityScore += 15;
        }
        
        // Age factor
        if (context.ageInHours > URGENT_RESPONSE_THRESHOLD_HOURS) {
            priorityScore += 20;
        } else if (context.ageInHours > STANDARD_RESPONSE_THRESHOLD_HOURS) {
            priorityScore += 10;
        }
        
        // Account value factor
        if (context.accountRevenue != null) {
            if (context.accountRevenue > 5000000) {
                priorityScore += 25;
            } else if (context.accountRevenue > 1000000) {
                priorityScore += 15;
            }
        }
        
        // Sentiment factor
        if (context.aiSentiment == 'Negative' || context.aiSentiment == 'Very Negative') {
            priorityScore += 15;
        }
        
        // Escalation factor
        if (context.isEscalated) {
            priorityScore += 20;
        }
        
        // Comment activity factor
        if (context.commentCount > 3) {
            priorityScore += 10;
        }
        
        // Determine priority based on score
        if (priorityScore >= 50) {
            return HIGH_PRIORITY;
        } else if (priorityScore >= 25) {
            return MEDIUM_PRIORITY;
        }
        
        return LOW_PRIORITY;
    }
    
    /**
     * @description Determine escalation reason if escalation is needed
     * @param context The enriched case context
     * @return Escalation reason or null if no escalation needed
     */
    private static String determineEscalationReason(EnrichedCaseContext context) {
        List<String> reasons = new List<String>();
        
        // Age-based escalation
        if (context.ageInHours > URGENT_RESPONSE_THRESHOLD_HOURS && context.priority == HIGH_PRIORITY) {
            reasons.add('High priority case exceeding response threshold');
        } else if (context.ageInHours > STANDARD_RESPONSE_THRESHOLD_HOURS && context.priority == MEDIUM_PRIORITY) {
            reasons.add('Medium priority case exceeding response threshold');
        } else if (context.ageInHours > LOW_RESPONSE_THRESHOLD_HOURS) {
            reasons.add('Case exceeding maximum response threshold');
        }
        
        // Sentiment-based escalation
        if (context.aiSentiment == 'Very Negative') {
            reasons.add('Very negative customer sentiment detected');
        }
        
        // Account value escalation
        if (context.accountRevenue != null && context.accountRevenue > 5000000) {
            reasons.add('High-value account requires priority attention');
        }
        
        // Activity-based escalation
        if (context.commentCount > 5) {
            reasons.add('High activity case requiring specialized attention');
        }
        
        // Technical complexity escalation
        if (isTechnicalIssue(context) && context.commentCount > 2) {
            reasons.add('Complex technical issue requiring advanced support');
        }
        
        return reasons.isEmpty() ? null : String.join(reasons, '; ');
    }
    
    /**
     * @description Generate summary for agent handoff
     * @param context The enriched case context
     * @return Summary text for agent
     */
    private static String generateAgentSummary(EnrichedCaseContext context) {
        List<String> summaryParts = new List<String>();
        
        // Case basics
        summaryParts.add('Case: ' + context.caseNumber + ' - ' + context.subject);
        
        // Customer context
        if (context.accountName != null) {
            summaryParts.add('Account: ' + context.accountName);
            if (context.accountRevenue != null) {
                summaryParts.add('Annual Revenue: $' + String.valueOf(context.accountRevenue));
            }
        }
        
        // AI insights
        if (context.aiSentiment != null) {
            summaryParts.add('Sentiment: ' + context.aiSentiment);
        }
        if (context.aiIntent != null) {
            summaryParts.add('Intent: ' + context.aiIntent);
        }
        
        // Case metrics
        summaryParts.add('Age: ' + context.ageInHours + ' hours');
        summaryParts.add('Comments: ' + context.commentCount);
        
        // Recent activity
        if (!context.recentComments.isEmpty()) {
            summaryParts.add('Latest Comment: ' + 
                (context.recentComments[0].length() > 100 ? 
                 context.recentComments[0].substring(0, 100) + '...' : 
                 context.recentComments[0]));
        }
        
        return String.join(summaryParts, ' | ');
    }
    
    /**
     * @description Calculate routing confidence score
     * @param context The enriched case context
     * @return Confidence score (0-100)
     */
    private static Integer calculateConfidenceScore(EnrichedCaseContext context) {
        Integer confidence = 50; // Base confidence
        
        // AI analysis boosts confidence
        if (context.hasAIAnalysis) {
            confidence += 20;
        }
        
        // Clear intent boosts confidence
        if (context.aiIntent != null && context.aiIntent != 'Unknown') {
            confidence += 15;
        }
        
        // Account data boosts confidence
        if (context.accountName != null) {
            confidence += 10;
        }
        
        // Case history boosts confidence
        if (context.commentCount > 0) {
            confidence += 5;
        }
        
        // Ensure confidence is within bounds
        return Math.min(100, Math.max(0, confidence));
    }
    
    /**
     * @description Determine if immediate handoff is required
     * @param context The enriched case context
     * @return True if immediate handoff is required
     */
    private static Boolean requiresImmediateHandoff(EnrichedCaseContext context) {
        // High priority cases older than threshold
        if (context.priority == HIGH_PRIORITY && context.ageInHours > URGENT_RESPONSE_THRESHOLD_HOURS) {
            return true;
        }
        
        // Very negative sentiment
        if (context.aiSentiment == 'Very Negative') {
            return true;
        }
        
        // High-value accounts with any issue
        if (context.accountRevenue != null && context.accountRevenue > 10000000) {
            return true;
        }
        
        // Already escalated cases
        if (context.isEscalated) {
            return true;
        }
        
        return false;
    }
    
    // Helper methods for case classification
    
    private static Boolean isTechnicalIssue(EnrichedCaseContext context) {
        String subject = context.subject != null ? context.subject.toLowerCase() : '';
        String description = context.description != null ? context.description.toLowerCase() : '';
        String type = context.type != null ? context.type.toLowerCase() : '';
        
        Set<String> technicalKeywords = new Set<String>{
            'error', 'bug', 'crash', 'performance', 'slow', 'timeout', 'integration',
            'api', 'sync', 'connection', 'login', 'authentication', 'technical'
        };
        
        for (String keyword : technicalKeywords) {
            if (subject.contains(keyword) || description.contains(keyword) || type.contains(keyword)) {
                return true;
            }
        }
        
        return context.type == 'Technical Issue' || context.reason == 'Performance';
    }
    
    private static Boolean isBillingIssue(EnrichedCaseContext context) {
        String subject = context.subject != null ? context.subject.toLowerCase() : '';
        String description = context.description != null ? context.description.toLowerCase() : '';
        String type = context.type != null ? context.type.toLowerCase() : '';
        
        Set<String> billingKeywords = new Set<String>{
            'billing', 'invoice', 'payment', 'charge', 'refund', 'credit',
            'subscription', 'renewal', 'pricing', 'cost'
        };
        
        for (String keyword : billingKeywords) {
            if (subject.contains(keyword) || description.contains(keyword) || type.contains(keyword)) {
                return true;
            }
        }
        
        return context.type == 'Billing' || context.reason == 'Billing Problem';
    }
    
    private static Boolean isSalesIssue(EnrichedCaseContext context) {
        String subject = context.subject != null ? context.subject.toLowerCase() : '';
        String description = context.description != null ? context.description.toLowerCase() : '';
        String type = context.type != null ? context.type.toLowerCase() : '';
        
        Set<String> salesKeywords = new Set<String>{
            'sales', 'quote', 'proposal', 'contract', 'upgrade', 'downgrade',
            'feature request', 'demo', 'trial', 'purchase'
        };
        
        for (String keyword : salesKeywords) {
            if (subject.contains(keyword) || description.contains(keyword) || type.contains(keyword)) {
                return true;
            }
        }
        
        return context.type == 'Feature Request' || context.reason == 'New product information';
    }
    
    // Utility methods
    
    private static Integer calculateAgeInHours(DateTime createdDate) {
        if (createdDate == null) {
            return 0;
        }
        
        Long diffInMs = DateTime.now().getTime() - createdDate.getTime();
        return Integer.valueOf(diffInMs / (1000 * 60 * 60));
    }
    
    private static Integer calculateTimeSinceLastUpdate(DateTime lastModifiedDate) {
        if (lastModifiedDate == null) {
            return 0;
        }
        
        Long diffInMs = DateTime.now().getTime() - lastModifiedDate.getTime();
        return Integer.valueOf(diffInMs / (1000 * 60 * 60));
    }
    
    // Inner classes
    
    /**
     * @description Enriched case context containing all data needed for routing decisions
     */
    public class EnrichedCaseContext {
        public Id caseId;
        public String caseNumber;
        public String subject;
        public String description;
        public String priority;
        public String status;
        public String origin;
        public String type;
        public String reason;
        public DateTime createdDate;
        public DateTime lastModifiedDate;
        public DateTime closedDate;
        
        // Account context
        public String accountName;
        public String accountType;
        public String accountIndustry;
        public Decimal accountRevenue;
        
        // Contact context
        public String contactName;
        public String contactEmail;
        public String contactPhone;
        
        // Owner context
        public String ownerName;
        public String ownerType;
        
        // AI analysis context
        public String aiSentiment;
        public String aiIntent;
        public String aiProcessingStatus;
        public DateTime aiLastAnalysis;
        public String aiSuggestedResponse;
        
        // Case history context
        public Integer commentCount;
        public List<String> recentComments;
        
        // Derived metrics
        public Integer ageInHours;
        public Integer timeSinceLastUpdate;
        public Boolean isEscalated;
        public Boolean hasAIAnalysis;
    }
    
    /**
     * @description Routing decision containing all routing intelligence
     */
    public class RoutingDecision {
        public Id caseId;
        public String targetSkillGroup;
        public String suggestedPriority;
        public String escalationReason;
        public String summaryForAgent;
        public Integer confidenceScore;
        public Boolean requiresImmediateHandoff;
        public DateTime routingTimestamp;
    }
    
    // Custom exceptions
    public class NotFoundException extends Exception {}
    public class SecurityException extends Exception {}
}

