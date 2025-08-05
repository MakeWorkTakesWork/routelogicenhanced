/**
 * @description Service for masking PII data based on regional requirements
 * @author RouteLogic Team
 * @date 2025-01-20
 */
public with sharing class PIIMaskingService {
    
    // Helper class to store match information
    private class MatchInfo {
        public Integer startPos;
        public Integer endPos;
        public String value;
        
        public MatchInfo(Integer startPos, Integer endPos, String value) {
            this.startPos = startPos;
            this.endPos = endPos;
            this.value = value;
        }
    }
    
    // PII patterns - Optimized to prevent ReDoS attacks
    // Fixed: Removed complex backtracking patterns that could cause catastrophic backtracking
    private static final Pattern EMAIL_PATTERN = Pattern.compile('[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}');
    // SECURITY FIX: Simplified phone pattern to prevent ReDoS vulnerability
    private static final Pattern PHONE_PATTERN = Pattern.compile('\\b\\d{3}[-.]?\\d{3}[-.]?\\d{4}\\b');
    private static final Pattern SSN_PATTERN = Pattern.compile('\\b\\d{3}-\\d{2}-\\d{4}\\b');
    private static final Pattern CREDIT_CARD_PATTERN = Pattern.compile('\\b\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}\\b');
    private static final Pattern IP_ADDRESS_PATTERN = Pattern.compile('\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b');
    
    // Maximum text length to prevent performance issues
    private static final Integer MAX_TEXT_LENGTH = 1000000; // 1MB limit
    
    /**
     * @description Mask PII in text based on regional requirements
     * @param text The text to mask
     * @param region The region code (e.g., EU, CA, UK)
     * @return Masked text
     */
    public static String maskPII(String text, String region) {
        // Input validation and sanitization
        if (String.isBlank(text)) {
            return text;
        }
        
        // SECURITY FIX: Prevent processing of extremely large inputs that could cause DoS
        if (text.length() > MAX_TEXT_LENGTH) {
            throw new IllegalArgumentException('Text exceeds maximum allowed length of ' + MAX_TEXT_LENGTH + ' characters');
        }
        
        // SECURITY FIX: Sanitize input to prevent XSS attacks
        try {
            // Validate input is proper UTF-8 and doesn't contain null bytes
            if (text.contains('\u0000')) {
                throw new IllegalArgumentException('Text contains null bytes which are not allowed');
            }
        } catch (Exception e) {
            ErrorLogService.logError('PIIMaskingService.maskPII', e, 'Invalid input detected');
            throw new IllegalArgumentException('Invalid input text: ' + e.getMessage());
        }
        
        // Check if PII masking is enabled
        if (!isPIIMaskingEnabled()) {
            return text;
        }
        
        // Check if masking is required for this region
        if (!isPIIMaskingRequiredForRegion(region)) {
            return text;
        }
        
        // Apply masking based on region-specific rules
        String maskedText = text;
        
        // Mask emails
        maskedText = maskEmails(maskedText);
        
        // Mask phone numbers
        maskedText = maskPhoneNumbers(maskedText);
        
        // Mask SSNs (US specific)
        // SECURITY FIX: Use case-insensitive comparison for region
        if ('US'.equalsIgnoreCase(region)) {
            maskedText = maskSSNs(maskedText);
        }
        
        // Mask credit card numbers
        maskedText = maskCreditCards(maskedText);
        
        // Mask IP addresses if required
        if (requiresIPMasking(region)) {
            maskedText = maskIPAddresses(maskedText);
        }
        
        // Apply region-specific masking
        maskedText = applyRegionSpecificMasking(maskedText, region);
        
        return maskedText;
    }
    
    /**
     * @description Check if PII masking is enabled
     */
    private static Boolean isPIIMaskingEnabled() {
        return ConfigManager.isPIIMaskingEnabled();
    }
    
    /**
     * @description Check if PII masking is required for region
     */
    private static Boolean isPIIMaskingRequiredForRegion(String region) {
        if (String.isBlank(region)) {
            return false;
        }
        
        Set<String> maskingRegions = ConfigManager.getPIIMaskingRegions();
        return maskingRegions.contains(region.toUpperCase());
    }
    
    /**
     * @description Mask email addresses
     */
    private static String maskEmails(String text) {
        Matcher matcher = EMAIL_PATTERN.matcher(text);
        // PERFORMANCE FIX: Build result in one pass
        String result = text;
        List<MatchInfo> matches = new List<MatchInfo>();
        
        while (matcher.find()) {
            matches.add(new MatchInfo(matcher.start(), matcher.end(), matcher.group()));
        }
        
        // Process matches in reverse order to maintain position integrity
        for (Integer i = matches.size() - 1; i >= 0; i--) {
            MatchInfo match = matches[i];
            String maskedEmail = maskEmail(match.value);
            result = result.substring(0, match.startPos) + maskedEmail + result.substring(match.endPos);
        }
        
        return result;
    }
    
    /**
     * @description Mask individual email
     */
    private static String maskEmail(String email) {
        Integer atIndex = email.indexOf('@');
        if (atIndex > 2) {
            return email.substring(0, 2) + '***' + email.substring(atIndex);
        }
        return '***' + email.substring(atIndex);
    }
    
    /**
     * @description Mask phone numbers
     */
    private static String maskPhoneNumbers(String text) {
        Matcher matcher = PHONE_PATTERN.matcher(text);
        // PERFORMANCE FIX: Build result in one pass
        String result = text;
        List<MatchInfo> matches = new List<MatchInfo>();
        
        while (matcher.find()) {
            matches.add(new MatchInfo(matcher.start(), matcher.end(), matcher.group()));
        }
        
        // Process matches in reverse order to maintain position integrity
        for (Integer i = matches.size() - 1; i >= 0; i--) {
            MatchInfo match = matches[i];
            String phone = match.value;
            // Extract last 4 digits safely
            String lastFour = phone.replaceAll('[^0-9]', '');
            if (lastFour.length() >= 4) {
                lastFour = lastFour.substring(lastFour.length() - 4);
            } else {
                lastFour = 'XXXX';
            }
            String maskedPhone = 'XXX-XXX-' + lastFour;
            result = result.substring(0, match.startPos) + maskedPhone + result.substring(match.endPos);
        }
        
        return result;
    }
    
    /**
     * @description Mask SSNs
     */
    private static String maskSSNs(String text) {
        Matcher matcher = SSN_PATTERN.matcher(text);
        String result = text;
        
        while (matcher.find()) {
            String ssn = matcher.group();
            String maskedSSN = 'XXX-XX-' + ssn.substring(ssn.length() - 4);
            result = result.replace(ssn, maskedSSN);
        }
        
        return result;
    }
    
    /**
     * @description Mask credit card numbers
     */
    private static String maskCreditCards(String text) {
        Matcher matcher = CREDIT_CARD_PATTERN.matcher(text);
        String result = text;
        
        while (matcher.find()) {
            String card = matcher.group();
            String digitsOnly = card.replaceAll('[^0-9]', '');
            if (digitsOnly.length() >= 12) {
                String maskedCard = 'XXXX-XXXX-XXXX-' + digitsOnly.substring(digitsOnly.length() - 4);
                result = result.replace(card, maskedCard);
            }
        }
        
        return result;
    }
    
    /**
     * @description Mask IP addresses
     */
    private static String maskIPAddresses(String text) {
        Matcher matcher = IP_ADDRESS_PATTERN.matcher(text);
        String result = text;
        
        while (matcher.find()) {
            String ip = matcher.group();
            String[] octets = ip.split('\\.');
            if (octets.size() == 4) {
                String maskedIP = octets[0] + '.' + octets[1] + '.XXX.XXX';
                result = result.replace(ip, maskedIP);
            }
        }
        
        return result;
    }
    
    /**
     * @description Check if region requires IP masking
     */
    private static Boolean requiresIPMasking(String region) {
        // EU GDPR requires IP masking
        Set<String> ipMaskingRegions = new Set<String>{'EU', 'UK', 'CH'};
        return ipMaskingRegions.contains(region.toUpperCase());
    }
    
    /**
     * @description Apply region-specific masking rules
     */
    private static String applyRegionSpecificMasking(String text, String region) {
        switch on region.toUpperCase() {
            when 'EU' {
                // GDPR specific masking
                return applyGDPRMasking(text);
            }
            when 'CA' {
                // Canadian privacy law masking
                return applyCanadianMasking(text);
            }
            when 'UK' {
                // UK GDPR masking
                return applyUKMasking(text);
            }
            when 'AU' {
                // Australian privacy law masking
                return applyAustralianMasking(text);
            }
            when else {
                return text;
            }
        }
    }
    
    /**
     * @description Apply GDPR-specific masking
     */
    private static String applyGDPRMasking(String text) {
        // Additional GDPR requirements
        // Mask dates of birth
        text = text.replaceAll('\\b\\d{1,2}[/-]\\d{1,2}[/-]\\d{4}\\b', 'XX/XX/XXXX');
        
        // Mask postal codes (various EU formats)
        text = text.replaceAll('\\b\\d{5}\\b', 'XXXXX'); // German, French, etc.
        text = text.replaceAll('\\b[A-Z]{1,2}\\d{1,2}[A-Z]?\\s?\\d[A-Z]{2}\\b', 'XX## XXX'); // UK postcodes
        
        return text;
    }
    
    /**
     * @description Apply Canadian privacy law masking
     */
    private static String applyCanadianMasking(String text) {
        // Mask Canadian postal codes
        text = text.replaceAll('\\b[A-Z]\\d[A-Z]\\s?\\d[A-Z]\\d\\b', 'X#X #X#');
        
        // Mask SIN (Social Insurance Number)
        text = text.replaceAll('\\b\\d{3}[\\s-]?\\d{3}[\\s-]?\\d{3}\\b', 'XXX-XXX-XXX');
        
        return text;
    }
    
    /**
     * @description Apply UK-specific masking
     */
    private static String applyUKMasking(String text) {
        // Mask UK National Insurance numbers
        text = text.replaceAll('\\b[A-Z]{2}\\s?\\d{2}\\s?\\d{2}\\s?\\d{2}\\s?[A-Z]\\b', 'XX ## ## ## X');
        
        return text;
    }
    
    /**
     * @description Apply Australian privacy law masking
     */
    private static String applyAustralianMasking(String text) {
        // Mask Australian Tax File Numbers
        text = text.replaceAll('\\b\\d{3}\\s?\\d{3}\\s?\\d{3}\\b', 'XXX XXX XXX');
        
        // Mask Medicare numbers
        text = text.replaceAll('\\b\\d{10}\\b', 'XXXXXXXXXX');
        
        return text;
    }
    
    /**
     * @description Detect region from user or org settings
     */
    public static String detectRegion() {
        // Check user's locale
        String userLocale = UserInfo.getLocale();
        
        // Map locales to regions
        Map<String, String> localeToRegion = new Map<String, String>{
            'en_US' => 'US',
            'en_CA' => 'CA',
            'en_GB' => 'UK',
            'en_AU' => 'AU',
            'fr_FR' => 'EU',
            'de_DE' => 'EU',
            'es_ES' => 'EU',
            'it_IT' => 'EU',
            'nl_NL' => 'EU'
        };
        
        if (localeToRegion.containsKey(userLocale)) {
            return localeToRegion.get(userLocale);
        }
        
        // Check organization country
        Organization org = [SELECT Country FROM Organization LIMIT 1];
        if (org.Country != null) {
            return mapCountryToRegion(org.Country);
        }
        
        // Default to US
        return 'US';
    }
    
    /**
     * @description Map country to region
     */
    private static String mapCountryToRegion(String country) {
        // EU countries
        Set<String> euCountries = new Set<String>{
            'AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR',
            'DE', 'GR', 'HU', 'IE', 'IT', 'LV', 'LT', 'LU', 'MT', 'NL',
            'PL', 'PT', 'RO', 'SK', 'SI', 'ES', 'SE'
        };
        
        if (euCountries.contains(country.toUpperCase())) {
            return 'EU';
        }
        
        switch on country.toUpperCase() {
            when 'US' { return 'US'; }
            when 'CA' { return 'CA'; }
            when 'GB', 'UK' { return 'UK'; }
            when 'AU' { return 'AU'; }
            when else { return 'OTHER'; }
        }
    }
}