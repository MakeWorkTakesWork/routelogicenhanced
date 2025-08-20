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
            // Errors during uninstall are silently caught to prevent uninstall failure
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
            // Silent catch - logging infrastructure may be unavailable during uninstall
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
            // Silent catch - cleanup errors should not prevent uninstall
        }
    }
    
    /**
     * @description Cancel scheduled jobs
     */
    private void cancelScheduledJobs() {
        try {
            // Validate CRUD access before querying
            if (!RouteLogicSecurityUtils.hasReadAccess('CronTrigger')) {
                // Insufficient permissions - skip job cancellation
                return;
            }
            
            // Find and abort scheduled jobs
            List<CronTrigger> jobs = [
                SELECT Id 
                FROM CronTrigger 
                WHERE CronJobDetail.Name LIKE 'RouteLogic%'
                AND State != 'DELETED'
                WITH SECURITY_ENFORCED
            ];
            
            for (CronTrigger job : jobs) {
                System.abortJob(job.Id);
            }
            
        } catch (Exception e) {
            // Silent catch - job cancellation errors should not prevent uninstall
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
            // Silent catch - cache clearing errors should not prevent uninstall
        }
    }
    
    /**
     * @description Archive critical data before uninstall
     */
    private void archiveCriticalData() {
        try {
            // Validate CRUD access before querying
            Integer auditCount = 0;
            Integer metricsCount = 0;
            
            if (RouteLogicSecurityUtils.hasReadAccess('AI_Audit_Event__c')) {
                auditCount = [SELECT COUNT() FROM AI_Audit_Event__c WITH SECURITY_ENFORCED LIMIT 50000];
            }
            
            if (RouteLogicSecurityUtils.hasReadAccess('AI_Bulk_Processing_Metrics__c')) {
                metricsCount = [SELECT COUNT() FROM AI_Bulk_Processing_Metrics__c WITH SECURITY_ENFORCED LIMIT 50000];
            }
            
            // Log summary
            String summary = String.format(
                'Data to be deleted - Audit Events: {0}, Processing Metrics: {1}',
                new String[] { String.valueOf(auditCount), String.valueOf(metricsCount) }
            );
            
            // Data summary: Audit Events and Processing Metrics will be deleted
            
            // In production, this could export data to an external system
            
        } catch (Exception e) {
            // Silent catch - archiving errors should not prevent uninstall
        }
    }
    
    /**
     * @description Send uninstall notification
     */
    private void sendUninstallNotification(UninstallContext context) {
        try {
            // Validate CRUD access before querying
            if (!RouteLogicSecurityUtils.hasReadAccess('User')) {
                // Insufficient permissions - skip notification
                return;
            }
            
            // Validate field-level security
            Set<String> userFields = new Set<String>{'Id', 'Email', 'Name'};
            try {
                RouteLogicSecurityUtils.validateFieldAccess('User', userFields, RouteLogicSecurityUtils.AccessType.READABLE);
            } catch (Exception e) {
                // Insufficient field permissions - skip notification
                return;
            }
            
            // Get uninstaller user
            User uninstaller = [
                SELECT Id, Email, Name 
                FROM User 
                WHERE Id = :context.uninstallerId() 
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            
            // Log uninstaller information
            // Package uninstalled by user - notification would be sent here if configured
            
            // In production, this could send an email notification
            
        } catch (Exception e) {
            // Silent catch - notification errors should not prevent uninstall
        }
    }
}