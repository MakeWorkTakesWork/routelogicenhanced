import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getHandoffMetrics from '@salesforce/apex/RoutingLedgerTriggerHandler.getHandoffSuccessMetrics';
import getBlackHoleCases from '@salesforce/apex/RoutingLedgerTriggerHandler.getBlackHoleCases';

export default class AiHandoffEscalationAnalytics extends LightningElement {
    @track handoffMetrics;
    @track blackHoleCases;
    @track isLoading = true;
    @track error;
    @track errorMessage;
    @track selectedTimeframe = '24';
    @track selectedView = 'overview';
    
    wiredMetricsResult;
    wiredBlackHoleResult;
    refreshInterval;
    
    // Chart data
    @track handoffSuccessChartData;
    @track timeToRouteChartData;
    @track providerPerformanceData;
    @track escalationTrendData;
    
    get timeframeOptions() {
        return [
            { label: 'Last 24 Hours', value: '24' },
            { label: 'Last 7 Days', value: '168' },
            { label: 'Last 30 Days', value: '720' },
            { label: 'Last 90 Days', value: '2160' }
        ];
    }
    
    get viewOptions() {
        return [
            { label: 'Handoff Overview', value: 'overview' },
            { label: 'Success Rate Trends', value: 'success' },
            { label: 'Time-to-Route Analysis', value: 'timing' },
            { label: 'Black Hole Cases', value: 'blackhole' },
            { label: 'Provider Performance', value: 'providers' },
            { label: 'Escalation Patterns', value: 'escalation' }
        ];
    }
    
    get isOverviewView() {
        return this.selectedView === 'overview';
    }
    
    get isSuccessView() {
        return this.selectedView === 'success';
    }
    
    get isTimingView() {
        return this.selectedView === 'timing';
    }
    
    get isBlackHoleView() {
        return this.selectedView === 'blackhole';
    }
    
    get isProvidersView() {
        return this.selectedView === 'providers';
    }
    
    get isEscalationView() {
        return this.selectedView === 'escalation';
    }
    
    get successRateClass() {
        if (!this.handoffMetrics || !this.handoffMetrics.successRate) return 'metric-neutral';
        const rate = this.handoffMetrics.successRate;
        if (rate >= 95) return 'metric-excellent';
        if (rate >= 85) return 'metric-good';
        if (rate >= 70) return 'metric-warning';
        return 'metric-critical';
    }
    
    get blackHoleRateClass() {
        if (!this.handoffMetrics || !this.handoffMetrics.blackHoleHandoffs) return 'metric-neutral';
        const total = this.handoffMetrics.totalHandoffs;
        const blackHoles = this.handoffMetrics.blackHoleHandoffs;
        const rate = total > 0 ? (blackHoles / total) * 100 : 0;
        
        if (rate === 0) return 'metric-excellent';
        if (rate <= 2) return 'metric-good';
        if (rate <= 5) return 'metric-warning';
        return 'metric-critical';
    }
    
    @wire(getHandoffMetrics, { hoursBack: '$selectedTimeframe' })
    wiredHandoffMetrics(result) {
        this.wiredMetricsResult = result;
        if (result.data) {
            this.handoffMetrics = result.data;
            this.buildHandoffSuccessChart();
            this.error = undefined;
            this.errorMessage = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.errorMessage = this.sanitizeErrorMessage(result.error);
            this.handoffMetrics = undefined;
        }
        this.isLoading = false;
    }
    
    @wire(getBlackHoleCases, { hoursBack: '$selectedTimeframe' })
    wiredBlackHoleCases(result) {
        this.wiredBlackHoleResult = result;
        if (result.data) {
            this.blackHoleCases = result.data;
            this.error = undefined;
            this.errorMessage = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.errorMessage = this.sanitizeErrorMessage(result.error);
            this.blackHoleCases = undefined;
        }
    }
    
    connectedCallback() {
        // Auto-refresh every 30 seconds
        this.refreshInterval = setInterval(() => {
            this.refreshData();
        }, 30000);
    }
    
