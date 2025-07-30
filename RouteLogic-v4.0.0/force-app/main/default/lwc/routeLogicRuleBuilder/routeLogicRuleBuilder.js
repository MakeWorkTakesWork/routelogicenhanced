import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getSupportedObjectTypes from '@salesforce/apex/RouteLogicObjectManager.getSupportedObjectTypes';
import getObjectConfiguration from '@salesforce/apex/RouteLogicObjectManager.getObjectConfiguration';
import validateConfiguration from '@salesforce/apex/RouteLogicConfigurationManager.validateConfiguration';
import testConfiguration from '@salesforce/apex/RouteLogicConfigurationManager.testConfiguration';

export default class RouteLogicRuleBuilder extends LightningElement {
    @track rules = [];
    @track selectedObjectType = '';
    @track supportedObjects = [];
    @track objectFields = [];
    @track availableOperators = [];
    @track availableProviders = [];
    @track isLoading = false;
    @track error;
    @track errorMessage;
    @track showRuleModal = false;
    @track editingRule = null;
    @track ruleValidationResults = {};
    
    // Rule builder state
    @track currentRule = {
        id: null,
        name: '',
        description: '',
        objectType: '',
        isActive: true,
        priority: 1,
        conditions: [],
        actions: []
    };
    
    // Wire results
    wiredSupportedObjectsResult;
    
    get objectTypeOptions() {
        return this.supportedObjects.map(obj => ({
            label: obj,
            value: obj
        }));
    }
    
    get operatorOptions() {
        return [
            { label: 'Equals', value: 'equals' },
            { label: 'Not Equals', value: 'not_equals' },
            { label: 'Contains', value: 'contains' },
            { label: 'Does Not Contain', value: 'not_contains' },
            { label: 'Starts With', value: 'starts_with' },
            { label: 'Ends With', value: 'ends_with' },
            { label: 'Greater Than', value: 'greater_than' },
            { label: 'Less Than', value: 'less_than' },
            { label: 'Greater or Equal', value: 'greater_equal' },
            { label: 'Less or Equal', value: 'less_equal' },
            { label: 'Is Empty', value: 'is_empty' },
            { label: 'Is Not Empty', value: 'is_not_empty' },
            { label: 'In List', value: 'in_list' },
            { label: 'Not In List', value: 'not_in_list' }
        ];
    }
    
    get actionTypeOptions() {
        return [
            { label: 'Route to Provider', value: 'route_to_provider' },
            { label: 'Assign to User', value: 'assign_to_user' },
            { label: 'Assign to Queue', value: 'assign_to_queue' },
            { label: 'Set Field Value', value: 'set_field_value' },
            { label: 'Send Email Alert', value: 'send_email' },
            { label: 'Create Task', value: 'create_task' },
            { label: 'Escalate', value: 'escalate' },
            { label: 'Stop Processing', value: 'stop_processing' }
        ];
    }
    
    get providerOptions() {
        return [
            { label: 'Ada', value: 'Ada' },
            { label: 'Intercom', value: 'Intercom' },
            { label: 'Custom Provider', value: 'Custom' }
        ];
    }
    
    get priorityOptions() {
        return [
            { label: 'Highest (1)', value: 1 },
            { label: 'High (2)', value: 2 },
            { label: 'Medium (3)', value: 3 },
            { label: 'Low (4)', value: 4 },
            { label: 'Lowest (5)', value: 5 }
        ];
    }
    
    get hasRules() {
        return this.rules && this.rules.length > 0;
    }
    
    get ruleColumns() {
        return [
            { 
                label: 'Rule Name', 
                fieldName: 'name', 
                type: 'text',
                cellAttributes: { class: 'slds-text-font_monospace' }
            },
            { label: 'Object Type', fieldName: 'objectType', type: 'text' },
            { 
                label: 'Status', 
                fieldName: 'isActive', 
                type: 'boolean',
                cellAttributes: { 
                    iconName: { fieldName: 'statusIcon' },
                    iconVariant: { fieldName: 'statusVariant' }
                }
            },
            { 
                label: 'Priority', 
                fieldName: 'priority', 
                type: 'number',
                cellAttributes: { alignment: 'center' }
            },
            { 
                label: 'Conditions', 
                fieldName: 'conditionCount', 
                type: 'number',
                cellAttributes: { alignment: 'center' }
            },
            { 
                label: 'Actions', 
                fieldName: 'actionCount', 
                type: 'number',
                cellAttributes: { alignment: 'center' }
            },
            {
                type: 'action',
                typeAttributes: {
                    rowActions: [
                        { label: 'Edit', name: 'edit' },
                        { label: 'Test', name: 'test' },
                        { label: 'Clone', name: 'clone' },
                        { label: 'Delete', name: 'delete' }
                    ]
                }
            }
        ];
    }
    
