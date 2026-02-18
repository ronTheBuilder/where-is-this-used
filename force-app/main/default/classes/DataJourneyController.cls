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
            AuraHandledException ahe = new AuraHandledException(ex.getMessage());

            ahe.setMessage(ex.getMessage());

            throw ahe;
        } catch (Exception ex) {
            AuraHandledException ahe = new AuraHandledException('Unexpected error while tracing data journey: ' + ex.getMessage());

            ahe.setMessage('Unexpected error while tracing data journey: ' + ex.getMessage());

            throw ahe;
        }
    }
}