    disconnectedCallback() {
        if (this.refreshInterval) {
            clearInterval(this.refreshInterval);
        }
    }
    
    handleTimeframeChange(event) {
        this.selectedTimeframe = event.detail.value;
        this.isLoading = true;
    }
    
    handleViewChange(event) {
        this.selectedView = event.detail.value;
    }
    
    refreshData() {
        this.isLoading = true;
        return Promise.all([
            refreshApex(this.wiredMetricsResult),
            refreshApex(this.wiredBlackHoleResult)
        ]).then(() => {
            this.isLoading = false;
            this.showToast('Success', 'Dashboard refreshed', 'success');
        }).catch(error => {
            this.isLoading = false;
            this.showToast('Error', 'Failed to refresh dashboard: ' + error.body.message, 'error');
        });
    }
    
    buildHandoffSuccessChart() {
        if (!this.handoffMetrics) return;
        
        const metrics = this.handoffMetrics;
        this.handoffSuccessChartData = {
            labels: ['Successful', 'Failed', 'Black Hole'],
            datasets: [{
                data: [
                    metrics.successfulHandoffs || 0,
                    metrics.failedHandoffs || 0,
                    metrics.blackHoleHandoffs || 0
                ],
                backgroundColor: [
                    '#4CAF50', // Green for success
                    '#FF9800', // Orange for failed
                    '#F44336'  // Red for black hole
                ],
                borderWidth: 2,
                borderColor: '#ffffff'
            }]
        };
    }
    
    handleExportData() {
        // Export handoff analytics data
        if (!this.handoffMetrics) {
            this.showToast('Warning', 'No data available to export', 'warning');
            return;
        }
        
        const exportData = {
            timeframe: this.selectedTimeframe + ' hours',
            exportTime: new Date().toISOString(),
            metrics: this.handoffMetrics,
            blackHoleCases: this.blackHoleCases
        };
        
        const dataStr = JSON.stringify(exportData, null, 2);
        const dataBlob = new Blob([dataStr], { type: 'application/json' });
        const url = URL.createObjectURL(dataBlob);
        
        const link = document.createElement('a');
        link.href = url;
        link.download = `handoff-analytics-${new Date().toISOString().split('T')[0]}.json`;
        link.click();
        
        URL.revokeObjectURL(url);
        this.showToast('Success', 'Analytics data exported', 'success');
    }
    
    handleDrillDown(event) {
        const caseId = event.target.dataset.caseId;
        if (caseId) {
            // Navigate to case record or show detailed handoff timeline
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: caseId,
                    objectApiName: 'Case',
                    actionName: 'view'
                }
            });
        }
    }
    
    get formattedSuccessRate() {
        return this.handoffMetrics?.successRate ? 
               this.handoffMetrics.successRate.toFixed(1) + '%' : '0%';
    }
    
    get formattedFailureRate() {
        return this.handoffMetrics?.failureRate ? 
               this.handoffMetrics.failureRate.toFixed(1) + '%' : '0%';
    }
    
    get averageTimeToRoute() {
        // This would be calculated from routing ledger timestamps
        // For now, return a placeholder
        return '2.3 min';
    }
    
    get criticalBottlenecks() {
        // Identify bottlenecks in the handoff process
        const bottlenecks = [];
        
        if (this.handoffMetrics?.blackHoleHandoffs > 0) {
            bottlenecks.push({
                type: 'Black Hole Cases',
                count: this.handoffMetrics.blackHoleHandoffs,
                severity: 'critical'
            });
        }
        
        if (this.handoffMetrics?.failedHandoffs > 0) {
            bottlenecks.push({
                type: 'Failed Handoffs',
                count: this.handoffMetrics.failedHandoffs,
                severity: 'warning'
            });
        }
        
        return bottlenecks;
    }
    
    get hasBottlenecks() {
        return this.criticalBottlenecks.length > 0;
    }
    
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(evt);
    }
    
    /**
     * Sanitize error message to prevent XSS attacks
     * @param {Object} error - The error object from Apex
     * @returns {String} - Sanitized error message
     */
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

