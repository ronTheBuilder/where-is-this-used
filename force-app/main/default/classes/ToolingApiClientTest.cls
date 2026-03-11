@IsTest
private with sharing class ToolingApiClientTest {
    @IsTest
    static void queryToolingRecords_marksLimitReached() {
        ToolingApiClient.bypassAccessCheckForTests = true;
        Test.setMock(HttpCalloutMock.class, new QueryPaginationMock());

        Test.startTest();
        ToolingApiClient.ToolingQueryResponse response = ToolingApiClient.queryToolingRecords(
            'SELECT Id FROM ApexClass',
            3
        );
        Test.stopTest();

        System.assertEquals(true, response.limitReached);
        System.assertEquals(3, response.records.size());
        System.assertEquals(false, response.done);
        System.assert(response.nextRecordsUrl != null);
    }

    @IsTest
    static void sendGet_throwsOn429WithoutRetry() {
        ToolingApiClient.bypassAccessCheckForTests = true;
        Retry429ThenSuccessMock mock = new Retry429ThenSuccessMock();
        Test.setMock(HttpCalloutMock.class, mock);

        try {
            Test.startTest();
            ToolingApiClient.sendGet('/services/data/v66.0/tooling/query/?q=SELECT+Id+FROM+Org');
            Test.stopTest();
            System.assert(false, 'Expected a 429 exception.');
        } catch (ToolingApiClient.ToolingApiClientException ex) {
            System.assert(ex.getMessage().contains('rate limit'));
            System.assertEquals(1, mock.callCount);
        }
    }

    @IsTest
    static void sendGet_retriesOn503ThenFails() {
        ToolingApiClient.bypassAccessCheckForTests = true;
        Always503Mock mock = new Always503Mock();
        Test.setMock(HttpCalloutMock.class, mock);

        try {
            Test.startTest();
            ToolingApiClient.sendGet('/services/data/v66.0/tooling/query/?q=SELECT+Id+FROM+Org');
            Test.stopTest();
            System.assert(false, 'Expected a 503 exception after retries.');
        } catch (ToolingApiClient.ToolingApiClientException ex) {
            System.assert(ex.getMessage().contains('temporarily unavailable'));
            System.assertEquals(3, mock.callCount);
        }
    }

    @IsTest
    static void sendGet_parses400ErrorBody() {
        ToolingApiClient.bypassAccessCheckForTests = true;
        Test.setMock(HttpCalloutMock.class, new Error400Mock());

        try {
            Test.startTest();
            ToolingApiClient.sendGet('/services/data/v66.0/tooling/query/?q=bad');
            Test.stopTest();
            System.assert(false, 'Expected a 400 exception.');
        } catch (ToolingApiClient.ToolingApiClientException ex) {
            System.assert(ex.getMessage().contains('Invalid query filter'));
        }
    }

    @IsTest
    static void utilityHelpers_validateAndCast() {
        ToolingApiClient.bypassAccessCheckForTests = true;

        ToolingApiClient.validateComponentName('Account.MyField__c');
        System.assertEquals(
            'callout:WITU_ToolingAPI/services/data/v66.0/tooling/query/01gNEXT',
            ToolingApiClient.resolveEndpoint('/services/data/v66.0/tooling/query/01gNEXT')
        );

        Map<String, Object> sourceMap = new Map<String, Object>{ 'k' => 'v' };
        List<Object> sourceList = new List<Object>{ 'x' };
        System.assertEquals('v', String.valueOf(ToolingApiClient.asMap(sourceMap).get('k')));
        System.assertEquals(1, ToolingApiClient.asList(sourceList).size());
        System.assertEquals(null, ToolingApiClient.asMap(sourceList));
        System.assertEquals(null, ToolingApiClient.asList(sourceMap));
    }

    @IsTest
    static void validateComponentName_rejectsInvalidCharacters() {
        ToolingApiClient.bypassAccessCheckForTests = true;
        try {
            ToolingApiClient.validateComponentName('Bad Name');
            System.assert(false, 'Expected invalid component name exception.');
        } catch (ToolingApiClient.ToolingApiClientException ex) {
            System.assert(ex.getMessage().contains('invalid characters'));
        }
    }

    @IsTest
    static void getFlowMetadata_returnsMetadataMap() {
        ToolingApiClient.bypassAccessCheckForTests = true;
        Test.setMock(HttpCalloutMock.class, new FlowMetadataMock());

        Test.startTest();
        Map<String, Object> metadata = ToolingApiClient.getFlowMetadata('301TEST');
        Test.stopTest();

        System.assertNotEquals(null, metadata);
        System.assertEquals(true, metadata.containsKey('subflows'));
    }

    @IsTest
    static void getFlowMetadata_returnsNullForEmptyPayload() {
        ToolingApiClient.bypassAccessCheckForTests = true;
        Test.setMock(HttpCalloutMock.class, new EmptyFlowMetadataMock());

        Test.startTest();
        Map<String, Object> metadata = ToolingApiClient.getFlowMetadata('301EMPTY');
        Test.stopTest();

        System.assertEquals(null, metadata);
    }

    @IsTest
    static void queryDependenciesWithNameFallback_serverSideSuccess() {
        ToolingApiClient.bypassAccessCheckForTests = true;
        Test.setMock(HttpCalloutMock.class, new DependencyFallbackMock(false));

        Test.startTest();
        ToolingApiClient.ToolingQueryResponse result = ToolingApiClient.queryDependenciesWithNameFallback(
            'MetadataComponentId, MetadataComponentName, MetadataComponentType, RefMetadataComponentName',
            'CustomField',
            'Account.MyField__c',
            2000
        );
        Test.stopTest();

        // Server-side filter succeeded — mock returns 2 records (real API would filter to 1)
        System.assertEquals(2, result.records.size());
    }

    @IsTest
    static void queryDependenciesWithNameFallback_fallsBackToClientSide() {
        ToolingApiClient.bypassAccessCheckForTests = true;
        Test.setMock(HttpCalloutMock.class, new DependencyFallbackMock(true));

        Test.startTest();
        ToolingApiClient.ToolingQueryResponse result = ToolingApiClient.queryDependenciesWithNameFallback(
            'MetadataComponentId, MetadataComponentName, MetadataComponentType, RefMetadataComponentName',
            'CustomField',
            'Account.MyField__c',
            2000
        );
        Test.stopTest();

        System.assertEquals(1, result.records.size());
    }

    @IsTest
    static void queryFlowVersionsWithFallback_fallsToFlowDefinitionView() {
        ToolingApiClient.bypassAccessCheckForTests = true;
        Test.setMock(HttpCalloutMock.class, new FlowVersionViewNotSupportedMock());

        Test.startTest();
        ToolingApiClient.ToolingQueryResponse result = ToolingApiClient.queryFlowVersionsWithFallback(
            null, 'Status = \'Active\'', 2000
        );
        Test.stopTest();

        System.assertEquals(1, result.records.size());
        Map<String, Object> record = ToolingApiClient.asMap(result.records[0]);
        System.assertEquals('301ACTIVE', String.valueOf(record.get('Id')));
        Map<String, Object> flowDef = ToolingApiClient.asMap(record.get('FlowDefinitionView'));
        System.assertNotEquals(null, flowDef);
        System.assertEquals('My_Flow', String.valueOf(flowDef.get('ApiName')));
    }

    private class QueryPaginationMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');

            if (req.getEndpoint().contains('/query/01gNEXT')) {
                response.setBody(
                    '{"done":false,"totalSize":5,"nextRecordsUrl":"/services/data/v66.0/tooling/query/01gMORE","records":[{"Id":"03"},{"Id":"04"},{"Id":"05"}]}'
                );
                return response;
            }

            response.setBody(
                '{"done":false,"totalSize":5,"nextRecordsUrl":"/services/data/v66.0/tooling/query/01gNEXT","records":[{"Id":"01"},{"Id":"02"}]}'
            );
            return response;
        }
    }

    private class Retry429ThenSuccessMock implements HttpCalloutMock {
        public Integer callCount = 0;

        public HttpResponse respond(HttpRequest req) {
            callCount++;
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            if (callCount == 1) {
                response.setStatusCode(429);
                response.setBody('{"message":"Rate limited"}');
                return response;
            }

            response.setStatusCode(200);
            response.setBody('{"done":true,"totalSize":1,"records":[{"Id":"00D"}]}');
            return response;
        }
    }

    private class Always503Mock implements HttpCalloutMock {
        public Integer callCount = 0;

        public HttpResponse respond(HttpRequest req) {
            callCount++;
            HttpResponse response = new HttpResponse();
            response.setStatusCode(503);
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"message":"Service unavailable"}');
            return response;
        }
    }

    private class Error400Mock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(400);
            response.setHeader('Content-Type', 'application/json');
            response.setBody('[{"message":"Invalid query filter","errorCode":"MALFORMED_QUERY"}]');
            return response;
        }
    }

    private class FlowMetadataMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"Metadata":{"subflows":[{"flowName":"SubFlow1"}]}}');
            return response;
        }
    }

    private class EmptyFlowMetadataMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{}');
            return response;
        }
    }

    private class DependencyFallbackMock implements HttpCalloutMock {
        private final Boolean failServerSide;
        private Integer callCount = 0;

        DependencyFallbackMock(Boolean failServerSide) {
            this.failServerSide = failServerSide;
        }

        public HttpResponse respond(HttpRequest req) {
            callCount++;
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();
            String soql = '';
            if (endpoint.contains('?q=')) {
                soql = EncodingUtil.urlDecode(endpoint.substring(endpoint.indexOf('?q=') + 3), 'UTF-8');
            }

            if (failServerSide && soql.containsIgnoreCase('WHERE') && soql.substringAfter('WHERE').contains('RefMetadataComponentName')) {
                response.setStatusCode(400);
                response.setBody('[{"message":"Invalid query filter","errorCode":"MALFORMED_QUERY"}]');
                return response;
            }

            response.setStatusCode(200);
            response.setBody('{"done":true,"totalSize":2,"records":[' +
                '{"MetadataComponentId":"01pA","MetadataComponentName":"ClassA","MetadataComponentType":"ApexClass","RefMetadataComponentName":"Account.MyField__c"},' +
                '{"MetadataComponentId":"01pB","MetadataComponentName":"ClassB","MetadataComponentType":"ApexClass","RefMetadataComponentName":"Account.Other__c"}' +
            ']}');
            return response;
        }
    }

    private class FlowVersionViewNotSupportedMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();
            String soql = '';
            if (endpoint.contains('?q=')) {
                soql = EncodingUtil.urlDecode(endpoint.substring(endpoint.indexOf('?q=') + 3), 'UTF-8');
            }

            // FlowVersionView is not supported on this org
            if (soql.contains('FROM FlowVersionView')) {
                response.setStatusCode(400);
                response.setBody('[{"message":"sObject type \'FlowVersionView\' is not supported","errorCode":"INVALID_TYPE"}]');
                return response;
            }

            // FlowDefinitionView works
            if (soql.contains('FROM FlowDefinitionView')) {
                response.setStatusCode(200);
                response.setBody('{"done":true,"totalSize":1,"records":[' +
                    '{"ApiName":"My_Flow","Label":"My Flow","ActiveVersionId":"301ACTIVE"}' +
                ']}');
                return response;
            }

            response.setStatusCode(200);
            response.setBody('{"done":true,"totalSize":0,"records":[]}');
            return response;
        }
    }
}
