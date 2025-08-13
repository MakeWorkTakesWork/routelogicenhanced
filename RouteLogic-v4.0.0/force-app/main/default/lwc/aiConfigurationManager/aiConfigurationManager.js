/**
 * @description Lightning Web Component for managing AI Processing Configuration
 * Provides a user-friendly interface for administrators and service managers
 * to configure AI processing settings without editing custom metadata
 * @author RouteLogic Team
 * @date 2025-01-20
 */
import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

// Apex methods
import getConfigurationSettings from '@salesforce/apex/AIConfigurationController.getConfigurationSettings';
import updateConfigurationSetting from '@salesforce/apex/AIConfigurationController.updateConfigurationSetting';
import getProviderSettings from '@salesforce/apex/AIConfigurationController.getProviderSettings';
import updateProviderSetting from '@salesforce/apex/AIConfigurationController.updateProviderSetting';
import validateConfiguration from '@salesforce/apex/AIConfigurationController.validateConfiguration';
import testProviderConnection from '@salesforce/apex/AIConfigurationController.testProviderConnection';

// Labels
import CONFIG_MANAGER_TITLE from '@salesforce/label/c.AI_Config_Manager_Title';
import SAVE_SUCCESS from '@salesforce/label/c.Save_Success_Message';
import VALIDATION_ERROR from '@salesforce/label/c.Validation_Error_Message';

export default class AiConfigurationManager extends LightningElement {
    @track activeTab = 'general';
    @track isLoading = false;
    @track isSaving = false;
    @track validationResults = {};
    @track expandedSections = ['general', 'providers'];
    
    // Configuration data
    @track generalSettings = {};
    @track providerSettings = [];
    @track isDirty = false;
    
    // Wired data
    wiredConfigResult;
    wiredProvidersResult;
    
    // Labels
    label = {
        title: CONFIG_MANAGER_TITLE || 'AI Configuration Manager',
        saveSuccess: SAVE_SUCCESS || 'Configuration saved successfully',
        validationError: VALIDATION_ERROR || 'Please fix validation errors before saving'
    };
    
    // Tab options
    get tabOptions() {
        return [
            { label: 'General Settings', value: 'general' },
            { label: 'AI Providers', value: 'providers' },
            { label: 'Processing Rules', value: 'rules' },
            { label: 'Validation', value: 'validation' }
        ];
    }
    
    @wire(getConfigurationSettings)
    wiredConfig(result) {
        this.wiredConfigResult = result;
        if (result.data) {
            this.generalSettings = this.processConfigSettings(result.data);
            this.isLoading = false;
        } else if (result.error) {
            this.handleError('Failed to load configuration settings', result.error);
        }
    }
    
    @wire(getProviderSettings)
    wiredProviders(result) {
        this.wiredProvidersResult = result;
        if (result.data) {
            this.providerSettings = result.data.map(provider => ({
                ...provider,
                isExpanded: false,
                isEditing: false,
                originalValues: { ...provider },
                statusLabel: provider.connectionStatus ? provider.connectionStatus : 'Unknown',
                statusVariant: provider.connectionStatus === 'success' ? 'success' : 'base'
            }));
        } else if (result.error) {
            this.handleError('Failed to load provider settings', result.error);
        }
    }
    
