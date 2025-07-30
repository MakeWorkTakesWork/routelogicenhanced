import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import getActiveJobs from '@salesforce/apex/RouteLogicJobTracker.getActiveJobs';
import getJobHistory from '@salesforce/apex/RouteLogicJobTracker.getJobHistory';
import getJobMetrics from '@salesforce/apex/RouteLogicJobTracker.getJobMetrics';
import cancelJob from '@salesforce/apex/RouteLogicJobTracker.cancelJob';
import processDeadLetterQueue from '@salesforce/apex/RouteLogicRetryHandler.processDeadLetterQueue';

export default class RouteLogicJobMonitor extends LightningElement {
    @track activeJobs = [];
    @track jobHistory = [];
    @track jobMetrics = {};
    @track isLoading = true;
    @track error;
    @track errorMessage;
    @track selectedTimeframe = '24';
    @track selectedView = 'active';
    @track autoRefresh = true;
    
    // Real-time monitoring
    subscription = {};
    channelName = '/event/RouteLogic_Job_Status__e';
    
    // Refresh interval
    refreshInterval;
    
    // Wire results
    wiredActiveJobsResult;
    wiredJobHistoryResult;
    wiredJobMetricsResult;
    
    get timeframeOptions() {
        return [
            { label: 'Last 1 Hour', value: '1' },
            { label: 'Last 6 Hours', value: '6' },
            { label: 'Last 24 Hours', value: '24' },
            { label: 'Last 7 Days', value: '168' },
            { label: 'Last 30 Days', value: '720' }
        ];
    }
    
    get viewOptions() {
        return [
            { label: 'Active Jobs', value: 'active' },
            { label: 'Job History', value: 'history' },
            { label: 'Performance Metrics', value: 'metrics' },
            { label: 'Dead Letter Queue', value: 'dlq' }
        ];
    }
    
    get isActiveView() {
        return this.selectedView === 'active';
    }
    
    get isHistoryView() {
        return this.selectedView === 'history';
    }
    
    get isMetricsView() {
        return this.selectedView === 'metrics';
    }
    
    get isDlqView() {
        return this.selectedView === 'dlq';
    }
    
    get activeJobColumns() {
        return [
            { 
                label: 'Job ID', 
                fieldName: 'jobId', 
                type: 'text',
                cellAttributes: { class: 'slds-text-font_monospace' }
            },
            { label: 'Job Type', fieldName: 'jobType', type: 'text' },
            { 
                label: 'Status', 
                fieldName: 'status', 
                type: 'text',
                cellAttributes: { 
                    class: { fieldName: 'statusClass' },
                    iconName: { fieldName: 'statusIcon' }
                }
            },
            { 
                label: 'Records', 
                fieldName: 'recordCount', 
                type: 'number',
                cellAttributes: { alignment: 'right' }
            },
            { 
                label: 'Processed', 
                fieldName: 'processedCount', 
                type: 'number',
                cellAttributes: { alignment: 'right' }
            },
            { 
                label: 'Progress', 
                fieldName: 'progressPercent', 
                type: 'percent',
                typeAttributes: { minimumFractionDigits: 1 }
            },
            { 
                label: 'Retry Count', 
                fieldName: 'retryCount', 
                type: 'number',
                cellAttributes: { alignment: 'right' }
            },
            { 
                label: 'Duration', 
                fieldName: 'durationDisplay', 
                type: 'text'
            },
            {
                type: 'action',
                typeAttributes: {
                    rowActions: [
                        { label: 'Cancel', name: 'cancel' },
                        { label: 'View Details', name: 'details' }
                    ]
                }
            }
        ];
    }
    
