public with sharing class ProcessFlowController {
    @AuraEnabled
    public static ProcessFlowService.ProcessFlowResponse getProcessFlow(String objectName, String triggerContext) {
        try {
            return ProcessFlowService.getProcessFlow(objectName, triggerContext);
        } catch (ProcessFlowService.ProcessFlowServiceException ex) {
            AuraHandledException ahe = new AuraHandledException(ex.getMessage());

            ahe.setMessage(ex.getMessage());

            throw ahe;
        } catch (Exception ex) {
            AuraHandledException ahe = new AuraHandledException('Unexpected error while building process flow map: ' + ex.getMessage());

            ahe.setMessage('Unexpected error while building process flow map: ' + ex.getMessage());

            throw ahe;
        }
    }
}
