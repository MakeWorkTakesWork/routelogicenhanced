/**
 * @description Uninstall script for RouteLogic Enhanced package
 * @author RouteLogic Team
 * @date 2025-01-19
 */
@namespaceAccessible
global with sharing class UninstallScript implements UninstallHandler {
    
    /**
     * @description Called before package uninstallation
     * @param context Uninstall context
     */
    global void onUninstall(UninstallContext context) {
        try {
            // Get uninstall details
            Id organizationId = context.organizationId();
            Id uninstallerId = context.uninstallerId();
            
            // Log uninstallation
            logUninstallation(organizationId, uninstallerId);
            
            // Perform cleanup tasks
            performCleanup();
            
            // Send notification
            sendUninstallNotification(context);
            
        } catch (Exception e) {
            // Log error but don't fail uninstallation
            System.debug('Uninstall script error: ' + e.getMessage());
            // Can't use ErrorLogService as it will be deleted
        }
    }
    
    /**
     * @description Log uninstallation details
     */
    private void logUninstallation(Id organizationId, Id uninstallerId) {
        try {
            // Create final audit record before package removal
            AuditService.logEvent(
                'PACKAGE_UNINSTALL',
                'Package uninstalled - Org: ' + organizationId + ', User: ' + uninstallerId,
                'SUCCESS',
                'SYSTEM'
            );
            
            // Publish platform event for external logging if needed
            AI_Critical_Error__e event = new AI_Critical_Error__e(
                Component__c = 'UninstallScript',
                Error_Type__c = 'PACKAGE_UNINSTALL',
                Error_Message__c = 'RouteLogic Enhanced package uninstalled',
                Stack_Trace__c = 'Org: ' + organizationId,
                Severity__c = 'INFO'
            );
            EventBus.publish(event);
            
        } catch (Exception e) {
            System.debug('Failed to log uninstallation: ' + e.getMessage());
        }
    }
    
    /**
     * @description Perform cleanup tasks
     */
    private void performCleanup() {
        try {
            // Cancel scheduled jobs
            cancelScheduledJobs();
            
            // Clear platform cache
            clearPlatformCache();
            
            // Archive critical data if needed
            archiveCriticalData();
            
        } catch (Exception e) {
            System.debug('Cleanup error: ' + e.getMessage());
        }
    }
    
    /**
     * @description Cancel scheduled jobs
     */
    private void cancelScheduledJobs() {
        try {
            // Find and abort scheduled jobs
            List<CronTrigger> jobs = [
                SELECT Id 
                FROM CronTrigger 
                WHERE CronJobDetail.Name LIKE 'RouteLogic%'
                AND State != 'DELETED'
            ];
            
            for (CronTrigger job : jobs) {
                System.abortJob(job.Id);
            }
            
        } catch (Exception e) {
            System.debug('Failed to cancel scheduled jobs: ' + e.getMessage());
        }
    }
    
    /**
     * @description Clear platform cache
     */
    private void clearPlatformCache() {
        try {
            // Clear organization cache partition
            Cache.Org.remove('AIRateLimit');
            
        } catch (Exception e) {
            System.debug('Failed to clear cache: ' + e.getMessage());
        }
    }
    
    /**
     * @description Archive critical data before uninstall
     */
    private void archiveCriticalData() {
        try {
            // Count records that will be deleted
            Integer auditCount = [SELECT COUNT() FROM AI_Audit_Event__c LIMIT 50000];
            Integer metricsCount = [SELECT COUNT() FROM AI_Bulk_Processing_Metrics__c LIMIT 50000];
            
            // Log summary
            String summary = String.format(
                'Data to be deleted - Audit Events: {0}, Processing Metrics: {1}',
                new String[] { String.valueOf(auditCount), String.valueOf(metricsCount) }
            );
            
            System.debug('Uninstall data summary: ' + summary);
            
            // In production, this could export data to an external system
            
        } catch (Exception e) {
            System.debug('Failed to archive data: ' + e.getMessage());
        }
    }
    
    /**
     * @description Send uninstall notification
     */
    private void sendUninstallNotification(UninstallContext context) {
        try {
            // Get uninstaller user
            User uninstaller = [
                SELECT Id, Email, Name 
                FROM User 
                WHERE Id = :context.uninstallerId() 
                LIMIT 1
            ];
            
            // Log uninstaller information
            System.debug('Package uninstalled by: ' + uninstaller.Name + ' (' + uninstaller.Email + ')');
            
            // In production, this could send an email notification
            
        } catch (Exception e) {
            System.debug('Failed to send notification: ' + e.getMessage());
        }
    }
}