    processConfigSettings(data) {
        return {
            batchSize: {
                label: 'Default Batch Size',
                value: data.Default_Batch_Size__c || 100,
                type: 'number',
                min: 1,
                max: 200,
                helpText: 'Number of cases to process in each batch',
                category: 'processing'
            },
            retryAttempts: {
                label: 'Max Retry Attempts',
                value: data.Max_Retry_Attempts__c || 3,
                type: 'number',
                min: 0,
                max: 5,
                helpText: 'Maximum number of retry attempts for failed requests',
                category: 'processing'
            },
            circuitBreakerThreshold: {
                label: 'Circuit Breaker Threshold',
                value: data.Circuit_Breaker_Threshold__c || 5,
                type: 'number',
                min: 1,
                max: 20,
                helpText: 'Number of consecutive failures before circuit breaker opens',
                category: 'resilience'
            },
            circuitBreakerTimeout: {
                label: 'Circuit Breaker Timeout (minutes)',
                value: data.Circuit_Breaker_Timeout__c || 30,
                type: 'number',
                min: 5,
                max: 120,
                helpText: 'Time to wait before attempting to close circuit breaker',
                category: 'resilience'
            },
            apiTimeout: {
                label: 'API Timeout (seconds)',
                value: data.API_Timeout__c || 30,
                type: 'number',
                min: 10,
                max: 120,
                helpText: 'Maximum time to wait for AI provider response',
                category: 'api'
            },
            enableDebugLogging: {
                label: 'Enable Debug Logging',
                value: data.Enable_Debug_Logging__c || false,
                type: 'boolean',
                helpText: 'Enable detailed logging for troubleshooting',
                category: 'logging'
            },
            logRetentionDays: {
                label: 'Log Retention Days',
                value: data.Log_Retention_Days__c || 30,
                type: 'number',
                min: 7,
                max: 90,
                helpText: 'Number of days to retain processing logs',
                category: 'logging'
            }
        };
    }
    
    handleTabChange(event) {
        this.activeTab = event.target.value;
        if (this.activeTab === 'validation') {
            this.runValidation();
        }
    }
    
    handleGeneralSettingChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        
        this.generalSettings[field].value = value;
        this.isDirty = true;
    }
    
    handleProviderToggle(event) {
        const providerId = event.currentTarget.dataset.providerId;
        const provider = this.providerSettings.find(p => p.Id === providerId);
        if (provider) {
            provider.isExpanded = !provider.isExpanded;
        }
    }
    
    handleProviderEdit(event) {
        const providerId = event.currentTarget.dataset.providerId;
        const provider = this.providerSettings.find(p => p.Id === providerId);
        if (provider) {
            provider.isEditing = true;
        }
    }
    
    handleProviderCancel(event) {
        const providerId = event.currentTarget.dataset.providerId;
        const provider = this.providerSettings.find(p => p.Id === providerId);
        if (provider) {
            // Restore original values
            Object.keys(provider.originalValues).forEach(key => {
                if (key !== 'isExpanded' && key !== 'isEditing') {
                    provider[key] = provider.originalValues[key];
                }
            });
            provider.isEditing = false;
        }
    }
    
    handleProviderFieldChange(event) {
        const providerId = event.currentTarget.dataset.providerId;
        const field = event.currentTarget.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        
        const provider = this.providerSettings.find(p => p.Id === providerId);
        if (provider) {
            provider[field] = value;
            this.isDirty = true;
        }
    }
    
    async handleProviderSave(event) {
        const providerId = event.currentTarget.dataset.providerId;
        const provider = this.providerSettings.find(p => p.Id === providerId);
        
        if (!provider) return;
        
        this.isSaving = true;
        
        try {
            await updateProviderSetting({
                providerId: provider.Id,
                settings: {
                    Provider_Name__c: provider.Provider_Name__c,
                    Is_Active__c: provider.Is_Active__c,
                    API_Endpoint__c: provider.API_Endpoint__c,
                    Max_Batch_Size__c: provider.Max_Batch_Size__c,
                    Timeout_ms__c: provider.Timeout_ms__c,
                    Priority__c: provider.Priority__c
                }
            });
            
            provider.originalValues = { ...provider };
            provider.isEditing = false;
            
            this.showToast('Success', 'Provider settings updated', 'success');
        } catch (error) {
            this.handleError('Failed to save provider settings', error);
        } finally {
            this.isSaving = false;
        }
    }
    
    async handleTestConnection(event) {
        const providerId = event.currentTarget.dataset.providerId;
        const provider = this.providerSettings.find(p => p.Id === providerId);
        
        if (!provider) return;
        
        const button = event.currentTarget;
        button.disabled = true;
        button.label = 'Testing...';
        
        try {
            const result = await testProviderConnection({ providerId: provider.Id });
            
            if (result.success) {
                this.showToast('Success', `Connection to ${provider.Provider_Name__c} successful`, 'success');
                provider.connectionStatus = 'success';
            } else {
                this.showToast('Error', `Connection failed: ${result.message}`, 'error');
                provider.connectionStatus = 'error';
            }
        } catch (error) {
            this.handleError('Connection test failed', error);
            provider.connectionStatus = 'error';
        } finally {
            button.disabled = false;
            button.label = 'Test Connection';
        }
    }
    
    async handleSaveGeneralSettings() {
        this.isSaving = true;
        
        try {
            // Validate settings first
            const validation = await this.validateSettings();
            if (!validation.isValid) {
                this.showToast('Error', this.label.validationError, 'error');
                return;
            }
            
            // Save each setting
            const savePromises = Object.entries(this.generalSettings).map(([key, setting]) => {
                return updateConfigurationSetting({
                    settingName: key,
                    value: setting.value
                });
            });
            
            await Promise.all(savePromises);
            
            this.isDirty = false;
            this.showToast('Success', this.label.saveSuccess, 'success');
            
            // Refresh data
            return refreshApex(this.wiredConfigResult);
        } catch (error) {
            this.handleError('Failed to save configuration', error);
        } finally {
            this.isSaving = false;
        }
    }
    
    async runValidation() {
        this.isLoading = true;
        
        try {
            const results = await validateConfiguration();
            this.validationResults = results;
        } catch (error) {
            this.handleError('Validation failed', error);
        } finally {
            this.isLoading = false;
        }
    }
    
    async validateSettings() {
        // Client-side validation
        const errors = [];
        
        // Validate general settings
        Object.entries(this.generalSettings).forEach(([key, setting]) => {
            if (setting.type === 'number') {
                const value = Number(setting.value);
                if (isNaN(value) || value < setting.min || value > setting.max) {
                    errors.push(`${setting.label} must be between ${setting.min} and ${setting.max}`);
                }
            }
        });
        
        // Validate provider settings
        const activeProviders = this.providerSettings.filter(p => p.Is_Active__c);
        if (activeProviders.length === 0) {
            errors.push('At least one AI provider must be active');
        }
        
        return {
            isValid: errors.length === 0,
            errors: errors
        };
    }
    
    handleRefresh() {
        this.isLoading = true;
        Promise.all([
            refreshApex(this.wiredConfigResult),
            refreshApex(this.wiredProvidersResult)
        ]).then(() => {
            this.isLoading = false;
        });
    }
    
    handleError(message, error) {
        console.error(message, error);
        this.isLoading = false;
        this.isSaving = false;
        
        const errorMessage = error.body ? error.body.message : error.message || 'Unknown error';
        this.showToast('Error', `${message}: ${errorMessage}`, 'error');
    }
    
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant
        }));
    }
    
    // Getters for template
    get generalSettingsByCategory() {
        const categories = {};
        Object.entries(this.generalSettings).forEach(([key, setting]) => {
            if (!categories[setting.category]) {
                categories[setting.category] = [];
            }
            categories[setting.category].push({ key, ...setting });
        });
        return Object.entries(categories).map(([category, settings]) => ({
            category: category.charAt(0).toUpperCase() + category.slice(1),
            settings
        }));
    }
    
    get activeProviders() {
        return this.providerSettings.filter(p => p.Is_Active__c);
    }
    
    get inactiveProviders() {
        return this.providerSettings.filter(p => !p.Is_Active__c);
    }
    
    get hasUnsavedChanges() {
        return this.isDirty;
    }
    
    get validationStatus() {
        if (!this.validationResults || Object.keys(this.validationResults).length === 0) {
            return 'Not validated';
        }
        
        const hasErrors = Object.values(this.validationResults).some(v => !v.success);
        return hasErrors ? 'Validation failed' : 'Validation passed';
    }
    
    get validationStatusVariant() {
        if (!this.validationResults || Object.keys(this.validationResults).length === 0) {
            return 'base';
        }
        
        const hasErrors = Object.values(this.validationResults).some(v => !v.success);
        return hasErrors ? 'destructive' : 'success';
    }
}