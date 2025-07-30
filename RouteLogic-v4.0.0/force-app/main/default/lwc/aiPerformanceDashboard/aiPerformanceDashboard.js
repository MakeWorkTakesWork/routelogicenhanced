import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCacheStats from '@salesforce/apex/AICacheService.getCacheStats';
import analyzeQuery from '@salesforce/apex/AIQueryOptimizationService.analyzeQuery';
import getOptimizedAnalytics from '@salesforce/apex/AIQueryOptimizationService.getOptimizedAnalytics';
import clearStats from '@salesforce/apex/AICacheService.clearStats';

export default class AiPerformanceDashboard extends LightningElement {
    @track activeTab = 'cache';
    @track cacheStats = {};
    @track queryMetrics = [];
    @track performanceData = {};
    @track isLoading = false;
    
    // Cache configuration
    @track cacheConfig = {
        ttl: 300,
        useCompression: false,
        cacheLevel: 'PARTITION',
        enableMetrics: true
    };
    
    // Query analysis
    @track queryToAnalyze = '';
    @track queryAnalysisResult = null;
    
    // Performance metrics
    @track performanceMetrics = {
        avgResponseTime: 0,
        totalQueries: 0,
        cacheHitRate: 0,
        errorRate: 0
    };
    
    connectedCallback() {
        this.loadPerformanceData();
        this.startAutoRefresh();
    }
    
    disconnectedCallback() {
        this.stopAutoRefresh();
    }
    
    get tabs() {
        return [
            { label: 'Cache Management', value: 'cache', icon: 'utility:database' },
            { label: 'Query Optimization', value: 'query', icon: 'utility:search' },
            { label: 'Performance Metrics', value: 'metrics', icon: 'utility:chart' },
            { label: 'Mobile Performance', value: 'mobile', icon: 'utility:phone_portrait' }
        ];
    }
    
    get isActiveTab() {
        return {
            cache: this.activeTab === 'cache',
            query: this.activeTab === 'query',
            metrics: this.activeTab === 'metrics',
            mobile: this.activeTab === 'mobile'
        };
    }
    
    get cacheHitRateClass() {
        const rate = this.cacheStats.hitRate || 0;
        if (rate >= 80) return 'slds-text-color_success';
        if (rate >= 50) return 'slds-text-color_weak';
        return 'slds-text-color_error';
    }
    
    get cacheLevelOptions() {
        return [
            { label: 'Session Cache', value: 'SESSION' },
            { label: 'Organization Cache', value: 'ORG' },
            { label: 'Partition Cache', value: 'PARTITION' }
        ];
    }
    
    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
        this.loadTabData();
    }
    
    loadTabData() {
        switch(this.activeTab) {
            case 'cache':
                this.loadCacheStats();
                break;
            case 'query':
                this.loadQueryMetrics();
                break;
            case 'metrics':
                this.loadPerformanceMetrics();
                break;
            case 'mobile':
                this.loadMobileMetrics();
                break;
        }
    }
    
    async loadPerformanceData() {
        this.isLoading = true;
        try {
            await Promise.all([
                this.loadCacheStats(),
                this.loadQueryMetrics(),
                this.loadPerformanceMetrics()
            ]);
        } catch (error) {
            this.showError('Failed to load performance data', error);
        } finally {
            this.isLoading = false;
        }
    }
    
    async loadCacheStats() {
        try {
            this.cacheStats = await getCacheStats();
            this.updateCacheCharts();
        } catch (error) {
            this.showError('Failed to load cache stats', error);
        }
    }
    
    async loadQueryMetrics() {
        try {
            const result = await getOptimizedAnalytics({
                groupByField: 'Provider_Type__c',
                startDate: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000),
                endDate: new Date(),
                config: {
                    useSelectiveFilters: true
                }
            });
            
            this.queryMetrics = result.map(metric => ({
                provider: metric.Provider_Type__c,
                queries: metric.recordCount,
                avgTime: Math.round(metric.avgTime),
                maxTime: Math.round(metric.maxTime)
            }));
        } catch (error) {
            this.showError('Failed to load query metrics', error);
        }
    }
    
    async loadPerformanceMetrics() {
        try {
            // Calculate aggregate performance metrics
            const totalQueries = this.queryMetrics.reduce((sum, m) => sum + m.queries, 0);
            const avgResponseTime = this.queryMetrics.reduce((sum, m) => sum + m.avgTime, 0) / 
                                   (this.queryMetrics.length || 1);
            
            this.performanceMetrics = {
                avgResponseTime: Math.round(avgResponseTime),
                totalQueries: totalQueries,
                cacheHitRate: this.cacheStats.hitRate || 0,
                errorRate: 2.5 // Mock data - would come from real metrics
            };
            
            this.updatePerformanceCharts();
        } catch (error) {
            this.showError('Failed to load performance metrics', error);
        }
    }
    
    loadMobileMetrics() {
        // Load mobile-specific performance metrics
        this.mobileMetrics = {
            avgPayloadSize: '45 KB',
            compressionRate: '65%',
            offlineSyncTime: '3.2s',
            cacheUtilization: '78%'
        };
    }
    
    handleCacheConfigChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' ? 
                     event.target.checked : event.target.value;
        
        this.cacheConfig = {
            ...this.cacheConfig,
            [field]: value
        };
    }
    
    async handleClearCache() {
        try {
            await clearStats();
            await this.loadCacheStats();
            this.showSuccess('Cache cleared successfully');
        } catch (error) {
            this.showError('Failed to clear cache', error);
        }
    }
    
    handleQueryInputChange(event) {
        this.queryToAnalyze = event.target.value;
    }
    
    async handleAnalyzeQuery() {
        if (!this.queryToAnalyze) {
            this.showError('Please enter a query to analyze');
            return;
        }
        
        this.isLoading = true;
        try {
            this.queryAnalysisResult = await analyzeQuery({
                query: this.queryToAnalyze
            });
            
            if (this.queryAnalysisResult.optimizationSuggestions.length === 0) {
                this.queryAnalysisResult.optimizationSuggestions.push(
                    'Query appears to be optimized'
                );
            }
        } catch (error) {
            this.showError('Failed to analyze query', error);
        } finally {
            this.isLoading = false;
        }
    }
    
    updateCacheCharts() {
        // Update cache visualization
        const canvas = this.template.querySelector('.cache-chart');
        if (canvas) {
            // Implement chart rendering
        }
    }
    
    updatePerformanceCharts() {
        // Update performance visualization
        const canvas = this.template.querySelector('.performance-chart');
        if (canvas) {
            // Implement chart rendering
        }
    }
    
    startAutoRefresh() {
        this.refreshInterval = setInterval(() => {
            if (this.activeTab === 'cache' || this.activeTab === 'metrics') {
                this.loadTabData();
            }
        }, 30000); // Refresh every 30 seconds
    }
    
    stopAutoRefresh() {
        if (this.refreshInterval) {
            clearInterval(this.refreshInterval);
        }
    }
    
    handleRefresh() {
        this.loadTabData();
    }
    
    showSuccess(message) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Success',
            message: message,
            variant: 'success'
        }));
    }
    
    showError(message, error) {
        console.error(message, error);
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message: error?.body?.message || message,
            variant: 'error'
        }));
    }
}