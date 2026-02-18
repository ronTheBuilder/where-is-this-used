@IsTest
private with sharing class ProcessFlowControllerTest {
    @IsTest
    static void getProcessFlow_returnsResponse() {
        ToolingApiClient.bypassAccessCheckForTests = true;
        Test.setMock(HttpCalloutMock.class, new ControllerMock());

        Test.startTest();
        ProcessFlowService.ProcessFlowResponse response = ProcessFlowController.getProcessFlow('Account', 'All');
        Test.stopTest();

        System.assertEquals('Account', response.objectName);
        System.assertEquals(12, response.phases.size());
        System.assert(response.totalAutomations > 0);
    }

    @IsTest
    static void getProcessFlow_wrapsServiceException() {
        ToolingApiClient.bypassAccessCheckForTests = true;

        try {
            ProcessFlowController.getProcessFlow('Account', 'Wrong');
            System.assert(false, 'Expected AuraHandledException for invalid context');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage().contains('Trigger context must be'));
        }
    }

    @IsTest
    static void getProcessFlow_wrapsUnexpectedException() {
        ToolingApiClient.bypassAccessCheckForTests = true;
        Test.setMock(HttpCalloutMock.class, new ErrorControllerMock());

        try {
            Test.startTest();
            ProcessFlowController.getProcessFlow('Account', 'All');
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage().contains('Tooling API request failed'));
        }
    }

    private class ControllerMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();
            if (endpoint.contains('/query/?q=')) {
                String soql = EncodingUtil.urlDecode(endpoint.substring(endpoint.indexOf('?q=') + 3), 'UTF-8');
                if (soql.contains('FROM ApexTrigger')) {
                    response.setBody('{"done":true,"totalSize":1,"records":[{"Id":"01qA","Name":"AccountTrigger","UsageBeforeInsert":true,"UsageAfterInsert":true,"UsageBeforeUpdate":false,"UsageAfterUpdate":false,"UsageBeforeDelete":false,"UsageAfterDelete":false,"UsageAfterUndelete":false,"Status":"Active"}]}');
                } else if (soql.contains('FROM ValidationRule')) {
                    response.setBody('{"done":true,"totalSize":0,"records":[]}');
                } else if (soql.contains('FROM FlowVersionView')) {
                    response.setBody('{"done":true,"totalSize":1,"records":[{"Id":"301A","Status":"Active","TriggerObjectOrEvent":"Account","TriggerType":"RecordBeforeSave","FlowDefinitionView":{"ApiName":"Account_Flow","Label":"Account Flow"}}]}');
                } else {
                    response.setBody('{"done":true,"totalSize":0,"records":[]}');
                }
                return response;
            }

            if (endpoint.contains('/sobjects/Flow/301A')) {
                response.setBody('{"Metadata":{"triggerType":"RecordBeforeSave","recordTriggerType":"CreateOnly"}}');
                return response;
            }

            response.setBody('{"done":true,"totalSize":0,"records":[]}');
            return response;
        }
    }

    private class ErrorControllerMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(500);
            response.setBody('{"message":"fail"}');
            return response;
        }
    }
}
