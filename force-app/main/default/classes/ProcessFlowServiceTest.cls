@IsTest
private with sharing class ProcessFlowServiceTest {
    @IsTest
    static void getProcessFlow_returnsMultiplePhases() {
        ToolingApiClient.bypassAccessCheckForTests = true;
        Test.setMock(HttpCalloutMock.class, new ProcessFlowMock());

        Test.startTest();
        ProcessFlowService.ProcessFlowResponse response = ProcessFlowService.getProcessFlow('Account', 'All');
        Test.stopTest();

        System.assertEquals('Account', response.objectName);
        System.assertEquals('All', response.triggerContext);
        System.assertEquals(12, response.phases.size());
        System.assert(response.totalAutomations > 0);

        ProcessFlowService.AutomationPhase beforeTriggers = response.phases[1];
        ProcessFlowService.AutomationPhase validationRules = response.phases[2];
        ProcessFlowService.AutomationPhase afterTriggers = response.phases[3];
        ProcessFlowService.AutomationPhase beforeFlows = response.phases[6];
        ProcessFlowService.AutomationPhase afterFlows = response.phases[9];
        ProcessFlowService.AutomationPhase asyncFlows = response.phases[11];

        System.assertEquals(2, beforeTriggers.phaseNumber);
        System.assertEquals(1, beforeTriggers.steps.size());
        System.assertEquals('BeforeTrigger', beforeTriggers.steps[0].automationType);

        System.assertEquals(3, validationRules.phaseNumber);
        System.assertEquals(1, validationRules.steps.size());
        System.assertEquals('ValidationRule', validationRules.steps[0].automationType);

        System.assertEquals(4, afterTriggers.phaseNumber);
        System.assertEquals(1, afterTriggers.steps.size());
        System.assertEquals('AfterTrigger', afterTriggers.steps[0].automationType);

        System.assertEquals(7, beforeFlows.phaseNumber);
        System.assertEquals(1, beforeFlows.steps.size());
        System.assertEquals('Flow_BeforeSave', beforeFlows.steps[0].automationType);

        System.assertEquals(10, afterFlows.phaseNumber);
        System.assertEquals(1, afterFlows.steps.size());
        System.assertEquals('Flow_AfterSave', afterFlows.steps[0].automationType);

        System.assertEquals(12, asyncFlows.phaseNumber);
        System.assertEquals(1, asyncFlows.steps.size());
        System.assertEquals('Flow_Async', asyncFlows.steps[0].automationType);
    }

    @IsTest
    static void getProcessFlow_deleteContext_filtersNonDeleteAutomations() {
        ToolingApiClient.bypassAccessCheckForTests = true;
        Test.setMock(HttpCalloutMock.class, new ProcessFlowMock());

        Test.startTest();
        ProcessFlowService.ProcessFlowResponse response = ProcessFlowService.getProcessFlow('Account', 'Delete');
        Test.stopTest();

        System.assertEquals('Delete', response.triggerContext);
        System.assertEquals(0, response.phases[2].steps.size());
        System.assertEquals(0, response.phases[6].steps.size());
        System.assertEquals(0, response.phases[9].steps.size());
        System.assertEquals(0, response.phases[11].steps.size());

        System.assertEquals(1, response.phases[1].steps.size());
        System.assertEquals(1, response.phases[3].steps.size());
        System.assert(response.totalAutomations >= 2);
    }

    @IsTest
    static void getProcessFlow_emptyObjectReturnsNoAutomations() {
        ToolingApiClient.bypassAccessCheckForTests = true;
        Test.setMock(HttpCalloutMock.class, new EmptyObjectMock());

        Test.startTest();
        ProcessFlowService.ProcessFlowResponse response = ProcessFlowService.getProcessFlow('Contact', 'All');
        Test.stopTest();

        System.assertEquals('Contact', response.objectName);
        System.assertEquals(12, response.phases.size());
        System.assertEquals(0, response.totalAutomations);
        for (ProcessFlowService.AutomationPhase phase : response.phases) {
            System.assertEquals(0, phase.steps.size());
        }
    }

    @IsTest
    static void getProcessFlow_throwsForInvalidInput() {
        ToolingApiClient.bypassAccessCheckForTests = true;

        try {
            ProcessFlowService.getProcessFlow('Account;DROP', 'All');
            System.assert(false, 'Expected invalid object name exception');
        } catch (ProcessFlowService.ProcessFlowServiceException ex) {
            System.assert(ex.getMessage().contains('invalid characters'));
        }

        try {
            ProcessFlowService.getProcessFlow('Account', 'Merge');
            System.assert(false, 'Expected invalid trigger context exception');
        } catch (ProcessFlowService.ProcessFlowServiceException ex) {
            System.assert(ex.getMessage().contains('Trigger context must be'));
        }
    }

    @IsTest
    static void getProcessFlow_throwsForToolingError() {
        ToolingApiClient.bypassAccessCheckForTests = true;
        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        try {
            Test.startTest();
            ProcessFlowService.getProcessFlow('Account', 'All');
            Test.stopTest();
            System.assert(false, 'Expected tooling exception');
        } catch (ProcessFlowService.ProcessFlowServiceException ex) {
            System.assert(ex.getMessage().contains('Tooling API request failed'));
        }
    }

    private class ProcessFlowMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();
            if (endpoint.contains('/query/?q=')) {
                String soql = decodeSoql(endpoint);
                response.setBody(buildQueryResponse(soql));
                return response;
            }

            if (endpoint.contains('/sobjects/Flow/301B')) {
                response.setBody('{"Metadata":{"triggerType":"RecordBeforeSave","recordTriggerType":"CreateAndUpdate","description":"Before flow"}}');
                return response;
            }
            if (endpoint.contains('/sobjects/Flow/301C')) {
                response.setBody('{"Metadata":{"triggerType":"RecordAfterSave","recordTriggerType":"CreateAndUpdate","description":"After flow"}}');
                return response;
            }
            if (endpoint.contains('/sobjects/Flow/301D')) {
                response.setBody('{"Metadata":{"triggerType":"RecordAfterSaveAsync","recordTriggerType":"UpdateOnly","description":"Async flow"}}');
                return response;
            }

            response.setBody('{"done":true,"totalSize":0,"records":[]}');
            return response;
        }

        private String decodeSoql(String endpoint) {
            Integer qStart = endpoint.indexOf('?q=');
            if (qStart < 0) {
                return '';
            }
            String encoded = endpoint.substring(qStart + 3);
            return EncodingUtil.urlDecode(encoded, 'UTF-8');
        }

        private String buildQueryResponse(String soql) {
            if (soql.contains('FROM ApexTrigger')) {
                return '{"done":true,"totalSize":1,"records":[{"Id":"01qA","Name":"AccountTrigger","TableEnumOrId":"Account","UsageBeforeInsert":true,"UsageAfterInsert":true,"UsageBeforeUpdate":true,"UsageAfterUpdate":true,"UsageBeforeDelete":true,"UsageAfterDelete":true,"UsageAfterUndelete":false,"Status":"Active"}]}';
            }

            if (soql.contains('FROM ValidationRule')) {
                return '{"done":true,"totalSize":1,"records":[{"Id":"03dA","ValidationName":"Require_Industry","Active":true,"ErrorConditionFormula":"ISBLANK(Industry)","EntityDefinition":{"QualifiedApiName":"Account"}}]}';
            }

            if (soql.contains('FROM FlowVersionView')) {
                return '{"done":true,"totalSize":4,"records":[' +
                    '{"Id":"301B","Status":"Active","VersionNumber":3,"TriggerObjectOrEvent":"Account","TriggerType":"RecordBeforeSave","FlowDefinitionView":{"ApiName":"Account_Before","Label":"Account Before"}},' +
                    '{"Id":"301C","Status":"Active","VersionNumber":2,"TriggerObjectOrEvent":{"QualifiedApiName":"Account"},"TriggerType":"RecordAfterSave","FlowDefinitionView":{"ApiName":"Account_After","Label":"Account After"}},' +
                    '{"Id":"301D","Status":"Active","VersionNumber":1,"TriggerObjectOrEvent":"Account","TriggerType":"RecordAfterSaveAsync","FlowDefinitionView":{"ApiName":"Account_Async","Label":"Account Async"}},' +
                    '{"Id":"301E","Status":"Active","VersionNumber":1,"TriggerObjectOrEvent":"Contact","TriggerType":"RecordBeforeSave","FlowDefinitionView":{"ApiName":"Contact_Before","Label":"Contact Before"}}' +
                ']}';
            }

            return '{"done":true,"totalSize":0,"records":[]}';
        }
    }

    private class EmptyObjectMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"done":true,"totalSize":0,"records":[]}');
            return response;
        }
    }

    private class ErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(500);
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"message":"boom"}');
            return response;
        }
    }
}
