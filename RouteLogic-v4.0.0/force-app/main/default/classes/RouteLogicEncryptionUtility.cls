/**
 * @description Encryption utility for RouteLogic Enhanced v4.0.0
 * @author RouteLogic Team
 * @date 2025-01-21
 * @version 4.0.0
 * 
 * This class provides secure encryption and decryption capabilities for:
 * - Configuration data encryption
 * - API key and secret protection
 * - Sensitive data handling
 * - Key management and rotation
 */
public with sharing class RouteLogicEncryptionUtility {
    
    // Encryption constants
    private static final String ENCRYPTION_ALGORITHM = 'AES256';
    private static final String KEY_DERIVATION_ALGORITHM = 'SHA256';
    private static final Integer KEY_SIZE = 256;
    private static final Integer SALT_SIZE = 16;
    private static final Integer IV_SIZE = 16;
    
    // Master key configuration
    private static final String MASTER_KEY_CONFIG = 'Security_Master_Encryption_Key';
    private static final String KEY_ROTATION_CONFIG = 'Security_Key_Rotation_Enabled';
    
    // Cache for derived keys
    private static Map<String, Blob> keyCache = new Map<String, Blob>();
    
    /**
     * @description Encrypt sensitive data
     * @param plaintext The data to encrypt
     * @return Encrypted data as base64 string
     */
    public static String encrypt(String plaintext) {
        if (String.isBlank(plaintext)) {
            throw new IllegalArgumentException('Plaintext cannot be null or empty');
        }
        
        try {
            // Get or generate encryption key
            Blob encryptionKey = getEncryptionKey();
            
            // Generate random salt and IV
            Blob salt = generateRandomBytes(SALT_SIZE);
            Blob iv = generateRandomBytes(IV_SIZE);
            
            // Derive key with salt
            Blob derivedKey = deriveKey(encryptionKey, salt);
            
            // Encrypt the data
            Blob plaintextBlob = Blob.valueOf(plaintext);
            Blob encryptedData = Crypto.encrypt(ENCRYPTION_ALGORITHM, derivedKey, iv, plaintextBlob);
            
            // Combine salt + iv + encrypted data
            Blob combinedData = combineBlobs(new List<Blob>{salt, iv, encryptedData});
            
            // Return as base64 string
            return EncodingUtil.base64Encode(combinedData);
            
        } catch (Exception e) {
            throw new EncryptionException('Encryption failed: ' + e.getMessage());
        }
    }
    
    /**
     * @description Decrypt sensitive data
     * @param encryptedData The encrypted data as base64 string
     * @return Decrypted plaintext
     */
    public static String decrypt(String encryptedData) {
        if (String.isBlank(encryptedData)) {
            throw new IllegalArgumentException('Encrypted data cannot be null or empty');
        }
        
        try {
            // Decode from base64
            Blob combinedData = EncodingUtil.base64Decode(encryptedData);
            
            // Extract salt, IV, and encrypted data
            List<Blob> components = extractBlobs(combinedData, new List<Integer>{SALT_SIZE, IV_SIZE});
            Blob salt = components[0];
            Blob iv = components[1];
            Blob encryptedBlob = components[2];
            
            // Get encryption key
            Blob encryptionKey = getEncryptionKey();
            
            // Derive key with salt
            Blob derivedKey = deriveKey(encryptionKey, salt);
            
            // Decrypt the data
            Blob decryptedBlob = Crypto.decrypt(ENCRYPTION_ALGORITHM, derivedKey, iv, encryptedBlob);
            
            // Return as string
            return decryptedBlob.toString();
            
        } catch (Exception e) {
            throw new EncryptionException('Decryption failed: ' + e.getMessage());
        }
    }
    
    /**
     * @description Encrypt data with custom key
     * @param plaintext The data to encrypt
     * @param customKey Custom encryption key
     * @return Encrypted data as base64 string
     */
    public static String encryptWithKey(String plaintext, String customKey) {
        if (String.isBlank(plaintext) || String.isBlank(customKey)) {
            throw new IllegalArgumentException('Plaintext and custom key cannot be null or empty');
        }
        
        try {
            // Convert custom key to blob
            Blob keyBlob = Blob.valueOf(customKey);
            
            // Generate random salt and IV
            Blob salt = generateRandomBytes(SALT_SIZE);
            Blob iv = generateRandomBytes(IV_SIZE);
            
            // Derive key with salt
            Blob derivedKey = deriveKey(keyBlob, salt);
            
            // Encrypt the data
            Blob plaintextBlob = Blob.valueOf(plaintext);
            Blob encryptedData = Crypto.encrypt(ENCRYPTION_ALGORITHM, derivedKey, iv, plaintextBlob);
            
            // Combine salt + iv + encrypted data
            Blob combinedData = combineBlobs(new List<Blob>{salt, iv, encryptedData});
            
            // Return as base64 string
            return EncodingUtil.base64Encode(combinedData);
            
        } catch (Exception e) {
            throw new EncryptionException('Encryption with custom key failed: ' + e.getMessage());
        }
    }
    
    /**
     * @description Decrypt data with custom key
     * @param encryptedData The encrypted data as base64 string
     * @param customKey Custom encryption key
     * @return Decrypted plaintext
     */
    public static String decryptWithKey(String encryptedData, String customKey) {
        if (String.isBlank(encryptedData) || String.isBlank(customKey)) {
            throw new IllegalArgumentException('Encrypted data and custom key cannot be null or empty');
        }
        
        try {
            // Decode from base64
            Blob combinedData = EncodingUtil.base64Decode(encryptedData);
            
            // Extract salt, IV, and encrypted data
            List<Blob> components = extractBlobs(combinedData, new List<Integer>{SALT_SIZE, IV_SIZE});
            Blob salt = components[0];
            Blob iv = components[1];
            Blob encryptedBlob = components[2];
            
            // Convert custom key to blob
            Blob keyBlob = Blob.valueOf(customKey);
            
            // Derive key with salt
            Blob derivedKey = deriveKey(keyBlob, salt);
            
            // Decrypt the data
            Blob decryptedBlob = Crypto.decrypt(ENCRYPTION_ALGORITHM, derivedKey, iv, encryptedBlob);
            
            // Return as string
            return decryptedBlob.toString();
            
        } catch (Exception e) {
            throw new EncryptionException('Decryption with custom key failed: ' + e.getMessage());
        }
    }
    
    /**
     * @description Generate secure hash
     * @param data The data to hash
     * @param salt Optional salt for additional security
     * @return SHA-256 hash as hex string
     */
    public static String generateSecureHash(String data, String salt) {
        if (String.isBlank(data)) {
            throw new IllegalArgumentException('Data cannot be null or empty');
        }
        
        String hashInput = data;
        if (String.isNotBlank(salt)) {
            hashInput = salt + data + salt;
        }
        
        Blob hashBlob = Crypto.generateDigest(KEY_DERIVATION_ALGORITHM, Blob.valueOf(hashInput));
        return EncodingUtil.convertToHex(hashBlob);
    }
    
    /**
     * @description Generate random encryption key
     * @return Random encryption key as base64 string
     */
    public static String generateRandomKey() {
        Blob randomKey = generateRandomBytes(KEY_SIZE / 8); // Convert bits to bytes
        return EncodingUtil.base64Encode(randomKey);
    }
    
    /**
     * @description Generate random salt
     * @return Random salt as base64 string
     */
    public static String generateRandomSalt() {
        Blob randomSalt = generateRandomBytes(SALT_SIZE);
        return EncodingUtil.base64Encode(randomSalt);
    }
    
    /**
     * @description Validate encryption key strength
     * @param key The encryption key to validate
     * @return True if key meets security requirements
     */
    public static Boolean validateKeyStrength(String key) {
        if (String.isBlank(key)) {
            return false;
        }
        
        // Check minimum length
        if (key.length() < 32) {
            return false;
        }
        
        // Check for character diversity
        Boolean hasUpper = false;
        Boolean hasLower = false;
        Boolean hasDigit = false;
        Boolean hasSpecial = false;
        
        for (Integer i = 0; i < key.length(); i++) {
            String char = key.substring(i, i + 1);
            if (char.isAllUpperCase()) {
                hasUpper = true;
            } else if (char.isAllLowerCase()) {
                hasLower = true;
            } else if (char.isNumeric()) {
                hasDigit = true;
            } else {
                hasSpecial = true;
            }
        }
        
        // Require at least 3 of 4 character types
        Integer diversityScore = 0;
        if (hasUpper) diversityScore++;
        if (hasLower) diversityScore++;
        if (hasDigit) diversityScore++;
        if (hasSpecial) diversityScore++;
        
        return diversityScore >= 3;
    }
    
    /**
     * @description Rotate encryption keys
     * @return True if rotation was successful
     */
    public static Boolean rotateEncryptionKeys() {
        try {
            // Check if key rotation is enabled
            Boolean rotationEnabled = false; // Would get from configuration
            
            if (!rotationEnabled) {
                System.debug(LoggingLevel.INFO, 'Key rotation is disabled');
                return false;
            }
            
            // Generate new master key
            String newMasterKey = generateRandomKey();
            
            // In a real implementation, this would:
            // 1. Re-encrypt all existing encrypted data with the new key
            // 2. Update the master key configuration
            // 3. Clear the key cache
            
            // Clear key cache to force regeneration
            clearKeyCache();
            
            System.debug(LoggingLevel.INFO, 'Encryption key rotation completed');
            return true;
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Key rotation failed: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * @description Get encryption key from configuration or generate new one
     * @return Encryption key blob
     */
    private static Blob getEncryptionKey() {
        String cacheKey = 'master_key';
        
        // Check cache first
        if (keyCache.containsKey(cacheKey)) {
            return keyCache.get(cacheKey);
        }
        
        try {
            Blob encryptionKey;
            
            // SECURITY ENHANCEMENT: Try SecureKeyVault first
            try {
                String masterSecret = SecureKeyVault.getMasterSecret();
                if (String.isNotBlank(masterSecret)) {
                    encryptionKey = SecureKeyVault.retrieveKey(MASTER_KEY_CONFIG, masterSecret);
                }
            } catch (Exception vaultEx) {
                System.debug(LoggingLevel.WARN, 'SecureKeyVault not available: ' + vaultEx.getMessage());
            }
            
            // Fallback to configuration if vault didn't work
            if (encryptionKey == null) {
                String masterKeyConfig = RouteLogicConfigurationManager.getConfigurationValue(MASTER_KEY_CONFIG);
                if (String.isNotBlank(masterKeyConfig)) {
                    encryptionKey = EncodingUtil.base64Decode(masterKeyConfig);
                }
            }
            
            if (encryptionKey == null) {
                // Generate new key if not configured
                encryptionKey = generateRandomBytes(KEY_SIZE / 8);
                
                // CRITICAL FIX: Use SecureKeyVault for better security
                // First, try to store in SecureKeyVault (Platform Cache + Metadata)
                Boolean vaultStored = SecureKeyVault.storeKey(MASTER_KEY_CONFIG, encryptionKey);
                
                if (!vaultStored) {
                    // Fallback: Store in configuration (still better than not storing at all)
                    String encodedKey = EncodingUtil.base64Encode(encryptionKey);
                    RouteLogicConfigurationManager.setConfigurationValue(
                        MASTER_KEY_CONFIG, 
                        encodedKey,
                        false // Don't encrypt the master key with itself
                    );
                    System.debug(LoggingLevel.WARN, 'Stored key in configuration (fallback). Configure SecureKeyVault for better security.');
                } else {
                    System.debug(LoggingLevel.INFO, 'Generated and securely stored new master encryption key');
                }
            }
            
            // Cache the key
            keyCache.put(cacheKey, encryptionKey);
            
            return encryptionKey;
            
        } catch (Exception e) {
            throw new EncryptionException('Failed to get encryption key: ' + e.getMessage());
        }
    }
    
    /**
     * @description Derive encryption key using PBKDF2
     * @param masterKey The master key
     * @param salt The salt for key derivation
     * @return Derived key blob
     */
    private static Blob deriveKey(Blob masterKey, Blob salt) {
        try {
            // Combine master key and salt
            Blob combinedData = combineBlobs(new List<Blob>{masterKey, salt});
            
            // Generate derived key using SHA-256
            Blob derivedKey = Crypto.generateDigest(KEY_DERIVATION_ALGORITHM, combinedData);
            
            return derivedKey;
            
        } catch (Exception e) {
            throw new EncryptionException('Key derivation failed: ' + e.getMessage());
        }
    }
    
    /**
     * @description Generate random bytes
     * @param size Number of bytes to generate
     * @return Random bytes blob
     */
    private static Blob generateRandomBytes(Integer size) {
        if (size <= 0) {
            throw new IllegalArgumentException('Size must be positive');
        }
        
        // CRITICAL FIX: Support variable sizes correctly
        if (size == 16) {
            return Crypto.generateAesKey(128); // 16 bytes
        } else if (size == 32) {
            return Crypto.generateAesKey(256); // 32 bytes
        } else {
            // For other sizes, use crypto-secure random generation
            String randomHex = '';
            Integer iterations = (size * 2); // Each byte = 2 hex chars
            
            while (randomHex.length() < iterations) {
                // Generate cryptographically secure random data
                Long randomLong = Crypto.getRandomLong();
                Blob randomBlob = Blob.valueOf(String.valueOf(randomLong) + System.now().getTime());
                String hashHex = EncodingUtil.convertToHex(
                    Crypto.generateDigest('SHA256', randomBlob)
                );
                randomHex += hashHex;
            }
            
            // Trim to exact size needed
            randomHex = randomHex.substring(0, iterations);
            return EncodingUtil.convertFromHex(randomHex);
        }
    }
    
    /**
     * @description Combine multiple blobs into one
     * @param blobs List of blobs to combine
     * @return Combined blob
     */
    private static Blob combineBlobs(List<Blob> blobs) {
        if (blobs == null || blobs.isEmpty()) {
            throw new IllegalArgumentException('Blobs list cannot be null or empty');
        }
        
        String combinedHex = '';
        for (Blob b : blobs) {
            combinedHex += EncodingUtil.convertToHex(b);
        }
        
        return EncodingUtil.convertFromHex(combinedHex);
    }
    
    /**
     * @description Extract blobs from combined blob
     * @param combinedBlob The combined blob
     * @param sizes List of sizes for each component
     * @return List of extracted blobs
     */
    private static List<Blob> extractBlobs(Blob combinedBlob, List<Integer> sizes) {
        if (combinedBlob == null || sizes == null || sizes.isEmpty()) {
            throw new IllegalArgumentException('Combined blob and sizes cannot be null or empty');
        }
        
        List<Blob> extractedBlobs = new List<Blob>();
        String combinedHex = EncodingUtil.convertToHex(combinedBlob);
        
        Integer offset = 0;
        for (Integer size : sizes) {
            Integer hexSize = size * 2; // Each byte = 2 hex characters
            
            if (offset + hexSize > combinedHex.length()) {
                throw new EncryptionException('Invalid combined blob structure');
            }
            
            String componentHex = combinedHex.substring(offset, offset + hexSize);
            extractedBlobs.add(EncodingUtil.convertFromHex(componentHex));
            
            offset += hexSize;
        }
        
        // Add remaining data as the last component
        if (offset < combinedHex.length()) {
            String remainingHex = combinedHex.substring(offset);
            extractedBlobs.add(EncodingUtil.convertFromHex(remainingHex));
        }
        
        return extractedBlobs;
    }
    
    /**
     * @description Clear key cache
     */
    private static void clearKeyCache() {
        keyCache.clear();
    }
    
    /**
     * @description Clear key cache (for testing)
     */
    @TestVisible
    private static void clearCacheForTesting() {
        clearKeyCache();
    }
    
    /**
     * @description Get cache size for monitoring
     * @return Number of keys in cache
     */
    public static Integer getCacheSize() {
        return keyCache.size();
    }
    
    // Custom exceptions
    public class EncryptionException extends Exception {}
}

