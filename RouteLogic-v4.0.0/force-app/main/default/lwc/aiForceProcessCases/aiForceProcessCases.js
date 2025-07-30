import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAvailableProviders from '@salesforce/apex/AIBulkProcessingController.getAvailableProviders';
import forceProcessCases from '@salesforce/apex/AIBulkProcessingController.forceProcessCases';

export default class AiForceProcessCases extends LightningElement {
    @track selectedProvider = '';
    @track caseIds = '';
    @track isProcessing = false;
    @track providers = [];
    
    @wire(getAvailableProviders)
    wiredProviders({ data, error }) {
        if (data) {
            this.providers = data.map(provider => ({
                label: provider,
                value: provider
            }));
            
            // Set default provider
            if (this.providers.length > 0 && !this.selectedProvider) {
                this.selectedProvider = this.providers[0].value;
            }
        } else if (error) {
            this.showToast('Error', 'Failed to load AI providers', 'error');
        }
    }
    
    get hasProviders() {
        return this.providers && this.providers.length > 0;
    }
    
    get isFormValid() {
        return this.selectedProvider && this.caseIds.trim() && !this.isProcessing;
    }
    
    get caseIdsList() {
        if (!this.caseIds.trim()) return [];
        
        return this.caseIds
            .split(/[,\n\r\s]+/)
            .map(id => id.trim())
            .filter(id => id.length > 0);
    }
    
    get caseCountMessage() {
        const count = this.caseIdsList.length;
        if (count === 0) return 'No valid case IDs entered';
        if (count === 1) return '1 case ready for processing';
        return `${count} cases ready for processing`;
    }
    
    get caseCountClass() {
        const count = this.caseIdsList.length;
        if (count === 0) return 'case-count-neutral';
        if (count > 100) return 'case-count-error';
        if (count > 50) return 'case-count-warning';
        return 'case-count-valid';
    }
    
    get isFormDisabled() {
        return !this.isFormValid || !this.hasProviders;
    }
    
    handleProviderChange(event) {
        this.selectedProvider = event.detail.value;
    }
    
    handleCaseIdsChange(event) {
        this.caseIds = event.detail.value;
    }
    
    async handleForceProcess() {
        if (!this.isFormValid) {
            this.showToast('Error', 'Please select a provider and enter case IDs', 'error');
            return;
        }
        
        const caseIdsList = this.caseIdsList;
        
        // Validate case IDs format
        const invalidIds = caseIdsList.filter(id => !this.isValidSalesforceId(id));
        if (invalidIds.length > 0) {
            this.showToast(
                'Error', 
                `Invalid case IDs: ${invalidIds.join(', ')}`, 
                'error'
            );
            return;
        }
        
        if (caseIdsList.length > 100) {
            this.showToast(
                'Error', 
                'Maximum 100 cases can be processed at once', 
                'error'
            );
            return;
        }
        
        this.isProcessing = true;
        
        try {
            const jobId = await forceProcessCases({
                caseIds: caseIdsList,
                provider: this.selectedProvider
            });
            
            if (jobId) {
                this.showToast(
                    'Success', 
                    `Processing initiated for ${caseIdsList.length} cases. Job ID: ${jobId}`, 
                    'success'
                );
                
                // Clear form
                this.caseIds = '';
                
                // Dispatch success event for parent components
                this.dispatchEvent(new CustomEvent('processingstarted', {
                    detail: {
                        jobId: jobId,
                        caseCount: caseIdsList.length,
                        provider: this.selectedProvider
                    }
                }));
            } else {
                this.showToast('Warning', 'No processing job was created', 'warning');
            }
        } catch (error) {
            console.error('Force processing error:', error);
            this.showToast(
                'Error', 
                error.body?.message || 'Failed to initiate processing', 
                'error'
            );
        } finally {
            this.isProcessing = false;
        }
    }
    
    handleClear() {
        this.caseIds = '';
    }
    
    isValidSalesforceId(id) {
        // Basic Salesforce ID validation (15 or 18 characters)
        const sfIdRegex = /^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/;
        return sfIdRegex.test(id);
    }
    
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title,
            message,
            variant
        });
        this.dispatchEvent(event);
    }
    
    // Help text for users
    get helpText() {
        return 'Enter Case IDs separated by commas, spaces, or new lines. Maximum 100 cases per batch.';
    }
    
    get exampleText() {
        return 'Example: 5003000000abcDE, 5003000000xyzFG';
    }
}