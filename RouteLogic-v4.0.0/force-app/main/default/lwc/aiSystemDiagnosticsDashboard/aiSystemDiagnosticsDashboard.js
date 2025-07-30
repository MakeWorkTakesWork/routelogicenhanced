import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSystemDiagnostics from '@salesforce/apex/AISystemMonitoringService.getSystemDiagnostics';
import checkAllProviders from '@salesforce/apex/AIProviderHealthCheckService.checkAllProviders';

export default class AiSystemDiagnosticsDashboard extends LightningElement {
    @track diagnosticsData;
    @track isLoading = true;
    @track error;
    @track selectedView = 'overview';
    
    wiredDiagnosticsResult;
    refreshInterval;
    
    // Chart data
    @track queueChartData;
    @track performanceChartData;
    @track providerHealthData;
    
    get viewOptions() {
        return [
            { label: 'Overview', value: 'overview' },
            { label: 'Queue Metrics', value: 'queue' },
            { label: 'Provider Health', value: 'providers' },
            { label: 'Performance', value: 'performance' },
            { label: 'System Limits', value: 'limits' },
            { label: 'Recent Errors', value: 'errors' }
        ];
    }
    
    get isOverviewView() {
        return this.selectedView === 'overview';
    }
    
    get isQueueView() {
        return this.selectedView === 'queue';
    }
    
    get isProvidersView() {
        return this.selectedView === 'providers';
    }
    
    get isPerformanceView() {
        return this.selectedView === 'performance';
    }
    
    get isLimitsView() {
        return this.selectedView === 'limits';
    }
    
    get isErrorsView() {
        return this.selectedView === 'errors';
    }
    
    get overallHealthClass() {
        if (!this.diagnosticsData) return 'slds-badge';
        
        const health = this.diagnosticsData.overallHealth;
        if (health >= 90) return 'slds-badge slds-theme_success';
        if (health >= 70) return 'slds-badge slds-theme_warning';
        return 'slds-badge slds-theme_error';
    }
    
    get overallHealthIcon() {
        if (!this.diagnosticsData) return 'utility:question';
        
        const health = this.diagnosticsData.overallHealth;
        if (health >= 90) return 'utility:success';
        if (health >= 70) return 'utility:warning';
        return 'utility:error';
    }
    
    @wire(getSystemDiagnostics)
    wiredDiagnostics(result) {
        this.wiredDiagnosticsResult = result;
        this.isLoading = true;
        
        if (result.data) {
            this.diagnosticsData = result.data;
            this.error = undefined;
            this.processChartData();
            this.isLoading = false;
        } else if (result.error) {
            this.error = result.error;
            this.diagnosticsData = undefined;
            this.isLoading = false;
            this.showError('Failed to load diagnostics', result.error);
        }
    }
    
    connectedCallback() {
        // Set up auto-refresh every 30 seconds
        this.refreshInterval = setInterval(() => {
            this.handleRefresh();
        }, 30000);
    }
    
    disconnectedCallback() {
        // Clear interval when component is destroyed
        if (this.refreshInterval) {
            clearInterval(this.refreshInterval);
        }
    }
    
    handleViewChange(event) {
        this.selectedView = event.detail.value;
    }
    
