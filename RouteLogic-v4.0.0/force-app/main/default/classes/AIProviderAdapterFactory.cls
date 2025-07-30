/**
 * @description Factory class for creating AI provider adapters
 * @author RouteLogic Team
 * @date 2025-01-21
 * @version 2.0
 * 
 * This factory implements the adapter pattern to provide clean separation
 * between the core routing engine and provider-specific implementations.
 */
public with sharing class AIProviderAdapterFactory {
    
    private static final Map<String, Type> ADAPTER_REGISTRY = new Map<String, Type>{
        'Ada' => AdaAdapter.class,
        'Intercom' => IntercomAdapter.class
    };
    
    /**
     * @description Get adapter instance for specified provider
     * @param providerName The AI provider name
     * @return IAIProviderAdapter implementation
     */
    public static IAIProviderAdapter getAdapter(String providerName) {
        if (String.isBlank(providerName)) {
            throw new IllegalArgumentException('Provider name cannot be null or empty');
        }
        
        Type adapterType = ADAPTER_REGISTRY.get(providerName);
        if (adapterType == null) {
            throw new UnsupportedProviderException('No adapter found for provider: ' + providerName);
        }
        
        try {
            return (IAIProviderAdapter) adapterType.newInstance();
        } catch (Exception e) {
            throw new AdapterInstantiationException('Failed to create adapter for ' + providerName + ': ' + e.getMessage());
        }
    }
    
    /**
     * @description Register a new adapter for a provider
     * @param providerName The provider name
     * @param adapterType The adapter class type
     */
    public static void registerAdapter(String providerName, Type adapterType) {
        if (String.isBlank(providerName)) {
            throw new IllegalArgumentException('Provider name cannot be null or empty');
        }
        
        if (adapterType == null) {
            throw new IllegalArgumentException('Adapter type cannot be null');
        }
        
        ADAPTER_REGISTRY.put(providerName, adapterType);
    }
    
    /**
     * @description Get list of supported providers
     * @return Set of supported provider names
     */
    public static Set<String> getSupportedProviders() {
        return ADAPTER_REGISTRY.keySet();
    }
    
    /**
     * @description Check if provider is supported
     * @param providerName The provider name to check
     * @return True if provider is supported
     */
    public static Boolean isProviderSupported(String providerName) {
        return ADAPTER_REGISTRY.containsKey(providerName);
    }
    
    // Custom exceptions
    
    public class UnsupportedProviderException extends Exception {}
    public class AdapterInstantiationException extends Exception {}
}