    @wire(getSupportedObjectTypes)
    wiredSupportedObjects(result) {
        this.wiredSupportedObjectsResult = result;
        if (result.data) {
            this.supportedObjects = result.data;
            this.error = undefined;
            this.errorMessage = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.errorMessage = this.sanitizeErrorMessage(result.error);
            this.supportedObjects = [];
        }
        this.isLoading = false;
    }
    
    connectedCallback() {
        this.loadRules();
        this.initializeDefaultRule();
    }
    
    loadRules() {
        // In a real implementation, this would load rules from the server
        // For now, we'll initialize with sample rules
        this.rules = [
            {
                id: '1',
                name: 'High Priority Cases to Ada',
                description: 'Route high priority cases to Ada AI',
                objectType: 'Case',
                isActive: true,
                priority: 1,
                conditions: [
                    { field: 'Priority', operator: 'equals', value: 'High' }
                ],
                actions: [
                    { type: 'route_to_provider', value: 'Ada' }
                ],
                conditionCount: 1,
                actionCount: 1,
                statusIcon: 'utility:success',
                statusVariant: 'success'
            },
            {
                id: '2',
                name: 'Lead Qualification to Intercom',
                description: 'Route qualified leads to Intercom',
                objectType: 'Lead',
                isActive: true,
                priority: 2,
                conditions: [
                    { field: 'Status', operator: 'equals', value: 'Qualified' },
                    { field: 'Rating', operator: 'equals', value: 'Hot' }
                ],
                actions: [
                    { type: 'route_to_provider', value: 'Intercom' },
                    { type: 'send_email', value: 'sales_team@company.com' }
                ],
                conditionCount: 2,
                actionCount: 2,
                statusIcon: 'utility:success',
                statusVariant: 'success'
            }
        ];
    }
    
    initializeDefaultRule() {
        this.currentRule = {
            id: null,
            name: '',
            description: '',
            objectType: '',
            isActive: true,
            priority: 1,
            conditions: [],
            actions: []
        };
    }
    
    handleObjectTypeChange(event) {
        this.selectedObjectType = event.detail.value;
        this.currentRule.objectType = this.selectedObjectType;
        this.loadObjectFields();
    }
    
