/**
 * @description Trigger for Routing_Ledger__c to enforce immutability and populate security hash
 * @author RouteLogic Team
 * @date 2025-01-21
 */
trigger RoutingLedgerTrigger on Routing_Ledger__c (before insert, before update, before delete) {
    
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            RoutingLedgerTriggerHandler.handleBeforeInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            RoutingLedgerTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete) {
            RoutingLedgerTriggerHandler.handleBeforeDelete(Trigger.old);
        }
    }
}

