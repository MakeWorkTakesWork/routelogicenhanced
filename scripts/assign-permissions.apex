// RouteLogic Security Permission Assignment Script
// Run this after deployment to assign permissions to current user

try {
    // Get current user
    User currentUser = [SELECT Id, Username FROM User WHERE Id = :UserInfo.getUserId()];
    System.debug('Assigning permissions to: ' + currentUser.Username);
    
    // Get the permission set
    List<PermissionSet> permSets = [
        SELECT Id, Name 
        FROM PermissionSet 
        WHERE Name = 'RouteLogic_Security_Admin'
        LIMIT 1
    ];
    
    if (permSets.isEmpty()) {
        System.debug('Error: RouteLogic_Security_Admin permission set not found');
        return;
    }
    
    // Check if already assigned
    List<PermissionSetAssignment> existing = [
        SELECT Id 
        FROM PermissionSetAssignment 
        WHERE AssigneeId = :currentUser.Id 
        AND PermissionSetId = :permSets[0].Id
    ];
    
    if (existing.isEmpty()) {
        // Assign permission set
        PermissionSetAssignment psa = new PermissionSetAssignment(
            AssigneeId = currentUser.Id,
            PermissionSetId = permSets[0].Id
        );
        insert psa;
        System.debug('✓ Permission set assigned successfully');
    } else {
        System.debug('✓ Permission set already assigned');
    }
    
    // Verify custom permission
    Boolean hasCustomPerm = FeatureManagement.checkPermission('RouteLogic_Security_Admin');
    System.debug('Custom permission check: ' + (hasCustomPerm ? 'GRANTED' : 'NOT GRANTED'));
    
    if (!hasCustomPerm) {
        System.debug('Note: Custom permission may take a moment to activate. Log out and back in if needed.');
    }
    
} catch (Exception e) {
    System.debug('Error assigning permissions: ' + e.getMessage());
}