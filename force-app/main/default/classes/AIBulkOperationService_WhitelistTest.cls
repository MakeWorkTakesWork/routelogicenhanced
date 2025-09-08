@IsTest
private class AIBulkOperationService_WhitelistTest {
    @IsTest static void validFieldName_Passes() {
        System.assertEquals(true, AIBulkOperationService.isValidFieldName('Account', 'Name'));
    }
    @IsTest static void invalidFieldName_Fails() {
        System.assertEquals(false, AIBulkOperationService.isValidFieldName('Account', 'DoesNotExist__c'));
        System.assertEquals(false, AIBulkOperationService.isValidFieldName('Account', 'Owner.Name'));
    }
    @IsTest static void validWhereParams_Passes() {
        Map<String,Object> wp = new Map<String,Object>{ 'Name' => 'Acme' };
        System.assertEquals(true, AIBulkOperationService.areValidWhereParams('Account', wp));
    }
    @IsTest static void invalidWhereParams_Fails() {
        Map<String,Object> wp = new Map<String,Object>{ 'Owner.Name' => 'Smith' };
        System.assertEquals(false, AIBulkOperationService.areValidWhereParams('Account', wp));
    }
}
