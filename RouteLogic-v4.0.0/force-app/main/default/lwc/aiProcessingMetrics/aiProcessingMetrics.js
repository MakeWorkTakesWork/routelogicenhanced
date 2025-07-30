import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getDetailedMetrics from '@salesforce/apex/AIBulkProcessingController.getDetailedMetrics';
import getActiveJobs from '@salesforce/apex/AIBulkProcessingController.getActiveJobs';

export default class AiProcessingMetrics extends LightningElement {
    @track metrics = [];
    @track activeJobs = [];
    @track showJobs = false;
    
    // Column definitions for metrics table
    metricsColumns = [
        {
            label: 'Batch ID',
            fieldName: 'batchId',
            type: 'text',
            cellAttributes: { class: 'slds-text-color_weak' }
        },
        {
            label: 'Total Requests',
            fieldName: 'totalRequests',
            type: 'number'
        },
        {
            label: 'Successful',
            fieldName: 'successfulRequests',
            type: 'number',
            cellAttributes: { class: 'slds-text-color_success' }
        },
        {
            label: 'Failed',
            fieldName: 'failedRequests',
            type: 'number',
            cellAttributes: { class: 'slds-text-color_error' }
        },
        {
            label: 'Success Rate',
            fieldName: 'successRate',
            type: 'percent',
            typeAttributes: {
                minimumFractionDigits: 1,
                maximumFractionDigits: 1
            },
            cellAttributes: { alignment: 'left' }
        },
        {
            label: 'Avg Time (ms)',
            fieldName: 'averageTimePerRequest',
            type: 'number',
            typeAttributes: {
                minimumFractionDigits: 2,
                maximumFractionDigits: 2
            }
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
    
    // Column definitions for active jobs table
    jobsColumns = [
        {
            label: 'Job ID',
            fieldName: 'jobId',
            type: 'text',
            cellAttributes: { class: 'slds-text-color_weak' }
        },
        {
            label: 'Status',
            fieldName: 'status',
            type: 'text'
        },
        {
            label: 'Progress',
            fieldName: 'progressPercentage',
            type: 'percent',
            typeAttributes: {
                minimumFractionDigits: 1,
                maximumFractionDigits: 1
            }
        },
        {
            label: 'Items Processed',
            fieldName: 'itemsProcessed',
            type: 'number'
        },
        {
            label: 'Total Items',
            fieldName: 'totalItems',
            type: 'number'
        },
        {
            label: 'Errors',
            fieldName: 'numberOfErrors',
            type: 'number',
            cellAttributes: { class: 'slds-text-color_error' }
        },
        {
            label: 'Created By',
            fieldName: 'createdByName',
            type: 'text'
        },
        {
            label: 'Created Date',
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
    
    // Wire methods
    wiredMetricsResult;
    wiredJobsResult;
    
    @wire(getDetailedMetrics)
    wiredMetrics(result) {
        this.wiredMetricsResult = result;
        if (result.data) {
            this.metrics = result.data.map(metric => ({
                ...metric,
                successRate: metric.successRate / 100 // Convert to decimal for percentage display
            }));
        }
    }
    
    @wire(getActiveJobs)
    wiredJobs(result) {
        this.wiredJobsResult = result;
        if (result.data) {
            this.activeJobs = result.data.map(job => ({
                ...job,
                progressPercentage: job.progressPercentage / 100 // Convert to decimal for percentage display
            }));
        }
    }
    
    // Computed properties
    get hasMetrics() {
        return this.metrics && this.metrics.length > 0;
    }
    
    get hasActiveJobs() {
        return this.activeJobs && this.activeJobs.length > 0;
    }
    
    get jobsButtonLabel() {
        return this.showJobs ? 'Hide Active Jobs' : `Show Active Jobs (${this.activeJobs.length})`;
    }
    
    get totalMetricsCount() {
        return this.metrics.length;
    }
    
    get totalSuccessfulRequests() {
        return this.metrics.reduce((sum, metric) => sum + metric.totalRequests, 0);
    }
    
    get averageSuccessRate() {
        if (this.metrics.length === 0) return 0;
        const totalRate = this.metrics.reduce((sum, metric) => sum + (metric.successRate * 100), 0);
        return (totalRate / this.metrics.length).toFixed(1);
    }
    
    get chartData() {
        // Prepare data for success rate trend chart
        return this.metrics.slice(-10).map(metric => ({
            label: metric.batchId.substring(0, 8),
            value: metric.successRate * 100
        }));
    }
    
    // Event handlers
    handleRefresh() {
        return Promise.all([
            refreshApex(this.wiredMetricsResult),
            refreshApex(this.wiredJobsResult)
        ]);
    }
    
    handleToggleJobs() {
        this.showJobs = !this.showJobs;
    }
}