    get jobHistoryColumns() {
        return [
            { 
                label: 'Job ID', 
                fieldName: 'jobId', 
                type: 'text',
                cellAttributes: { class: 'slds-text-font_monospace' }
            },
            { label: 'Job Type', fieldName: 'jobType', type: 'text' },
            { 
                label: 'Status', 
                fieldName: 'status', 
                type: 'text',
                cellAttributes: { 
                    class: { fieldName: 'statusClass' },
                    iconName: { fieldName: 'statusIcon' }
                }
            },
            { 
                label: 'Records', 
                fieldName: 'recordCount', 
                type: 'number',
                cellAttributes: { alignment: 'right' }
            },
            { 
                label: 'Processed', 
                fieldName: 'processedCount', 
                type: 'number',
                cellAttributes: { alignment: 'right' }
            },
            { 
                label: 'Success Rate', 
                fieldName: 'successRate', 
                type: 'percent',
                typeAttributes: { minimumFractionDigits: 1 }
            },
            { 
                label: 'Duration', 
                fieldName: 'durationDisplay', 
                type: 'text'
            },
            { 
                label: 'Created', 
                fieldName: 'createdDate', 
                type: 'date',
                typeAttributes: { 
                    year: 'numeric', 
                    month: 'short', 
                    day: '2-digit',
                    hour: '2-digit',
                    minute: '2-digit'
                }
            }
        ];
    }
    
    @wire(getActiveJobs)
    wiredActiveJobs(result) {
        this.wiredActiveJobsResult = result;
        if (result.data) {
            this.activeJobs = this.processJobData(result.data);
            this.error = undefined;
            this.errorMessage = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.errorMessage = this.sanitizeErrorMessage(result.error);
            this.activeJobs = [];
        }
        this.isLoading = false;
    }
    
    @wire(getJobHistory, { hoursBack: '$selectedTimeframe' })
    wiredJobHistory(result) {
        this.wiredJobHistoryResult = result;
        if (result.data) {
            this.jobHistory = this.processJobData(result.data);
            this.error = undefined;
            this.errorMessage = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.errorMessage = this.sanitizeErrorMessage(result.error);
            this.jobHistory = [];
        }
    }
    
    @wire(getJobMetrics, { hoursBack: '$selectedTimeframe' })
    wiredJobMetrics(result) {
        this.wiredJobMetricsResult = result;
        if (result.data) {
            this.jobMetrics = result.data;
            this.error = undefined;
            this.errorMessage = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.errorMessage = this.sanitizeErrorMessage(result.error);
            this.jobMetrics = {};
        }
    }
    
    connectedCallback() {
        // Subscribe to real-time job status updates
        this.subscribeToJobStatusEvents();
        
        // Set up auto-refresh
        if (this.autoRefresh) {
            this.startAutoRefresh();
        }
        
        // Register error listener
        this.registerErrorListener();
    }
    
    disconnectedCallback() {
        // Unsubscribe from events
        this.unsubscribeFromJobStatusEvents();
        
        // Clear auto-refresh
        this.stopAutoRefresh();
    }
    
    subscribeToJobStatusEvents() {
        const messageCallback = (response) => {
            this.handleJobStatusUpdate(response);
        };
        
        subscribe(this.channelName, -1, messageCallback).then(response => {
            this.subscription = response;
            console.log('Successfully subscribed to job status events');
        }).catch(error => {
            console.error('Failed to subscribe to job status events:', error);
        });
    }
    
    unsubscribeFromJobStatusEvents() {
        if (this.subscription) {
            unsubscribe(this.subscription, response => {
                console.log('Unsubscribed from job status events');
            });
        }
    }
    
    registerErrorListener() {
        onError(error => {
            console.error('EMP API error:', error);
        });
    }
    
    handleJobStatusUpdate(response) {
        try {
            const jobUpdate = response.data.payload;
            
            // Update active jobs if this is an active job
            if (this.isActiveView) {
                this.updateActiveJobStatus(jobUpdate);
            }
            
            // Refresh data if needed
            if (jobUpdate.Status__c === 'COMPLETED' || jobUpdate.Status__c === 'FAILED') {
                this.refreshData();
            }
            
            // Show toast for important status changes
            this.showJobStatusToast(jobUpdate);
            
        } catch (error) {
            console.error('Error handling job status update:', error);
        }
    }
    
