public with sharing class BlastRadiusController {
    @AuraEnabled
    public static BlastRadiusService.BlastRadiusResponse getBlastRadius(
        String metadataType,
        String componentName,
        Integer maxDepth
    ) {
        try {
            return BlastRadiusService.getBlastRadius(metadataType, componentName, maxDepth);
        } catch (BlastRadiusService.BlastRadiusServiceException ex) {
            AuraHandledException ahe = new AuraHandledException(ex.getMessage());

            ahe.setMessage(ex.getMessage());

            throw ahe;
        } catch (Exception ex) {
            AuraHandledException ahe = new AuraHandledException('Unexpected error while resolving blast radius: ' + ex.getMessage());

            ahe.setMessage('Unexpected error while resolving blast radius: ' + ex.getMessage());

            throw ahe;
        }
    }
}
