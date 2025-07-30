import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProcessingStatus from '@salesforce/apex/AIBulkProcessingController.getProcessingStatus';
import initiateBulkProcessing from '@salesforce/apex/AIBulkProcessingController.initiateBulkProcessing';
import processRetryQueue from '@salesforce/apex/AIBulkProcessingController.processRetryQueue';
import cancelAllJobs from '@salesforce/apex/AIBulkProcessingController.cancelAllJobs';

export default class AiBulkProcessingDashboard extends LightningElement {
    @track processingData = {};
    @track isLoading = false;
    @track showAdvanced = false;
    
    // Refresh interval (30 seconds)
    refreshInterval = 30000;
    intervalId;
    
    // Wire the processing status
    wiredProcessingResult;
    
    @wire(getProcessingStatus)
    wiredProcessingStatus(result) {
        this.wiredProcessingResult = result;
        if (result.data) {
            this.processingData = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.processingData = {};
        }
    }
    
    connectedCallback() {
        // Start auto-refresh
        this.startAutoRefresh();
    }
    
    disconnectedCallback() {
        // Clear auto-refresh
        this.stopAutoRefresh();
    }
    
    startAutoRefresh() {
        this.intervalId = setInterval(() => {
            this.refreshData();
        }, this.refreshInterval);
    }
    
    stopAutoRefresh() {
        if (this.intervalId) {
            clearInterval(this.intervalId);
            this.intervalId = null;
        }
    }
    
    async refreshData() {
        try {
            await refreshApex(this.wiredProcessingResult);
        } catch (error) {
            console.error('Error refreshing data:', error);
        }
    }
    
    // Computed properties for UI display
    get totalRequests() {
        return this.processingData.pendingCount + 
               this.processingData.processingCount + 
               this.processingData.completedCount + 
               this.processingData.failedCount || 0;
    }
    
    get successRate() {
        const total = this.totalRequests;
        if (total === 0) return 0;
        return Math.round((this.processingData.completedCount / total) * 100);
    }
    
    get progressBarClass() {
        const rate = this.successRate;
        if (rate >= 80) return 'slds-progress-bar__value progress-success';
        if (rate >= 60) return 'slds-progress-bar__value progress-warning';
        return 'slds-progress-bar__value progress-danger';
    }
    
    get statusCards() {
        return [
            {
                id: 'pending',
                title: 'Pending',
                count: this.processingData.pendingCount || 0,
                icon: 'utility:clock',
                variant: 'base'
            },
            {
                id: 'processing',
                title: 'Processing',
                count: this.processingData.processingCount || 0,
                icon: 'utility:refresh',
                variant: 'base'
            },
            {
                id: 'completed',
                title: 'Completed',
                count: this.processingData.completedCount || 0,
                icon: 'utility:success',
                variant: 'base'
            },
            {
                id: 'failed',
                title: 'Failed',
                count: this.processingData.failedCount || 0,
                icon: 'utility:error',
                variant: 'base'
            }
        ];
    }
    
    get retryQueueInfo() {
        return {
            count: this.processingData.retryQueueCount || 0,
            hasItems: (this.processingData.retryQueueCount || 0) > 0
        };
    }
    
    get activeJobsInfo() {
        return {
            count: this.processingData.activeJobs || 0,
            hasJobs: (this.processingData.activeJobs || 0) > 0
        };
    }
    
    get averageProcessingTime() {
        const time = this.processingData.averageProcessingTime || 0;
        return `${time.toFixed(2)}ms`;
    }
    
    // Event handlers
    async handleInitiateProcessing() {
        this.isLoading = true;
        try {
            const result = await initiateBulkProcessing({ batchSize: 200 });
            if (result) {
                this.showToast('Success', 'Bulk processing initiated successfully', 'success');
                await this.refreshData();
            } else {
                this.showToast('Info', 'No pending requests found', 'info');
            }
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Failed to initiate processing', 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    async handleProcessRetries() {
        this.isLoading = true;
        try {
            const processedCount = await processRetryQueue();
            this.showToast('Success', `Processed ${processedCount} retry requests`, 'success');
            await this.refreshData();
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Failed to process retries', 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    async handleCancelJobs() {
        this.isLoading = true;
        try {
            const cancelledCount = await cancelAllJobs();
            this.showToast('Success', `Cancelled ${cancelledCount} active jobs`, 'success');
            await this.refreshData();
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Failed to cancel jobs', 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    handleRefresh() {
        this.refreshData();
    }
    
    handleToggleAdvanced() {
        this.showAdvanced = !this.showAdvanced;
    }
    
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title,
            message,
            variant
        });
        this.dispatchEvent(event);
    }
}