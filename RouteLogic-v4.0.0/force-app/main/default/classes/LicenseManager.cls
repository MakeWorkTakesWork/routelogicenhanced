/**
 * @description Utility class for managing package license validation
 * @author RouteLogic Team
 * @date 2025-01-19
 */
@namespaceAccessible
public with sharing class LicenseManager {
    
    // Cache license status for performance
    private static Boolean licenseValidated = false;
    private static Boolean isLicensed = false;
    
    // Package namespace
    private static final String PACKAGE_NAMESPACE = 'routelogic';
    
    /**
     * @description Check if the current user has a valid package license
     * @return True if licensed, false otherwise
     */
    public static Boolean isPackageLicensed() {
        if (licenseValidated) {
            return isLicensed;
        }
        
        try {
            // Check if we're in a managed package context
            if (!isInManagedPackage()) {
                // Development/unmanaged context - always allow
                licenseValidated = true;
                isLicensed = true;
                return true;
            }
            
            // Check package license assignment
            isLicensed = UserInfo.isCurrentUserLicensed(PACKAGE_NAMESPACE);
            licenseValidated = true;
            
            // Log license check
            if (!isLicensed) {
                logLicenseViolation();
            }
            
            return isLicensed;
            
        } catch (Exception e) {
            // In case of any errors, fail open in development but closed in production
            ErrorLogService.logError('LicenseManager.isPackageLicensed', e, 'License check failed');
            
            // If we can't determine license status, default to safe behavior
            licenseValidated = true;
            isLicensed = !isInManagedPackage(); // Allow in dev, deny in managed
            return isLicensed;
        }
    }
    
    /**
     * @description Enforce license check - throws exception if not licensed
     * @throws LicenseException if user is not licensed
     */
    public static void enforceLicense() {
        if (!isPackageLicensed()) {
            throw new LicenseException(
                'You do not have a valid license for RouteLogic Enhanced. ' +
                'Please contact your administrator to assign a license.'
            );
        }
    }
    
    /**
     * @description Check if specific feature is licensed
     * @param featureName Name of the feature to check
     * @return True if feature is licensed
     */
    public static Boolean isFeatureLicensed(String featureName) {
        // First check base package license
        if (!isPackageLicensed()) {
            return false;
        }
        
        // Check feature-specific licensing if applicable
        // This can be extended to check custom permissions or feature parameters
        try {
            // For now, all features are included with base license
            return true;
        } catch (Exception e) {
            ErrorLogService.logError('LicenseManager.isFeatureLicensed', e, 'Feature check failed: ' + featureName);
            return false;
        }
    }
    
    /**
     * @description Get license expiration date
     * @return License expiration date or null if perpetual
     */
    public static Date getLicenseExpirationDate() {
        try {
            // This would typically query PackageLicense object
            // For now, return null indicating perpetual license
            return null;
        } catch (Exception e) {
            ErrorLogService.logError('LicenseManager.getLicenseExpirationDate', e, 'Failed to get expiration date');
            return null;
        }
    }
    
    /**
     * @description Check if code is running in managed package context
     * @return True if in managed package
     */
    private static Boolean isInManagedPackage() {
        try {
            // Check if our namespace is registered
            String currentNamespace = LicenseManager.class.getName().substringBefore('.');
            return currentNamespace == PACKAGE_NAMESPACE;
        } catch (Exception e) {
            // If we can't determine, assume we're in development
            return false;
        }
    }
    
    /**
     * @description Log license violation attempt
     */
    private static void logLicenseViolation() {
        try {
            // Create audit record for license violation
            AuditService.logEvent(
                'LICENSE_VIOLATION',
                'Unlicensed access attempt by user: ' + UserInfo.getUserId(),
                'BLOCKED',
                'SECURITY'
            );
            
            // Publish platform event for monitoring
            AI_Critical_Error__e errorEvent = new AI_Critical_Error__e(
                Component__c = 'LicenseManager',
                Error_Type__c = 'LICENSE_VIOLATION',
                Error_Message__c = 'Unlicensed access attempt',
                Stack_Trace__c = 'User: ' + UserInfo.getUserName(),
                Severity__c = 'HIGH'
            );
            EventBus.publish(errorEvent);
            
        } catch (Exception e) {
            System.debug('Failed to log license violation: ' + e.getMessage());
        }
    }
    
    /**
     * @description Custom exception for license violations
     */
    public class LicenseException extends Exception {}
}