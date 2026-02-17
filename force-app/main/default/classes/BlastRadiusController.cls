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
            throw new AuraHandledException(ex.getMessage());
        } catch (Exception ex) {
            throw new AuraHandledException('Unexpected error while resolving blast radius: ' + ex.getMessage());
        }
    }
}
