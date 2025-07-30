/**
 * @description Job tracking and monitoring system for RouteLogic Enhanced v4.0.0
 * @author RouteLogic Team
 * @date 2025-01-21
 * @version 4.0.0
 * 
 * This class provides comprehensive job tracking capabilities including:
 * - Job status monitoring
 * - Performance metrics
 * - Error tracking and reporting
 * - Job history and analytics
 */
public with sharing class RouteLogicJobTracker {
    
    // Job status constants
    public static final String STATUS_QUEUED = 'QUEUED';
    public static final String STATUS_PROCESSING = 'PROCESSING';
    public static final String STATUS_COMPLETED = 'COMPLETED';
    public static final String STATUS_FAILED = 'FAILED';
    public static final String STATUS_RETRY_SCHEDULED = 'RETRY_SCHEDULED';
    public static final String STATUS_CANCELLED = 'CANCELLED';
    
    // Cache for job statuses
    private static Map<String, JobStatus> jobStatusCache = new Map<String, JobStatus>();
    
    /**
     * @description Create or update a job tracking record
     * @param jobId Unique job identifier
     * @param jobType Type of job being processed
     * @param recordCount Number of records to process
     * @param status Current job status
     * @param retryCount Current retry count
     * @return JobStatus object
     */
    public static JobStatus createOrUpdateJob(String jobId, String jobType, Integer recordCount, 
                                            String status, Integer retryCount) {
        if (String.isBlank(jobId) || String.isBlank(jobType)) {
            throw new IllegalArgumentException('Job ID and job type cannot be null or empty');
        }
        
        JobStatus jobStatus = new JobStatus();
        jobStatus.jobId = jobId;
        jobStatus.jobType = jobType;
        jobStatus.recordCount = recordCount != null ? recordCount : 0;
        jobStatus.status = status;
        jobStatus.retryCount = retryCount != null ? retryCount : 0;
        jobStatus.createdDate = DateTime.now();
        jobStatus.lastUpdated = DateTime.now();
        jobStatus.processedCount = 0;
        jobStatus.errorMessage = '';
        
        // Cache the job status
        jobStatusCache.put(jobId, jobStatus);
        
        // In a real implementation, this would persist to a custom object
        // For now, we'll use platform events for real-time monitoring
        publishJobStatusEvent(jobStatus);
        
        return jobStatus;
    }
    
    /**
     * @description Update job status
     * @param jobId Job identifier
     * @param status New status
     * @param message Status message
     */
    public static void updateJobStatus(String jobId, String status, String message) {
        if (String.isBlank(jobId)) {
            return;
        }
        
        JobStatus jobStatus = getJobStatus(jobId);
        if (jobStatus != null) {
            jobStatus.status = status;
            jobStatus.lastUpdated = DateTime.now();
            jobStatus.errorMessage = RouteLogicSecurityUtils.sanitizeInput(message);
            
            // Update cache
            jobStatusCache.put(jobId, jobStatus);
            
            // Publish status update
            publishJobStatusEvent(jobStatus);
        }
    }
    
    /**
     * @description Complete a job successfully
     * @param jobId Job identifier
     * @param processedCount Number of records processed
     * @param message Completion message
     */
    public static void completeJob(String jobId, Integer processedCount, String message) {
        if (String.isBlank(jobId)) {
            return;
        }
        
        JobStatus jobStatus = getJobStatus(jobId);
        if (jobStatus != null) {
            jobStatus.status = STATUS_COMPLETED;
            jobStatus.processedCount = processedCount != null ? processedCount : 0;
            jobStatus.completedDate = DateTime.now();
            jobStatus.lastUpdated = DateTime.now();
            jobStatus.errorMessage = RouteLogicSecurityUtils.sanitizeInput(message);
            
            // Calculate duration
            if (jobStatus.createdDate != null) {
                Long durationMs = jobStatus.completedDate.getTime() - jobStatus.createdDate.getTime();
                jobStatus.durationSeconds = Integer.valueOf(durationMs / 1000);
            }
            
            // Update cache
            jobStatusCache.put(jobId, jobStatus);
            
            // Publish completion event
            publishJobStatusEvent(jobStatus);
            
            // Update job metrics
            updateJobMetrics(jobStatus);
        }
    }
    
    /**
     * @description Fail a job
     * @param jobId Job identifier
     * @param errorMessage Error message
     */
    public static void failJob(String jobId, String errorMessage) {
        if (String.isBlank(jobId)) {
            return;
        }
        
        JobStatus jobStatus = getJobStatus(jobId);
        if (jobStatus != null) {
            jobStatus.status = STATUS_FAILED;
            jobStatus.completedDate = DateTime.now();
            jobStatus.lastUpdated = DateTime.now();
            jobStatus.errorMessage = RouteLogicSecurityUtils.sanitizeInput(errorMessage);
            
            // Calculate duration
            if (jobStatus.createdDate != null) {
                Long durationMs = jobStatus.completedDate.getTime() - jobStatus.createdDate.getTime();
                jobStatus.durationSeconds = Integer.valueOf(durationMs / 1000);
            }
            
            // Update cache
            jobStatusCache.put(jobId, jobStatus);
            
            // Publish failure event
            publishJobStatusEvent(jobStatus);
            
            // Update job metrics
            updateJobMetrics(jobStatus);
        }
    }
    
    /**
     * @description Get job status
     * @param jobId Job identifier
     * @return JobStatus object or null if not found
     */
    public static JobStatus getJobStatus(String jobId) {
        if (String.isBlank(jobId)) {
            return null;
        }
        
        // Check cache first
        if (jobStatusCache.containsKey(jobId)) {
            return jobStatusCache.get(jobId);
        }
        
        // In a real implementation, this would query from persistent storage
        return null;
    }
    
    /**
     * @description Get all active jobs
     * @return List of active job statuses
     */
    public static List<JobStatus> getActiveJobs() {
        List<JobStatus> activeJobs = new List<JobStatus>();
        
        for (JobStatus job : jobStatusCache.values()) {
            if (job.status == STATUS_QUEUED || job.status == STATUS_PROCESSING || 
                job.status == STATUS_RETRY_SCHEDULED) {
                activeJobs.add(job);
            }
        }
        
        return activeJobs;
    }
    
    /**
     * @description Get job history for a specific time period
     * @param hoursBack Number of hours to look back
     * @return List of job statuses
     */
    public static List<JobStatus> getJobHistory(Integer hoursBack) {
        List<JobStatus> jobHistory = new List<JobStatus>();
        DateTime cutoffTime = DateTime.now().addHours(-(hoursBack != null ? hoursBack : 24));
        
        for (JobStatus job : jobStatusCache.values()) {
            if (job.createdDate >= cutoffTime) {
                jobHistory.add(job);
            }
        }
        
        // Sort by creation date descending
        jobHistory.sort();
        return jobHistory;
    }
    
    /**
     * @description Get job performance metrics
     * @param hoursBack Number of hours to analyze
     * @return JobMetrics object
     */
    public static JobMetrics getJobMetrics(Integer hoursBack) {
        JobMetrics metrics = new JobMetrics();
        DateTime cutoffTime = DateTime.now().addHours(-(hoursBack != null ? hoursBack : 24));
        
        Integer totalJobs = 0;
        Integer completedJobs = 0;
        Integer failedJobs = 0;
        Integer retryJobs = 0;
        Long totalDuration = 0;
        Integer totalRecordsProcessed = 0;
        
        for (JobStatus job : jobStatusCache.values()) {
            if (job.createdDate >= cutoffTime) {
                totalJobs++;
                
                switch on job.status {
                    when 'COMPLETED' {
                        completedJobs++;
                        if (job.durationSeconds != null) {
                            totalDuration += job.durationSeconds;
                        }
                        totalRecordsProcessed += job.processedCount;
                    }
                    when 'FAILED' {
                        failedJobs++;
                        if (job.durationSeconds != null) {
                            totalDuration += job.durationSeconds;
                        }
                    }
                    when 'RETRY_SCHEDULED' {
                        retryJobs++;
                    }
                }
            }
        }
        
        metrics.totalJobs = totalJobs;
        metrics.completedJobs = completedJobs;
        metrics.failedJobs = failedJobs;
        metrics.retryJobs = retryJobs;
        metrics.successRate = totalJobs > 0 ? (Decimal.valueOf(completedJobs) / totalJobs * 100).setScale(2) : 0;
        metrics.averageDurationSeconds = (completedJobs + failedJobs) > 0 ? 
                                        Integer.valueOf(totalDuration / (completedJobs + failedJobs)) : 0;
        metrics.totalRecordsProcessed = totalRecordsProcessed;
        metrics.recordsPerSecond = totalDuration > 0 ? 
                                  (Decimal.valueOf(totalRecordsProcessed) / totalDuration).setScale(2) : 0;
        
        return metrics;
    }
    
    /**
     * @description Cancel a job
     * @param jobId Job identifier
     * @param reason Cancellation reason
     */
    public static void cancelJob(String jobId, String reason) {
        if (String.isBlank(jobId)) {
            return;
        }
        
        JobStatus jobStatus = getJobStatus(jobId);
        if (jobStatus != null && (jobStatus.status == STATUS_QUEUED || jobStatus.status == STATUS_PROCESSING)) {
            jobStatus.status = STATUS_CANCELLED;
            jobStatus.lastUpdated = DateTime.now();
            jobStatus.errorMessage = RouteLogicSecurityUtils.sanitizeInput(reason);
            
            // Update cache
            jobStatusCache.put(jobId, jobStatus);
            
            // Publish cancellation event
            publishJobStatusEvent(jobStatus);
        }
    }
    
    /**
     * @description Publish job status event for real-time monitoring
     * @param jobStatus Job status to publish
     */
    private static void publishJobStatusEvent(JobStatus jobStatus) {
        try {
            // Create platform event for real-time monitoring
            RouteLogic_Job_Status__e jobEvent = new RouteLogic_Job_Status__e();
            jobEvent.Job_Id__c = jobStatus.jobId;
            jobEvent.Job_Type__c = jobStatus.jobType;
            jobEvent.Status__c = jobStatus.status;
            jobEvent.Record_Count__c = jobStatus.recordCount;
            jobEvent.Processed_Count__c = jobStatus.processedCount;
            jobEvent.Retry_Count__c = jobStatus.retryCount;
            jobEvent.Duration_Seconds__c = jobStatus.durationSeconds;
            jobEvent.Error_Message__c = jobStatus.errorMessage;
            
            // Publish event
            EventBus.publish(jobEvent);
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to publish job status event: ' + e.getMessage());
        }
    }
    
    /**
     * @description Update job metrics (placeholder for persistent metrics)
     * @param jobStatus Completed job status
     */
    private static void updateJobMetrics(JobStatus jobStatus) {
        // In a real implementation, this would update aggregated metrics
        // stored in custom objects or custom metadata
        System.debug(LoggingLevel.INFO, 'Job metrics updated for: ' + jobStatus.jobId);
    }
    
    /**
     * @description Clean up old job statuses from cache
     * @param hoursToKeep Number of hours of job history to keep
     */
    public static void cleanupOldJobs(Integer hoursToKeep) {
        DateTime cutoffTime = DateTime.now().addHours(-(hoursToKeep != null ? hoursToKeep : 168)); // Default 7 days
        
        Set<String> jobsToRemove = new Set<String>();
        for (String jobId : jobStatusCache.keySet()) {
            JobStatus job = jobStatusCache.get(jobId);
            if (job.createdDate < cutoffTime && 
                (job.status == STATUS_COMPLETED || job.status == STATUS_FAILED || job.status == STATUS_CANCELLED)) {
                jobsToRemove.add(jobId);
            }
        }
        
        for (String jobId : jobsToRemove) {
            jobStatusCache.remove(jobId);
        }
        
        System.debug(LoggingLevel.INFO, 'Cleaned up ' + jobsToRemove.size() + ' old job statuses');
    }
    
    /**
     * @description Get job status cache size for monitoring
     * @return Number of jobs in cache
     */
    public static Integer getCacheSize() {
        return jobStatusCache.size();
    }
    
    /**
     * @description Clear job status cache (for testing)
     */
    @TestVisible
    private static void clearCache() {
        jobStatusCache.clear();
    }
    
    // Inner classes
    
    /**
     * @description Job status container
     */
    public class JobStatus implements Comparable {
        public String jobId;
        public String jobType;
        public String status;
        public Integer recordCount;
        public Integer processedCount;
        public Integer retryCount;
        public DateTime createdDate;
        public DateTime lastUpdated;
        public DateTime completedDate;
        public Integer durationSeconds;
        public String errorMessage;
        
        public Integer compareTo(Object compareTo) {
            JobStatus compareToJob = (JobStatus) compareTo;
            if (createdDate == compareToJob.createdDate) return 0;
            if (createdDate > compareToJob.createdDate) return -1;
            return 1;
        }
    }
    
    /**
     * @description Job performance metrics container
     */
    public class JobMetrics {
        public Integer totalJobs;
        public Integer completedJobs;
        public Integer failedJobs;
        public Integer retryJobs;
        public Decimal successRate;
        public Integer averageDurationSeconds;
        public Integer totalRecordsProcessed;
        public Decimal recordsPerSecond;
    }
}