    updateActiveJobStatus(jobUpdate) {
        const updatedJobs = this.activeJobs.map(job => {
            if (job.jobId === jobUpdate.Job_Id__c) {
                return {
                    ...job,
                    status: jobUpdate.Status__c,
                    processedCount: jobUpdate.Processed_Count__c || job.processedCount,
                    retryCount: jobUpdate.Retry_Count__c || job.retryCount,
                    durationSeconds: jobUpdate.Duration_Seconds__c || job.durationSeconds,
                    errorMessage: jobUpdate.Error_Message__c || job.errorMessage,
                    lastUpdated: new Date(),
                    ...this.calculateJobDisplayProperties({
                        ...job,
                        status: jobUpdate.Status__c,
                        processedCount: jobUpdate.Processed_Count__c || job.processedCount
                    })
                };
            }
            return job;
        });
        
        this.activeJobs = updatedJobs;
    }
    
    showJobStatusToast(jobUpdate) {
        let variant = 'info';
        let title = 'Job Status Update';
        let message = `Job ${jobUpdate.Job_Id__c} status: ${jobUpdate.Status__c}`;
        
        switch (jobUpdate.Status__c) {
            case 'COMPLETED':
                variant = 'success';
                title = 'Job Completed';
                message = `Job ${jobUpdate.Job_Id__c} completed successfully`;
                break;
            case 'FAILED':
                variant = 'error';
                title = 'Job Failed';
                message = `Job ${jobUpdate.Job_Id__c} failed: ${jobUpdate.Error_Message__c || 'Unknown error'}`;
                break;
            case 'RETRY_SCHEDULED':
                variant = 'warning';
                title = 'Job Retry Scheduled';
                message = `Job ${jobUpdate.Job_Id__c} retry scheduled (attempt ${jobUpdate.Retry_Count__c})`;
                break;
        }
        
        this.showToast(title, message, variant);
    }
    
    processJobData(jobs) {
        return jobs.map(job => ({
            ...job,
            ...this.calculateJobDisplayProperties(job)
        }));
    }
    
    calculateJobDisplayProperties(job) {
        // Calculate progress percentage
        const progressPercent = job.recordCount > 0 ? 
                               (job.processedCount / job.recordCount) : 0;
        
        // Calculate success rate
        const successRate = job.recordCount > 0 ? 
                           (job.processedCount / job.recordCount) : 0;
        
        // Format duration
        let durationDisplay = 'N/A';
        if (job.durationSeconds) {
            if (job.durationSeconds < 60) {
                durationDisplay = `${job.durationSeconds}s`;
            } else if (job.durationSeconds < 3600) {
                durationDisplay = `${Math.floor(job.durationSeconds / 60)}m ${job.durationSeconds % 60}s`;
            } else {
                const hours = Math.floor(job.durationSeconds / 3600);
                const minutes = Math.floor((job.durationSeconds % 3600) / 60);
                durationDisplay = `${hours}h ${minutes}m`;
            }
        } else if (job.createdDate) {
            // Calculate running duration
            const now = new Date();
            const created = new Date(job.createdDate);
            const runningSeconds = Math.floor((now - created) / 1000);
            
            if (runningSeconds < 60) {
                durationDisplay = `${runningSeconds}s (running)`;
            } else if (runningSeconds < 3600) {
                durationDisplay = `${Math.floor(runningSeconds / 60)}m (running)`;
            } else {
                const hours = Math.floor(runningSeconds / 3600);
                const minutes = Math.floor((runningSeconds % 3600) / 60);
                durationDisplay = `${hours}h ${minutes}m (running)`;
            }
        }
        
        // Determine status styling
        let statusClass = 'slds-text-color_default';
        let statusIcon = 'utility:info';
        
        switch (job.status) {
            case 'COMPLETED':
                statusClass = 'slds-text-color_success';
                statusIcon = 'utility:success';
                break;
            case 'FAILED':
                statusClass = 'slds-text-color_error';
                statusIcon = 'utility:error';
                break;
            case 'PROCESSING':
                statusClass = 'slds-text-color_default';
                statusIcon = 'utility:spinner';
                break;
            case 'RETRY_SCHEDULED':
                statusClass = 'slds-text-color_warning';
                statusIcon = 'utility:warning';
                break;
            case 'QUEUED':
                statusClass = 'slds-text-color_weak';
                statusIcon = 'utility:clock';
                break;
        }
        
        return {
            progressPercent,
            successRate,
            durationDisplay,
            statusClass,
            statusIcon
        };
    }
    
