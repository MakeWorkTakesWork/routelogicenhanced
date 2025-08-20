/**
 * @description DEPRECATED - Scheduled job for automatic encryption key rotation every 90 days
 * @author RouteLogic Team
 * @date 2025-01-17
 * @deprecated This class is deprecated as of RouteLogic v3.3.0. Use Salesforce Shield Platform Encryption instead.
 * 
 * MIGRATION NOTICE:
 * RouteLogic now leverages native Salesforce Shield Platform Encryption which handles
 * key rotation automatically without requiring custom scheduled jobs.
 * 
 * To migrate:
 * 1. Enable Salesforce Shield Platform Encryption
 * 2. Remove this scheduled job from your org
 * 3. Configure automatic key rotation through Shield settings
 */
@Deprecated
global with sharing class EncryptionKeyRotationSchedule implements Schedulable {
    
    /**
     * @description Execute scheduled key rotation
     * @param ctx Schedulable context
     */
    global void execute(SchedulableContext ctx) {
        try {
            // Check if rotation is due
            if (SecurityKeyManager.isRotationDue()) {
                // Perform key rotation
                SecurityKeyManager.rotateEncryptionKeys();
                
                // Log successful execution
            } else {
                // Log skip
            }
            
            // Schedule next check
            scheduleNextRotation();
            
        } catch (Exception e) {
            // Log error but don't throw to prevent job failure
            ErrorLogService.logError('EncryptionKeyRotationSchedule.execute', e, ctx.getTriggerId());
            
            // Still schedule next attempt
            scheduleNextRotation();
        }
    }
    
    /**
     * @description Schedule the next rotation check
     */
    private void scheduleNextRotation() {
        // Check read access to CronTrigger
        if (!RouteLogicSecurityUtils.hasReadAccess('CronTrigger')) {
            return;
        }
        
        // Check if job already scheduled
        List<CronTrigger> existingJobs = [
            SELECT Id, NextFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name = 'Encryption Key Rotation Check'
            AND State != 'DELETED'
            LIMIT 1
        ];
        
        if (!existingJobs.isEmpty()) {
            // Job already scheduled
            return;
        }
        
        // Schedule for tomorrow at 2 AM
        DateTime tomorrow = DateTime.now().addDays(1);
        String cronExp = '0 0 2 ' + tomorrow.day() + ' ' + tomorrow.month() + ' ? ' + tomorrow.year();
        
        System.schedule('Encryption Key Rotation Check', cronExp, new EncryptionKeyRotationSchedule());
    }
    
    /**
     * @description Schedule the job for the first time
     * Call this method once during initial setup
     */
    public static void scheduleJob() {
        // Check read access to CronTrigger
        if (!RouteLogicSecurityUtils.hasReadAccess('CronTrigger')) {
            return;
        }
        
        // Remove existing job if any
        List<CronTrigger> existingJobs = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Encryption Key Rotation%'
            AND State != 'DELETED'
        ];
        
        for (CronTrigger job : existingJobs) {
            System.abortJob(job.Id);
        }
        
        // Schedule daily check at 2 AM
        String cronExp = '0 0 2 * * ?'; // Every day at 2 AM
        System.schedule('Encryption Key Rotation Daily Check', cronExp, new EncryptionKeyRotationSchedule());
        
    }
}