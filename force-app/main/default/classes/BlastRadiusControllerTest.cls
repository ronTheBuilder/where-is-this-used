@IsTest
private with sharing class BlastRadiusControllerTest {
    @TestSetup
    static void setupPermission() {
        List<PermissionSet> permissionSets = [
            SELECT Id, Name
            FROM PermissionSet
            WHERE Name IN ('Where_Is_This_Used_User', 'Where_Is_This_Used_Admin')
            ORDER BY Name
            LIMIT 1
        ];
        if (permissionSets.isEmpty()) {
            return;
        }

        PermissionSet ps = permissionSets[0];
        List<PermissionSetAssignment> existing = [
            SELECT Id
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            AND PermissionSetId = :ps.Id
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = ps.Id);
        }
    }

    @IsTest
    static void getBlastRadius_returnsResponse() {
        Test.setMock(HttpCalloutMock.class, new ControllerBlastRadiusMock(false));

        Test.startTest();
        BlastRadiusService.BlastRadiusResponse response = BlastRadiusController.getBlastRadius('Flow', 'RootFlow', 3);
        Test.stopTest();

        System.assertEquals(2, response.stats.totalNodes);
        System.assertEquals(1, response.stats.totalEdges);
        System.assertEquals(false, response.limitReached);
    }

    @IsTest
    static void getBlastRadius_wrapsServiceException() {
        Test.setMock(HttpCalloutMock.class, new ControllerBlastRadiusMock(true));

        Boolean thrown = false;
        try {
            BlastRadiusController.getBlastRadius('Flow', 'RootFlow', 3);
        } catch (AuraHandledException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('Tooling API request failed'));
        }

        System.assertEquals(true, thrown);
    }

    private class ControllerBlastRadiusMock implements HttpCalloutMock {
        private final Boolean shouldError;

        ControllerBlastRadiusMock(Boolean shouldError) {
            this.shouldError = shouldError;
        }

        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            if (shouldError) {
                response.setStatusCode(500);
                response.setBody('{"message":"failure"}');
                return response;
            }

            response.setStatusCode(200);
            String endpoint = req.getEndpoint();
            if (endpoint.contains('/query/?q=')) {
                String soql = EncodingUtil.urlDecode(endpoint.substring(endpoint.indexOf('?q=') + 3), 'UTF-8');
                if (soql.contains('RefMetadataComponentName = \'RootFlow\'')) {
                    response.setBody('{"done":true,"totalSize":1,"records":[' +
                        '{"MetadataComponentId":"01pB","MetadataComponentName":"UsingClass","MetadataComponentType":"ApexClass"}' +
                    ']}');
                    return response;
                }
                response.setBody('{"done":true,"totalSize":0,"records":[]}');
                return response;
            }

            response.setBody('{"done":true,"totalSize":0,"records":[]}');
            return response;
        }
    }
}
