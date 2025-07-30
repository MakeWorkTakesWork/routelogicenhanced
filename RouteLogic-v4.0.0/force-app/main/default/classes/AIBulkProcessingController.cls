/**
 * @description Controller for AI Bulk Processing Lightning Web Components
 * @author RouteLogic Team
 * @date 2025-01-17
 */
@namespaceAccessible
public with sharing class AIBulkProcessingController {
    
    /**
     * @description Get current processing status for dashboard
     * @return ProcessingStatus object with current metrics
     */
    @AuraEnabled
    public static AIBulkProcessingCoordinator.ProcessingStatus getProcessingStatus() {
        try {
            // Enforce license check
            LicenseManager.enforceLicense();
            return AIBulkProcessingCoordinator.getProcessingStatus();
        } catch (DmlException e) {
            ErrorLogService.logError(
                'AIBulkProcessingController.getProcessingStatus',
                e,
                'Database error while getting processing status'
            );
            throw new AIHandledException('Failed to retrieve processing status due to database error');
        } catch (QueryException e) {
            ErrorLogService.logError(
                'AIBulkProcessingController.getProcessingStatus',
                e,
                'Query error while getting processing status'
            );
            throw new AIHandledException('Failed to retrieve processing status due to query error');
        } catch (Exception e) {
            ErrorLogService.logError(
                'AIBulkProcessingController.getProcessingStatus',
                e,
                'Unexpected error while getting processing status'
            );
            throw new AIHandledException('Failed to retrieve processing status');
        }
    }
    
    /**
     * @description Initiate bulk processing
     * @param batchSize Size of batch to process
     * @return Job ID if processing started, null if no pending requests
     */
    @AuraEnabled
    public static String initiateBulkProcessing(Integer batchSize) {
        try {
            LicenseManager.enforceLicense();
            // Ensure batchSize has a default value
            batchSize = Math.max(1, batchSize == null ? 200 : batchSize);
            Id jobId = AIBulkProcessingCoordinator.initiateBulkProcessing(batchSize);
            return jobId != null ? String.valueOf(jobId) : null;
        } catch (Exception e) {
            ErrorLogService.logError(
                'AIBulkProcessingController.initiateBulkProcessing',
                e,
                'Failed to initiate bulk processing'
            );
            throw new AIHandledException('Failed to initiate bulk processing');
        }
    }
    
    /**
     * @description Process retry queue
     * @return Number of retry requests processed
     */
    @AuraEnabled
    public static Integer processRetryQueue() {
        try {
            LicenseManager.enforceLicense();
            return AIBulkProcessingCoordinator.processRetryQueue();
        } catch (Exception e) {
            ErrorLogService.logError(
                'AIBulkProcessingController.processRetryQueue',
                e,
                'Failed to process retry queue'
            );
            throw new AIHandledException('Failed to process retry queue');
        }
    }
    
    /**
     * @description Cancel all active jobs
     * @return Number of jobs cancelled
     */
    @AuraEnabled
    public static Integer cancelAllJobs() {
        try {
            LicenseManager.enforceLicense();
            return AIBulkProcessingCoordinator.cancelAllJobs();
        } catch (Exception e) {
            ErrorLogService.logError(
                'AIBulkProcessingController.cancelAllJobs',
                e,
                'Failed to cancel jobs'
            );
            throw new AIHandledException('Failed to cancel jobs');
        }
    }
    
    /**
     * @description Get detailed processing metrics
     * @return List of recent processing metrics
     */
    @AuraEnabled
    public static List<ProcessingMetric> getDetailedMetrics() {
        try {
            LicenseManager.enforceLicense();
            // Calculate datetime cutoff to avoid timezone issues
            DateTime cutoff = DateTime.now().addDays(-7);
            List<AI_Bulk_Processing_Metrics__c> metrics = [
                SELECT Id, Batch_Id__c, Total_Requests__c, Successful_Requests__c,
                       Failed_Requests__c, Error_Requests__c, Rate_Limit_Exceeded__c,
                       Processing_Time_Ms__c, Average_Time_Per_Request__c, CreatedDate
                FROM AI_Bulk_Processing_Metrics__c
                WHERE CreatedDate >= :cutoff
                ORDER BY CreatedDate DESC
                LIMIT 50
                WITH SECURITY_ENFORCED
            ];
            
            List<ProcessingMetric> result = new List<ProcessingMetric>();
            
            for (AI_Bulk_Processing_Metrics__c metric : metrics) {
                ProcessingMetric pm = new ProcessingMetric();
                pm.batchId = metric.Batch_Id__c;
                pm.totalRequests = metric.Total_Requests__c != null ? metric.Total_Requests__c.intValue() : 0;
                pm.successfulRequests = metric.Successful_Requests__c != null ? metric.Successful_Requests__c.intValue() : 0;
                pm.failedRequests = metric.Failed_Requests__c != null ? metric.Failed_Requests__c.intValue() : 0;
                pm.errorRequests = metric.Error_Requests__c != null ? metric.Error_Requests__c.intValue() : 0;
                pm.rateLimitExceeded = metric.Rate_Limit_Exceeded__c != null ? metric.Rate_Limit_Exceeded__c.intValue() : 0;
                pm.processingTimeMs = metric.Processing_Time_Ms__c != null ? metric.Processing_Time_Ms__c.longValue() : 0;
                pm.averageTimePerRequest = metric.Average_Time_Per_Request__c != null ? metric.Average_Time_Per_Request__c : 0;
                pm.createdDate = metric.CreatedDate;
                pm.successRate = pm.totalRequests > 0 ? 
                    (Decimal.valueOf(pm.successfulRequests) / Decimal.valueOf(pm.totalRequests) * 100).setScale(1) : 0;
                
                result.add(pm);
            }
            
            return result;
        } catch (Exception e) {
            ErrorLogService.logError(
                'AIBulkProcessingController.getDetailedMetrics',
                e,
                'Failed to get detailed metrics'
            );
            throw new AIHandledException('Failed to retrieve detailed metrics');
        }
    }
    
    /**
     * @description Get active job information
     * @return List of active jobs
     */
    @AuraEnabled
    public static List<ActiveJob> getActiveJobs() {
        try {
            LicenseManager.enforceLicense();
            List<AsyncApexJob> jobs = [
                SELECT Id, JobType, Status, NumberOfErrors, JobItemsProcessed,
                       TotalJobItems, CreatedDate, CreatedBy.Name, ExtendedStatus
                FROM AsyncApexJob
                WHERE ApexClass.Name = 'AIBulkProcessingQueueable'
                AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
                ORDER BY CreatedDate DESC
                LIMIT 20
            ];
            
            List<ActiveJob> result = new List<ActiveJob>();
            
            for (AsyncApexJob job : jobs) {
                ActiveJob aj = new ActiveJob();
                aj.jobId = job.Id;
                aj.jobType = job.JobType;
                aj.status = job.Status;
                aj.numberOfErrors = job.NumberOfErrors != null ? job.NumberOfErrors : 0;
                aj.itemsProcessed = job.JobItemsProcessed != null ? job.JobItemsProcessed : 0;
                aj.totalItems = job.TotalJobItems != null ? job.TotalJobItems : 0;
                aj.createdDate = job.CreatedDate;
                aj.createdByName = job.CreatedBy.Name;
                aj.extendedStatus = job.ExtendedStatus;
                aj.progressPercentage = aj.totalItems > 0 ? 
                    (Decimal.valueOf(aj.itemsProcessed) / Decimal.valueOf(aj.totalItems) * 100).setScale(1) : 0;
                
                result.add(aj);
            }
            
            return result;
        } catch (Exception e) {
            ErrorLogService.logError(
                'AIBulkProcessingController.getActiveJobs',
                e,
                'Failed to get active jobs'
            );
            throw new AIHandledException('Failed to retrieve active jobs');
        }
    }
    
    /**
     * @description Force process specific cases
     * @param caseIds List of case IDs to process
     * @param provider AI provider to use
     * @return Job ID if processing started
     */
    @AuraEnabled
    public static String forceProcessCases(List<String> caseIds, String provider) {
        try {
            LicenseManager.enforceLicense();
            List<Id> caseIdList = new List<Id>();
            for (String caseId : caseIds) {
                caseIdList.add((Id) caseId);
            }
            
            Id jobId = AIBulkProcessingCoordinator.forceProcessCases(caseIdList, provider);
            return jobId != null ? String.valueOf(jobId) : null;
        } catch (Exception e) {
            ErrorLogService.logError(
                'AIBulkProcessingController.forceProcessCases',
                e,
                'Failed to force process cases'
            );
            throw new AIHandledException('Failed to force process cases');
        }
    }
    
    /**
     * @description Get available AI providers
     * @return List of provider names
     */
    @AuraEnabled
    public static List<String> getAvailableProviders() {
        try {
            LicenseManager.enforceLicense();
            List<AIProviderCredential__c> credentials = [
                SELECT Name
                FROM AIProviderCredential__c
                WHERE IsActive__c = true
                WITH SECURITY_ENFORCED
            ];
            
            List<String> providers = new List<String>();
            for (AIProviderCredential__c cred : credentials) {
                providers.add(cred.Name);
            }
            
            return providers;
        } catch (Exception e) {
            ErrorLogService.logError(
                'AIBulkProcessingController.getAvailableProviders',
                e,
                'Failed to get available providers'
            );
            throw new AIHandledException('Failed to retrieve available providers');
        }
    }
    
    /**
     * @description Wrapper class for processing metrics
     */
    @namespaceAccessible
    public class ProcessingMetric {
        @AuraEnabled public String batchId;
        @AuraEnabled public Integer totalRequests;
        @AuraEnabled public Integer successfulRequests;
        @AuraEnabled public Integer failedRequests;
        @AuraEnabled public Integer errorRequests;
        @AuraEnabled public Integer rateLimitExceeded;
        @AuraEnabled public Long processingTimeMs;
        @AuraEnabled public Decimal averageTimePerRequest;
        @AuraEnabled public DateTime createdDate;
        @AuraEnabled public Decimal successRate;
    }
    
    /**
     * @description Wrapper class for active jobs
     */
    @namespaceAccessible
    public class ActiveJob {
        @AuraEnabled public String jobId;
        @AuraEnabled public String jobType;
        @AuraEnabled public String status;
        @AuraEnabled public Integer numberOfErrors;
        @AuraEnabled public Integer itemsProcessed;
        @AuraEnabled public Integer totalItems;
        @AuraEnabled public DateTime createdDate;
        @AuraEnabled public String createdByName;
        @AuraEnabled public String extendedStatus;
        @AuraEnabled public Decimal progressPercentage;
    }
}