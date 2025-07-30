/**
 * @description REST endpoint for receiving webhook callbacks from AI providers
 * @author RouteLogic Team
 * @date 2025-01-17
 */
@namespaceAccessible
@RestResource(urlMapping='/services/apexrest/ai/webhook/*')
global with sharing class AIWebhookService {
    
    /**
     * @description Handle incoming webhook POST requests
     */
    @HttpPost
    global static void handleCallback() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        try {
            // Enforce license check for webhook processing
            LicenseManager.enforceLicense();
            
            // Set response headers
            res.addHeader('Content-Type', 'application/json');
            
            // Extract provider from URL path
            String provider = extractProviderFromPath(req.requestURI);
            if (String.isBlank(provider)) {
                sendErrorResponse(res, 400, 'Invalid provider in URL path');
                return;
            }
            
            // Log incoming webhook
            logWebhookRequest(provider, req);
            
            // Validate webhook signature
            if (!validateWebhookSignature(req, provider)) {
                sendErrorResponse(res, 401, 'Invalid webhook signature');
                return;
            }
            
            // Parse webhook payload
            String requestBody = req.requestBody.toString();
            WebhookPayload payload = parsePayload(requestBody, provider);
            
            if (payload == null) {
                sendErrorResponse(res, 400, 'Invalid payload format');
                return;
            }
            
            // Create platform event for async processing
            AI_Webhook_Response__e webhookEvent = new AI_Webhook_Response__e(
                Callback_Id__c = payload.callbackId,
                Provider_Name__c = provider,
                Response_Data__c = JSON.serialize(payload.data),
                Status__c = payload.status,
                Timestamp__c = DateTime.now(),
                Event_Type__c = payload.eventType,
                Case_Id__c = payload.caseId,
                Correlation_Id__c = payload.correlationId
            );
            
            // Publish platform event
            Database.SaveResult sr = EventBus.publish(webhookEvent);
            
            if (sr.isSuccess()) {
                // Send success response
                WebhookResponse response = new WebhookResponse();
                response.success = true;
                response.eventId = sr.getId();
                response.message = 'Webhook processed successfully';
                
                res.statusCode = 200;
                res.responseBody = Blob.valueOf(JSON.serialize(response));
                
                // Log successful processing
                logWebhookSuccess(provider, payload.callbackId);
            } else {
                // Handle publish failure
                String error = sr.getErrors()[0].getMessage();
                sendErrorResponse(res, 500, 'Failed to process webhook: ' + error);
                logWebhookError(provider, error);
            }
            
        } catch (Exception e) {
            // Log error and return failure response
            ErrorLogService.logError('AIWebhookService.handleCallback', e, req.requestURI);
            sendErrorResponse(res, 500, 'Internal error: ' + e.getMessage());
        }
    }
    
    /**
     * @description Extract provider name from URL path
     */
    private static String extractProviderFromPath(String uri) {
        // Expected format: /services/apexrest/ai/webhook/{provider}
        if (String.isBlank(uri)) {
            return null;
        }
        
        List<String> pathParts = uri.split('/');
        if (pathParts.size() >= 6) {
            return pathParts[5].toLowerCase(); // Provider should be at index 5
        }
        
        return null;
    }
    
    /**
     * @description Validate webhook signature based on provider
     */
    private static Boolean validateWebhookSignature(RestRequest req, String provider) {
        Map<String, String> headers = req.headers;
        String payload = req.requestBody != null ? req.requestBody.toString() : '';
        
        try {
            // Get appropriate signature header based on provider
            String signature;
            switch on provider.toLowerCase() {
                when 'ada' {
                    signature = headers.get('X-Ada-Signature');
                }
                when 'intercom' {
                    signature = headers.get('X-Hub-Signature-256');
                }
                when else {
                    return false;
                }
            }
            
            // Use factory to validate signature
            return AISecurityProviderFactory.validateWebhookSignature(provider, payload, signature);
        } catch (Exception e) {
            ErrorLogService.logError('Webhook signature validation failed', e, provider);
            return false;
        }
    }
    
    /**
     * @description Parse webhook payload based on provider format
     */
    private static WebhookPayload parsePayload(String requestBody, String provider) {
        try {
            WebhookPayload payload = new WebhookPayload();
            Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(requestBody);
            
            switch on provider.toLowerCase() {
                when 'ada' {
                    return parseAdaPayload(jsonMap);
                }
                when 'intercom' {
                    return parseIntercomPayload(jsonMap);
                }
                when else {
                    return null;
                }
            }
        } catch (Exception e) {
            ErrorLogService.logError('Webhook payload parsing failed', e, provider);
            return null;
        }
    }
    
    /**
     * @description Parse Ada webhook payload
     */
    private static WebhookPayload parseAdaPayload(Map<String, Object> jsonMap) {
        WebhookPayload payload = new WebhookPayload();
        
        payload.callbackId = (String) jsonMap.get('callback_id');
        payload.eventType = (String) jsonMap.get('event');
        payload.status = (String) jsonMap.get('status');
        payload.correlationId = (String) jsonMap.get('conversation_id');
        
        // Extract case ID from metadata
        Map<String, Object> metadata = (Map<String, Object>) jsonMap.get('metadata');
        if (metadata != null) {
            payload.caseId = (String) metadata.get('case_id');
        }
        
        // Store full payload data
        payload.data = jsonMap;
        
        return payload;
    }
    
    /**
     * @description Parse Intercom webhook payload
     */
    private static WebhookPayload parseIntercomPayload(Map<String, Object> jsonMap) {
        WebhookPayload payload = new WebhookPayload();
        
        payload.eventType = (String) jsonMap.get('type');
        payload.callbackId = (String) jsonMap.get('id');
        
        // Extract data from nested structure
        Map<String, Object> data = (Map<String, Object>) jsonMap.get('data');
        if (data != null) {
            Map<String, Object> item = (Map<String, Object>) data.get('item');
            if (item != null) {
                payload.correlationId = (String) item.get('id');
                payload.status = (String) item.get('state');
                
                // Extract case ID from custom attributes
                Map<String, Object> customAttrs = (Map<String, Object>) item.get('custom_attributes');
                if (customAttrs != null) {
                    payload.caseId = (String) customAttrs.get('salesforce_case_id');
                }
            }
        }
        
        // Store full payload data
        payload.data = jsonMap;
        
        return payload;
    }
    
    /**
     * @description Send error response
     */
    private static void sendErrorResponse(RestResponse res, Integer statusCode, String message) {
        WebhookResponse response = new WebhookResponse();
        response.success = false;
        response.error = message;
        
        res.statusCode = statusCode;
        res.responseBody = Blob.valueOf(JSON.serialize(response));
    }
    
    /**
     * @description Log webhook request
     */
    private static void logWebhookRequest(String provider, RestRequest req) {
        // Log webhook request for monitoring
        AI_Webhook_Log__c log = new AI_Webhook_Log__c(
            Provider__c = provider,
            Request_Headers__c = JSON.serialize(req.headers),
            Request_URI__c = req.requestURI,
            Timestamp__c = DateTime.now(),
            Status__c = 'Received'
        );
        
        // Insert without sharing for logging
        insertWebhookLog(log);
    }
    
    /**
     * @description Log successful webhook processing
     */
    private static void logWebhookSuccess(String provider, String callbackId) {
        AI_Webhook_Log__c log = new AI_Webhook_Log__c(
            Provider__c = provider,
            Callback_Id__c = callbackId,
            Status__c = 'Success',
            Timestamp__c = DateTime.now()
        );
        
        insertWebhookLog(log);
    }
    
    /**
     * @description Log webhook error
     */
    private static void logWebhookError(String provider, String error) {
        AI_Webhook_Log__c log = new AI_Webhook_Log__c(
            Provider__c = provider,
            Status__c = 'Error',
            Error_Message__c = error,
            Timestamp__c = DateTime.now()
        );
        
        insertWebhookLog(log);
    }
    
    /**
     * @description Insert webhook log without sharing
     */
    private static void insertWebhookLog(AI_Webhook_Log__c log) {
        try {
            // Apply FLS before insert
            List<AI_Webhook_Log__c> logsToInsert = new List<AI_Webhook_Log__c>{log};
            logsToInsert = SecurityUtils.stripInaccessibleRecords(
                AccessType.CREATABLE,
                logsToInsert
            );
            
            // Insert without sharing for logging purposes
            if (!logsToInsert.isEmpty()) {
                Database.insert(logsToInsert[0], false);
            }
        } catch (Exception e) {
            // Don't fail webhook processing due to logging error
            System.debug('Failed to insert webhook log: ' + e.getMessage());
        }
    }
    
    /**
     * @description Inner class for webhook payload
     */
    public class WebhookPayload {
        public String callbackId { get; set; }
        public String eventType { get; set; }
        public String status { get; set; }
        public String caseId { get; set; }
        public String correlationId { get; set; }
        public Map<String, Object> data { get; set; }
    }
    
    /**
     * @description Inner class for webhook response
     */
    global class WebhookResponse {
        public Boolean success { get; set; }
        public String eventId { get; set; }
        public String message { get; set; }
        public String error { get; set; }
    }
}