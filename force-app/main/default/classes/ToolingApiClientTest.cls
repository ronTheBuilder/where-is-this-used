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
    static void sendGet_retriesOn429AndSucceeds() {
        ToolingApiClient.bypassAccessCheckForTests = true;
        Retry429ThenSuccessMock mock = new Retry429ThenSuccessMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        HttpResponse response = ToolingApiClient.sendGet('/services/data/v65.0/tooling/query/?q=SELECT+Id+FROM+Org');
        Test.stopTest();

        System.assertEquals(200, response.getStatusCode());
        System.assertEquals(2, mock.callCount);
    }

    @IsTest
    static void sendGet_retriesOn503ThenFails() {
        ToolingApiClient.bypassAccessCheckForTests = true;
        Always503Mock mock = new Always503Mock();
        Test.setMock(HttpCalloutMock.class, mock);

        try {
            Test.startTest();
            ToolingApiClient.sendGet('/services/data/v65.0/tooling/query/?q=SELECT+Id+FROM+Org');
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
            ToolingApiClient.sendGet('/services/data/v65.0/tooling/query/?q=bad');
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
            'callout:WITU_ToolingAPI/services/data/v65.0/tooling/query/01gNEXT',
            ToolingApiClient.resolveEndpoint('/services/data/v65.0/tooling/query/01gNEXT')
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

    private class QueryPaginationMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');

            if (req.getEndpoint().contains('/query/01gNEXT')) {
                response.setBody(
                    '{"done":false,"totalSize":5,"nextRecordsUrl":"/services/data/v65.0/tooling/query/01gMORE","records":[{"Id":"03"},{"Id":"04"},{"Id":"05"}]}'
                );
                return response;
            }

            response.setBody(
                '{"done":false,"totalSize":5,"nextRecordsUrl":"/services/data/v65.0/tooling/query/01gNEXT","records":[{"Id":"01"},{"Id":"02"}]}'
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
}
