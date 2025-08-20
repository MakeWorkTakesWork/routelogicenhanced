/**
 * @description Post-install script for RouteLogic Enhanced package
 * @author RouteLogic Team
 * @date 2025-01-19
 */
@namespaceAccessible
global with sharing class PostInstallScript implements InstallHandler {
    
    /**
     * @description Called after package installation
     * @param context Installation context
     */
    global void onInstall(InstallContext context) {
        try {
            // Get install details
            Version previousVersion = context.previousVersion();
            Version currentVersion = context.currentVersion();
            Id organizationId = context.organizationId();
            Id installerId = context.installerId();
            
            // Log installation
            logInstallation(previousVersion, currentVersion, organizationId, installerId);
            
            // Perform post-install tasks based on installation type
            if (previousVersion == null) {
                // Fresh install
                performFreshInstall();
            } else {
                // Upgrade
                performUpgrade(previousVersion, currentVersion);
            }
            
            // Send notification
            sendInstallNotification(context);
            
        } catch (Exception e) {
            // Log error but don't fail installation
            
            ErrorLogService.logError('PostInstallScript.onInstall', e, 'Post-install error');
        }
    }
    
    /**
     * @description Log installation details
     */
    private void logInstallation(Version previousVersion, Version currentVersion, 
                                 Id organizationId, Id installerId) {
        String description = String.format(
            'Package installed - Previous: {0}, Current: {1}, Org: {2}, User: {3}',
            new String[] {
                previousVersion != null ? previousVersion.toString() : 'New Install',
                currentVersion.toString(),
                organizationId,
                installerId
            }
        );
        
        AuditService.logEvent(
            'PACKAGE_INSTALL',
            description,
            'SUCCESS',
            'SYSTEM'
        );
    }
    
    /**
     * @description Perform fresh install tasks
     */
    private void performFreshInstall() {
        // Schedule encryption key rotation
        scheduleKeyRotation();
        
        // Initialize platform cache partition
        initializePlatformCache();
        
        // Create default settings if needed
        createDefaultSettings();
    }
    
    /**
     * @description Perform upgrade tasks
     */
    private void performUpgrade(Version previousVersion, Version currentVersion) {
        // Version-specific upgrade logic
        if (previousVersion.compareTo(new Version(3, 0, 0)) < 0) {
            // Upgrade from v2.x to v3.x
            migrateV2ToV3();
        }
        
        // Ensure key rotation is scheduled
        scheduleKeyRotation();
    }
    
    /**
     * @description Schedule encryption key rotation
     */
    private void scheduleKeyRotation() {
        try {
            // Check if already scheduled
            List<CronTrigger> existingJobs = new List<CronTrigger>();
            if (RouteLogicSecurityUtils.hasReadAccess('CronTrigger')) {
                existingJobs = [
                    SELECT Id FROM CronTrigger 
                    WHERE CronJobDetail.Name = 'RouteLogic Key Rotation'
                    AND State != 'DELETED'
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
            }
            
            if (existingJobs.isEmpty()) {
                // Schedule monthly key rotation
                String cronExp = '0 0 2 1 * ?'; // 2 AM on the 1st of every month
                System.schedule('RouteLogic Key Rotation', cronExp, new EncryptionKeyRotationSchedule());
            }
        } catch (Exception e) {
            
        }
    }
    
    /**
     * @description Initialize platform cache
     */
    private void initializePlatformCache() {
        try {
            // Platform cache initialization is automatic
            // This is a placeholder for any custom initialization
        } catch (Exception e) {
            
        }
    }
    
    /**
     * @description Create default settings
     */
    private void createDefaultSettings() {
        // Default settings are managed through Custom Metadata
        // This is a placeholder for any runtime configuration
    }
    
    /**
     * @description Migrate from v2 to v3
     */
    private void migrateV2ToV3() {
        // Migration logic for major version upgrade
        // This would typically involve data transformation
    }
    
    /**
     * @description Send installation notification
     */
    private void sendInstallNotification(InstallContext context) {
        try {
            // Get installer user
            User installer = null;
            if (RouteLogicSecurityUtils.hasReadAccess('User')) {
                List<User> installers = [
                    SELECT Id, Email, Name FROM User 
                    WHERE Id = :context.installerId() 
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
                if (!installers.isEmpty()) {
                    installer = installers[0];
                }
            }
            
            // Send email notification (if configured)
            // This is a placeholder - actual implementation would check settings
            
        } catch (Exception e) {
            
        }
    }
}