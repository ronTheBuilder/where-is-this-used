@IsTest
private with sharing class DataJourneyServiceTest {
    @IsTest
    static void traceDataJourney_buildsUpstreamAndDownstreamGraph() {
        Test.setMock(HttpCalloutMock.class, new DataJourneyMock());

        Test.startTest();
        DataJourneyService.DataJourneyResponse response = DataJourneyService.traceDataJourney(
            'Account',
            'Region__c',
            3
        );
        Test.stopTest();

        System.assertEquals('Account', response.objectName);
        System.assertEquals('Region__c', response.fieldName);
        System.assert(response.nodes.size() > 0);
        System.assert(response.edges.size() > 0);

        System.assert(hasNode(response.nodes, 'field:Account.Region__c'));
        System.assert(hasNode(response.nodes, 'flow:F1'));
        System.assert(hasNode(response.nodes, 'field:Opportunity.Type'));
        System.assert(hasNode(response.nodes, 'apex:TR1'));
        System.assert(hasNode(response.nodes, 'flow:F3'));

        System.assert(hasEdge(response.edges, 'field:Account.Region__c', 'flow:F1', 'read_by'));
        System.assert(hasEdge(response.edges, 'flow:F1', 'field:Opportunity.Type', 'writes_to'));
        System.assert(hasEdge(response.edges, 'flow:F3', 'field:Account.Region__c', 'writes_to'));
    }

    @IsTest
    static void traceDownstream_appliesFlowRetrievalLimit() {
        Test.setMock(HttpCalloutMock.class, new DataJourneyMock());

        Test.startTest();
        DataJourneyService.DataJourneyResponse response = DataJourneyService.traceDownstream(
            'Account',
            'BigField__c',
            1
        );
        Test.stopTest();

        System.assertEquals(true, response.limitReached);
        Boolean sawWarning = false;
        for (String warning : response.warnings) {
            if (warning.contains('Flow metadata retrieval limit reached')) {
                sawWarning = true;
            }
        }
        System.assertEquals(true, sawWarning);
    }

    @IsTest
    static void traceDataJourney_validatesInput() {
        Boolean thrown = false;
        try {
            DataJourneyService.traceDataJourney('Account', 'Region__c', 0);
        } catch (DataJourneyService.DataJourneyServiceException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('Max depth'));
        }
        System.assertEquals(true, thrown);
    }

    private static Boolean hasNode(List<DataJourneyService.DataJourneyNode> nodes, String id) {
        for (DataJourneyService.DataJourneyNode node : nodes) {
            if (node.id == id) {
                return true;
            }
        }
        return false;
    }

    private static Boolean hasEdge(List<DataJourneyService.DataJourneyEdge> edges, String source, String target, String relationship) {
        for (DataJourneyService.DataJourneyEdge edge : edges) {
            if (edge.sourceId == source && edge.targetId == target && edge.relationship == relationship) {
                return true;
            }
        }
        return false;
    }

    private class DataJourneyMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            String endpoint = req.getEndpoint();
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');

            if (endpoint.contains('/sobjects/Flow/')) {
                response.setBody(flowMetadataFor(endpoint));
                return response;
            }

            if (endpoint.contains('/query/?q=')) {
                String soql = decodeSoql(endpoint);
                response.setBody(queryResponseFor(soql));
                return response;
            }

            response.setBody('{"done":true,"totalSize":0,"records":[]}');
            return response;
        }

        private static String decodeSoql(String endpoint) {
            Integer start = endpoint.indexOf('?q=');
            if (start < 0) {
                return '';
            }
            return EncodingUtil.urlDecode(endpoint.substring(start + 3), 'UTF-8');
        }

        private static String queryResponseFor(String soql) {
            if (soql.contains('FROM FlowVersionView')) {
                return '{"done":true,"totalSize":3,"records":[' +
                    '{"Id":"F1","FlowDefinitionView":{"ApiName":"Territory_Assignment_Flow","Label":"Territory Assignment"}},' +
                    '{"Id":"F2","FlowDefinitionView":{"ApiName":"Route_To_Queue","Label":"Route To Queue"}},' +
                    '{"Id":"F3","FlowDefinitionView":{"ApiName":"Set_Region","Label":"Set Region"}}' +
                ']}';
            }

            if (soql.contains('FROM MetadataComponentDependency') && soql.contains('Account.Region__c')) {
                return '{"done":true,"totalSize":2,"records":[' +
                    '{"MetadataComponentId":"TR1","MetadataComponentName":"AccountTrigger","MetadataComponentType":"ApexTrigger","MetadataComponentNamespace":null},' +
                    '{"MetadataComponentId":"F1","MetadataComponentName":"Territory_Assignment_Flow","MetadataComponentType":"Flow","MetadataComponentNamespace":null}' +
                ']}';
            }

            if (soql.contains('FROM MetadataComponentDependency') && soql.contains('Opportunity.Type')) {
                return '{"done":true,"totalSize":1,"records":[' +
                    '{"MetadataComponentId":"F2","MetadataComponentName":"Route_To_Queue","MetadataComponentType":"Flow","MetadataComponentNamespace":null}' +
                ']}';
            }

            if (soql.contains('FROM MetadataComponentDependency') && soql.contains('Case.Origin')) {
                return '{"done":true,"totalSize":0,"records":[]}';
            }

            if (soql.contains('FROM MetadataComponentDependency') && soql.contains('Account.BigField__c')) {
                List<Object> many = new List<Object>();
                for (Integer i = 0; i < 60; i++) {
                    many.add(new Map<String, Object>{
                        'MetadataComponentId' => 'L' + String.valueOf(i),
                        'MetadataComponentName' => 'FlowLimit' + String.valueOf(i),
                        'MetadataComponentType' => 'Flow',
                        'MetadataComponentNamespace' => null
                    });
                }
                Map<String, Object> payload = new Map<String, Object>{
                    'done' => true,
                    'totalSize' => 60,
                    'records' => many
                };
                return JSON.serialize(payload);
            }

            return '{"done":true,"totalSize":0,"records":[]}';
        }

        private static String flowMetadataFor(String endpoint) {
            if (endpoint.contains('/sobjects/Flow/F1')) {
                return '{"Metadata":{' +
                    '"decisions":[{"rules":[{"conditions":[{"leftValueReference":"$Record.Region__c","operator":"EqualTo","rightValue":{"stringValue":"EMEA"}}]}]}],' +
                    '"recordUpdates":[{"inputAssignments":[{"field":"Opportunity.Type","value":{"elementReference":"$Record.Region__c"}}]}]' +
                '}}';
            }

            if (endpoint.contains('/sobjects/Flow/F2')) {
                return '{"Metadata":{' +
                    '"formulas":[{"name":"route","expression":"IF(Opportunity.Type=\"Enterprise\", \"Queue\", \"Standard\")"}],' +
                    '"recordCreates":[{"inputAssignments":[{"field":"Case.Origin","value":{"stringValue":"Phone"}}]}]' +
                '}}';
            }

            if (endpoint.contains('/sobjects/Flow/F3')) {
                return '{"Metadata":{' +
                    '"recordUpdates":[{"inputAssignments":[{"field":"$Record.Region__c","value":{"elementReference":"$Record.BillingCountry"}}]}]' +
                '}}';
            }

            if (endpoint.contains('/sobjects/Flow/L')) {
                return '{"Metadata":{' +
                    '"recordUpdates":[{"inputAssignments":[{"field":"$Record.OtherField__c","value":{"elementReference":"$Record.BigField__c"}}]}]' +
                '}}';
            }

            return '{"Metadata":{}}';
        }
    }
}
