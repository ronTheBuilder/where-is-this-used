public with sharing class ProcessFlowController {
    @AuraEnabled
    public static ProcessFlowService.ProcessFlowResponse getProcessFlow(String objectName, String triggerContext) {
        try {
            return ProcessFlowService.getProcessFlow(objectName, triggerContext);
        } catch (ProcessFlowService.ProcessFlowServiceException ex) {
            throw new AuraHandledException(ex.getMessage());
        } catch (Exception ex) {
            throw new AuraHandledException('Unexpected error while building process flow map: ' + ex.getMessage());
        }
    }
}