    handleTimeframeChange(event) {
        this.selectedTimeframe = event.detail.value;
        this.refreshData();
    }
    
    handleViewChange(event) {
        this.selectedView = event.detail.value;
        this.refreshData();
    }
    
    handleAutoRefreshToggle(event) {
        this.autoRefresh = event.target.checked;
        
        if (this.autoRefresh) {
            this.startAutoRefresh();
        } else {
            this.stopAutoRefresh();
        }
    }
    
    startAutoRefresh() {
        this.refreshInterval = setInterval(() => {
            this.refreshData();
        }, 30000); // Refresh every 30 seconds
    }
    
    stopAutoRefresh() {
        if (this.refreshInterval) {
            clearInterval(this.refreshInterval);
            this.refreshInterval = null;
        }
    }
    
    handleRefresh() {
        this.isLoading = true;
        this.refreshData();
    }
    
    refreshData() {
        Promise.all([
            refreshApex(this.wiredActiveJobsResult),
            refreshApex(this.wiredJobHistoryResult),
            refreshApex(this.wiredJobMetricsResult)
        ]).then(() => {
            this.isLoading = false;
        }).catch(error => {
            this.isLoading = false;
            this.showToast('Error', 'Failed to refresh data: ' + error.body?.message, 'error');
        });
    }
    
    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        
        switch (actionName) {
            case 'cancel':
                this.handleCancelJob(row.jobId);
                break;
            case 'details':
                this.handleViewJobDetails(row);
                break;
        }
    }
    
    handleCancelJob(jobId) {
        cancelJob({ jobId: jobId, reason: 'Cancelled by user' })
            .then(() => {
                this.showToast('Success', 'Job cancelled successfully', 'success');
                this.refreshData();
            })
            .catch(error => {
                this.showToast('Error', 'Failed to cancel job: ' + error.body?.message, 'error');
            });
    }
    
    handleViewJobDetails(job) {
        // Show job details in a modal or navigate to detail page
        console.log('View job details:', job);
        // Implementation would depend on requirements
    }
    
    handleProcessDlq() {
        processDeadLetterQueue({ maxEntries: 10 })
            .then(result => {
                this.showToast('Success', `Processed ${result} dead letter queue entries`, 'success');
                this.refreshData();
            })
            .catch(error => {
                this.showToast('Error', 'Failed to process dead letter queue: ' + error.body?.message, 'error');
            });
    }
    
    get formattedJobMetrics() {
        if (!this.jobMetrics) return {};
        
        return {
            totalJobs: this.jobMetrics.totalJobs || 0,
            completedJobs: this.jobMetrics.completedJobs || 0,
            failedJobs: this.jobMetrics.failedJobs || 0,
            retryJobs: this.jobMetrics.retryJobs || 0,
            successRate: this.jobMetrics.successRate ? this.jobMetrics.successRate.toFixed(1) + '%' : '0%',
            averageDuration: this.formatDuration(this.jobMetrics.averageDurationSeconds),
            recordsPerSecond: this.jobMetrics.recordsPerSecond ? this.jobMetrics.recordsPerSecond.toFixed(2) : '0'
        };
    }
    
    formatDuration(seconds) {
        if (!seconds) return '0s';
        
        if (seconds < 60) {
            return `${seconds}s`;
        } else if (seconds < 3600) {
            return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
        } else {
            const hours = Math.floor(seconds / 3600);
            const minutes = Math.floor((seconds % 3600) / 60);
            return `${hours}h ${minutes}m`;
        }
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

