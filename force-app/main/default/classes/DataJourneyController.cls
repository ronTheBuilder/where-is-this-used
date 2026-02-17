public with sharing class DataJourneyController {
    @AuraEnabled
    public static DataJourneyService.DataJourneyResponse traceDataJourney(
        String objectName,
        String fieldName,
        Integer maxDepth
    ) {
        try {
            return DataJourneyService.traceDataJourney(objectName, fieldName, maxDepth);
        } catch (DataJourneyService.DataJourneyServiceException ex) {
            throw new AuraHandledException(ex.getMessage());
        } catch (Exception ex) {
            throw new AuraHandledException('Unexpected error while tracing data journey: ' + ex.getMessage());
        }
    }
}