    handleRefresh() {
        this.isLoading = true;
        refreshApex(this.wiredDiagnosticsResult)
            .then(() => {
                this.showToast('Success', 'Dashboard refreshed', 'success');
            })
            .catch(error => {
                this.showError('Failed to refresh', error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
    
    handleRunHealthCheck() {
        this.isLoading = true;
        
        checkAllProviders()
            .then(result => {
                this.showToast('Success', 'Health check completed', 'success');
                return refreshApex(this.wiredDiagnosticsResult);
            })
            .catch(error => {
                this.showError('Health check failed', error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
    
    processChartData() {
        if (!this.diagnosticsData) return;
        
        // Queue metrics chart data
        const queueMetrics = this.diagnosticsData.queueMetrics;
        this.queueChartData = {
            labels: ['Pending', 'Processing', 'Completed', 'Failed'],
            datasets: [{
                label: 'Queue Status',
                data: [
                    queueMetrics.pendingCount,
                    queueMetrics.processingCount,
                    queueMetrics.completedCount,
                    queueMetrics.failedCount
                ],
                backgroundColor: [
                    'rgba(255, 206, 86, 0.7)',
                    'rgba(54, 162, 235, 0.7)',
                    'rgba(75, 192, 192, 0.7)',
                    'rgba(255, 99, 132, 0.7)'
                ]
            }]
        };
        
        // Provider health data
        this.providerHealthData = [];
        if (this.diagnosticsData.providerHealth) {
            Object.values(this.diagnosticsData.providerHealth).forEach(provider => {
                this.providerHealthData.push({
                    id: provider.providerName,
                    name: provider.providerName,
                    status: provider.status,
                    statusClass: this.getStatusClass(provider.status),
                    statusIcon: this.getStatusIcon(provider.status),
                    responseTime: provider.responseTime,
                    uptime: provider.uptimePercentage ? provider.uptimePercentage.toFixed(1) : '0.0',
                    lastCheck: this.formatDateTime(provider.lastCheckTime),
                    message: provider.message
                });
            });
        }
        
        // Performance chart data
        const perfMetrics = this.diagnosticsData.performanceMetrics;
        this.performanceChartData = {
            successRate: perfMetrics.successRate ? perfMetrics.successRate.toFixed(1) : '0.0',
            throughput: perfMetrics.throughputPerHour ? perfMetrics.throughputPerHour.toFixed(0) : '0'
        };
    }
    
    getStatusClass(status) {
        switch(status) {
            case 'Healthy':
                return 'slds-text-color_success';
            case 'Degraded':
                return 'slds-text-color_warning';
            case 'Unhealthy':
                return 'slds-text-color_error';
            default:
                return 'slds-text-color_weak';
        }
    }
    
    getStatusIcon(status) {
        switch(status) {
            case 'Healthy':
                return 'utility:success';
            case 'Degraded':
                return 'utility:warning';
            case 'Unhealthy':
                return 'utility:error';
            default:
                return 'utility:question';
        }
    }
    
    formatDateTime(dateTime) {
        if (!dateTime) return 'Never';
        
        const date = new Date(dateTime);
        const now = new Date();
        const diffMs = now - date;
        const diffMins = Math.floor(diffMs / 60000);
        
        if (diffMins < 1) return 'Just now';
        if (diffMins < 60) return `${diffMins} minutes ago`;
        if (diffMins < 1440) return `${Math.floor(diffMins / 60)} hours ago`;
        return `${Math.floor(diffMins / 1440)} days ago`;
    }
    
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(evt);
    }
    
    showError(title, error) {
        let message = 'Unknown error';
        if (error && error.body) {
            if (error.body.message) {
                message = error.body.message;
            } else if (error.body.pageErrors && error.body.pageErrors.length > 0) {
                message = error.body.pageErrors[0].message;
            }
        } else if (error && error.message) {
            message = error.message;
        }
        
        this.showToast(title, message, 'error');
    }
    
    // Getters for computed values
    get hasErrors() {
        return this.diagnosticsData && this.diagnosticsData.recentErrors && 
               this.diagnosticsData.recentErrors.length > 0;
    }
    
    get apiUsageClass() {
        if (!this.diagnosticsData || !this.diagnosticsData.systemLimits) return '';
        
        const percentage = this.diagnosticsData.systemLimits.apiCallsPercentage;
        if (percentage > 90) return 'slds-text-color_error';
        if (percentage > 70) return 'slds-text-color_warning';
        return 'slds-text-color_success';
    }
    
    get storageUsageClass() {
        if (!this.diagnosticsData || !this.diagnosticsData.systemLimits) return '';
        
        const percentage = this.diagnosticsData.systemLimits.storagePercentage;
        if (percentage > 90) return 'slds-text-color_error';
        if (percentage > 70) return 'slds-text-color_warning';
        return 'slds-text-color_success';
    }
    
    get platformEventsUsageClass() {
        if (!this.diagnosticsData || !this.diagnosticsData.systemLimits) return '';
        
        const percentage = this.diagnosticsData.systemLimits.platformEventsPercentage;
        if (percentage > 90) return 'slds-text-color_error';
        if (percentage > 70) return 'slds-text-color_warning';
        return 'slds-text-color_success';
    }
}