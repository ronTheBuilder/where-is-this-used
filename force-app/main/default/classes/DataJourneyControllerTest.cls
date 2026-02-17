@IsTest
private with sharing class DataJourneyControllerTest {
    @IsTest
    static void traceDataJourney_returnsResponse() {
        Test.setMock(HttpCalloutMock.class, new ControllerMock());

        Test.startTest();
        DataJourneyService.DataJourneyResponse response = DataJourneyController.traceDataJourney(
            'Account',
            'Region__c',
            2
        );
        Test.stopTest();

        System.assertEquals('Account', response.objectName);
        System.assertEquals('Region__c', response.fieldName);
        System.assert(response.nodes.size() > 0);
    }

    @IsTest
    static void traceDataJourney_throwsAuraHandledException() {
        Boolean thrown = false;
        try {
            DataJourneyController.traceDataJourney('', 'Region__c', 2);
        } catch (AuraHandledException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('Object name is required'));
        }
        System.assertEquals(true, thrown);
    }

    private class ControllerMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();
            if (endpoint.contains('/query/?q=')) {
                String soql = EncodingUtil.urlDecode(endpoint.substring(endpoint.indexOf('?q=') + 3), 'UTF-8');
                if (soql.contains('FROM MetadataComponentDependency') && soql.contains('Account.Region__c')) {
                    response.setBody('{"done":true,"totalSize":1,"records":[{"MetadataComponentId":"F1","MetadataComponentName":"MyFlow","MetadataComponentType":"Flow"}]}');
                    return response;
                }
                if (soql.contains('FROM FlowVersionView')) {
                    response.setBody('{"done":true,"totalSize":1,"records":[{"Id":"F1","FlowDefinitionView":{"ApiName":"MyFlow","Label":"My Flow"}}]}');
                    return response;
                }
                response.setBody('{"done":true,"totalSize":0,"records":[]}');
                return response;
            }

            if (endpoint.contains('/sobjects/Flow/F1')) {
                response.setBody('{"Metadata":{"recordUpdates":[{"inputAssignments":[{"field":"$Record.Region__c","value":{"stringValue":"EMEA"}}]}]}}');
                return response;
            }

            response.setBody('{"done":true,"totalSize":0,"records":[]}');
            return response;
        }
    }
}
