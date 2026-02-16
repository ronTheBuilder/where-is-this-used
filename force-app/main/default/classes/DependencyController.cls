public with sharing class DependencyController {
    @AuraEnabled
    public static DependencyService.DependencySearchResponse searchDependencies(String metadataType, String componentName) {
        try {
            return DependencyService.searchDependencies(metadataType, componentName);
        } catch (DependencyService.DependencyServiceException ex) {
            throw new AuraHandledException(ex.getMessage());
        } catch (Exception ex) {
            throw new AuraHandledException('Unexpected error while searching dependencies: ' + ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getMetadataTypes() {
        return DependencyService.getSupportedMetadataTypes();
    }

    @AuraEnabled
    public static Boolean testConnection() {
        try {
            return DependencyService.testConnection();
        } catch (DependencyService.DependencyServiceException ex) {
            throw new AuraHandledException(ex.getMessage());
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to validate the Named Credential connection: ' + ex.getMessage());
        }
    }
}