    async loadObjectFields() {
        if (!this.selectedObjectType) {
            this.objectFields = [];
            return;
        }
        
        try {
            this.isLoading = true;
            
            // Get object configuration
            const config = await getObjectConfiguration({ objectApiName: this.selectedObjectType });
            
            if (config) {
                // In a real implementation, this would get actual field metadata
                this.objectFields = this.getStandardFields(this.selectedObjectType);
            }
            
        } catch (error) {
            this.showToast('Error', 'Failed to load object fields: ' + error.body?.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    getStandardFields(objectType) {
        const commonFields = [
            { label: 'Owner', value: 'OwnerId', type: 'reference' },
            { label: 'Created Date', value: 'CreatedDate', type: 'datetime' },
            { label: 'Last Modified Date', value: 'LastModifiedDate', type: 'datetime' }
        ];
        
        if (objectType === 'Case') {
            return [
                { label: 'Subject', value: 'Subject', type: 'text' },
                { label: 'Description', value: 'Description', type: 'textarea' },
                { label: 'Priority', value: 'Priority', type: 'picklist' },
                { label: 'Status', value: 'Status', type: 'picklist' },
                { label: 'Origin', value: 'Origin', type: 'picklist' },
                { label: 'Contact', value: 'ContactId', type: 'reference' },
                { label: 'Account', value: 'AccountId', type: 'reference' },
                ...commonFields
            ];
        } else if (objectType === 'Lead') {
            return [
                { label: 'First Name', value: 'FirstName', type: 'text' },
                { label: 'Last Name', value: 'LastName', type: 'text' },
                { label: 'Company', value: 'Company', type: 'text' },
                { label: 'Email', value: 'Email', type: 'email' },
                { label: 'Phone', value: 'Phone', type: 'phone' },
                { label: 'Status', value: 'Status', type: 'picklist' },
                { label: 'Rating', value: 'Rating', type: 'picklist' },
                { label: 'Lead Source', value: 'LeadSource', type: 'picklist' },
                ...commonFields
            ];
        }
        
        return commonFields;
    }
    
    handleNewRule() {
        this.initializeDefaultRule();
        this.editingRule = null;
        this.showRuleModal = true;
    }
    
    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        
        switch (actionName) {
            case 'edit':
                this.handleEditRule(row);
                break;
            case 'test':
                this.handleTestRule(row);
                break;
            case 'clone':
                this.handleCloneRule(row);
                break;
            case 'delete':
                this.handleDeleteRule(row);
                break;
        }
    }
    
    handleEditRule(rule) {
        this.currentRule = { ...rule };
        this.editingRule = rule;
        this.selectedObjectType = rule.objectType;
        this.loadObjectFields();
        this.showRuleModal = true;
    }
    
    handleTestRule(rule) {
        this.testRuleConfiguration(rule);
    }
    
    handleCloneRule(rule) {
        this.currentRule = { 
            ...rule, 
            id: null, 
            name: rule.name + ' (Copy)',
            isActive: false
        };
        this.editingRule = null;
        this.selectedObjectType = rule.objectType;
        this.loadObjectFields();
        this.showRuleModal = true;
    }
    
    handleDeleteRule(rule) {
        if (confirm('Are you sure you want to delete this rule?')) {
            this.rules = this.rules.filter(r => r.id !== rule.id);
            this.showToast('Success', 'Rule deleted successfully', 'success');
        }
    }
    
    handleRuleNameChange(event) {
        this.currentRule.name = event.target.value;
    }
    
    handleRuleDescriptionChange(event) {
        this.currentRule.description = event.target.value;
    }
    
    handleRuleActiveChange(event) {
        this.currentRule.isActive = event.target.checked;
    }
    
    handleRulePriorityChange(event) {
        this.currentRule.priority = parseInt(event.detail.value);
    }
    
    handleAddCondition() {
        this.currentRule.conditions.push({
            id: Date.now(),
            field: '',
            operator: 'equals',
            value: '',
            logicalOperator: this.currentRule.conditions.length > 0 ? 'AND' : null
        });
    }
    
    handleRemoveCondition(event) {
        const conditionId = parseInt(event.target.dataset.id);
        this.currentRule.conditions = this.currentRule.conditions.filter(c => c.id !== conditionId);
    }
    
    handleConditionFieldChange(event) {
        const conditionId = parseInt(event.target.dataset.id);
        const condition = this.currentRule.conditions.find(c => c.id === conditionId);
        if (condition) {
            condition.field = event.detail.value;
        }
    }
    
    handleConditionOperatorChange(event) {
        const conditionId = parseInt(event.target.dataset.id);
        const condition = this.currentRule.conditions.find(c => c.id === conditionId);
        if (condition) {
            condition.operator = event.detail.value;
        }
    }
    
    handleConditionValueChange(event) {
        const conditionId = parseInt(event.target.dataset.id);
        const condition = this.currentRule.conditions.find(c => c.id === conditionId);
        if (condition) {
            condition.value = event.target.value;
        }
    }
    
    handleConditionLogicalOperatorChange(event) {
        const conditionId = parseInt(event.target.dataset.id);
        const condition = this.currentRule.conditions.find(c => c.id === conditionId);
        if (condition) {
            condition.logicalOperator = event.detail.value;
        }
    }
    
    handleAddAction() {
        this.currentRule.actions.push({
            id: Date.now(),
            type: 'route_to_provider',
            value: '',
            parameters: {}
        });
    }
    
    handleRemoveAction(event) {
        const actionId = parseInt(event.target.dataset.id);
        this.currentRule.actions = this.currentRule.actions.filter(a => a.id !== actionId);
    }
    
    handleActionTypeChange(event) {
        const actionId = parseInt(event.target.dataset.id);
        const action = this.currentRule.actions.find(a => a.id === actionId);
        if (action) {
            action.type = event.detail.value;
            action.value = ''; // Reset value when type changes
        }
    }
    
    handleActionValueChange(event) {
        const actionId = parseInt(event.target.dataset.id);
        const action = this.currentRule.actions.find(a => a.id === actionId);
        if (action) {
            action.value = event.target.value;
        }
    }
    
    handleSaveRule() {
        if (!this.validateRule()) {
            return;
        }
        
        try {
            // Generate ID for new rules
            if (!this.currentRule.id) {
                this.currentRule.id = Date.now().toString();
            }
            
            // Calculate display properties
            this.currentRule.conditionCount = this.currentRule.conditions.length;
            this.currentRule.actionCount = this.currentRule.actions.length;
            this.currentRule.statusIcon = this.currentRule.isActive ? 'utility:success' : 'utility:pause';
            this.currentRule.statusVariant = this.currentRule.isActive ? 'success' : 'warning';
            
            // Update or add rule
            if (this.editingRule) {
                const index = this.rules.findIndex(r => r.id === this.editingRule.id);
                if (index !== -1) {
                    this.rules[index] = { ...this.currentRule };
                }
            } else {
                this.rules.push({ ...this.currentRule });
            }
            
            // Sort rules by priority
            this.rules.sort((a, b) => a.priority - b.priority);
            
            this.showToast('Success', 'Rule saved successfully', 'success');
            this.handleCancelRule();
            
        } catch (error) {
            this.showToast('Error', 'Failed to save rule: ' + error.message, 'error');
        }
    }
    
    handleCancelRule() {
        this.showRuleModal = false;
        this.initializeDefaultRule();
        this.editingRule = null;
        this.selectedObjectType = '';
        this.objectFields = [];
    }
    
    validateRule() {
        if (!this.currentRule.name) {
            this.showToast('Validation Error', 'Rule name is required', 'error');
            return false;
        }
        
        if (!this.currentRule.objectType) {
            this.showToast('Validation Error', 'Object type is required', 'error');
            return false;
        }
        
        if (this.currentRule.conditions.length === 0) {
            this.showToast('Validation Error', 'At least one condition is required', 'error');
            return false;
        }
        
        if (this.currentRule.actions.length === 0) {
            this.showToast('Validation Error', 'At least one action is required', 'error');
            return false;
        }
        
        // Validate conditions
        for (let condition of this.currentRule.conditions) {
            if (!condition.field || !condition.operator) {
                this.showToast('Validation Error', 'All condition fields and operators must be specified', 'error');
                return false;
            }
            
            if (condition.operator !== 'is_empty' && condition.operator !== 'is_not_empty' && !condition.value) {
                this.showToast('Validation Error', 'Condition values are required for most operators', 'error');
                return false;
            }
        }
        
        // Validate actions
        for (let action of this.currentRule.actions) {
            if (!action.type) {
                this.showToast('Validation Error', 'All action types must be specified', 'error');
                return false;
            }
            
            if (action.type !== 'stop_processing' && !action.value) {
                this.showToast('Validation Error', 'Action values are required for most action types', 'error');
                return false;
            }
        }
        
        return true;
    }
    
    async testRuleConfiguration(rule) {
        try {
            this.isLoading = true;
            
            // Convert rule to configuration format
            const configKey = 'Rule_' + rule.id;
            const configValue = JSON.stringify(rule);
            
            // Test the configuration
            const testResult = await testConfiguration({ 
                configurationKey: configKey 
            });
            
            if (testResult.success) {
                this.showToast('Test Success', 
                    `Rule test completed successfully in ${testResult.responseTime}ms`, 'success');
            } else {
                this.showToast('Test Failed', testResult.message, 'error');
            }
            
        } catch (error) {
            this.showToast('Error', 'Failed to test rule: ' + error.body?.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    handleExportRules() {
        try {
            const exportData = {
                version: '4.0.0',
                exportDate: new Date().toISOString(),
                rules: this.rules
            };
            
            const dataStr = JSON.stringify(exportData, null, 2);
            const dataBlob = new Blob([dataStr], { type: 'application/json' });
            
            const link = document.createElement('a');
            link.href = URL.createObjectURL(dataBlob);
            link.download = 'routelogic-rules-export.json';
            link.click();
            
            this.showToast('Success', 'Rules exported successfully', 'success');
            
        } catch (error) {
            this.showToast('Error', 'Failed to export rules: ' + error.message, 'error');
        }
    }
    
    handleImportRules(event) {
        const file = event.target.files[0];
        if (!file) return;
        
        const reader = new FileReader();
        reader.onload = (e) => {
            try {
                const importData = JSON.parse(e.target.result);
                
                if (importData.rules && Array.isArray(importData.rules)) {
                    // Validate and merge rules
                    const importedRules = importData.rules.map(rule => ({
                        ...rule,
                        id: Date.now() + Math.random(), // Generate new IDs
                        name: rule.name + ' (Imported)'
                    }));
                    
                    this.rules = [...this.rules, ...importedRules];
                    this.showToast('Success', `Imported ${importedRules.length} rules successfully`, 'success');
                } else {
                    this.showToast('Error', 'Invalid import file format', 'error');
                }
                
            } catch (error) {
                this.showToast('Error', 'Failed to import rules: ' + error.message, 'error');
            }
        };
        
        reader.readAsText(file);
    }
    
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(evt);
    }
    
    sanitizeErrorMessage(error) {
        if (!error) return '';
        
        let message = '';
        if (error.body && error.body.message) {
            message = error.body.message;
        } else if (error.message) {
            message = error.message;
        } else {
            message = 'An unknown error occurred';
        }
        
        // Basic HTML escaping to prevent XSS
        return message
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#x27;')
            .replace(/\//g, '&#x2F;');
    }
}

