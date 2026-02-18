public with sharing class DependencyController {
    @AuraEnabled
    public static DependencyService.DependencySearchResponse searchDependencies(String metadataType, String componentName) {
        try {
            return DependencyService.searchDependencies(metadataType, componentName);
        } catch (DependencyService.DependencyServiceException ex) {
            AuraHandledException ahe = new AuraHandledException(ex.getMessage());

            ahe.setMessage(ex.getMessage());

            throw ahe;
        } catch (Exception ex) {
            AuraHandledException ahe = new AuraHandledException('Unexpected error while searching dependencies: ' + ex.getMessage());

            ahe.setMessage('Unexpected error while searching dependencies: ' + ex.getMessage());

            throw ahe;
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
            AuraHandledException ahe = new AuraHandledException(ex.getMessage());

            ahe.setMessage(ex.getMessage());

            throw ahe;
        } catch (Exception ex) {
            AuraHandledException ahe = new AuraHandledException('Unable to validate the Named Credential connection: ' + ex.getMessage());

            ahe.setMessage('Unable to validate the Named Credential connection: ' + ex.getMessage());

            throw ahe;
        }
    }
}
