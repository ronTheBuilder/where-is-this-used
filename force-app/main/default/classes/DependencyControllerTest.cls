@IsTest
private with sharing class DependencyControllerTest {
    @TestSetup
    static void setupPermission() {
        grantAccessPermission();
    }

    @IsTest
    static void getMetadataTypes_returnsExpectedList() {
        List<String> types = DependencyController.getMetadataTypes();
        System.assert(types.contains('Standard Field'));
        System.assert(types.contains('Custom Field'));
        System.assert(types.contains('Flow'));
        System.assert(types.contains('Apex Class'));
    }

    @IsTest
    static void searchDependencies_returnsGroupedResponse() {
        Test.setMock(HttpCalloutMock.class, new ControllerMock());

        Test.startTest();
        DependencyService.DependencySearchResponse response = DependencyController.searchDependencies(
            'Apex Class',
            'MyClass'
        );
        Test.stopTest();

        System.assertEquals('Apex Class', response.metadataType);
        System.assertEquals(1, response.totalCount);
        System.assertEquals('ApexTrigger', response.groups[0].componentType);
    }

    @IsTest
    static void searchDependencies_throwsOnUnsupportedType() {
        Boolean thrown = false;

        try {
            DependencyController.searchDependencies('Report', 'AccountReport');
        } catch (AuraHandledException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('not yet supported'));
        }

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testConnection_returnsTrue() {
        Test.setMock(HttpCalloutMock.class, new ControllerMock());

        Test.startTest();
        Boolean connected = DependencyController.testConnection();
        Test.stopTest();

        System.assertEquals(true, connected);
    }

    private class ControllerMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();
            if (endpoint.contains('/query/?q=')) {
                String soql = EncodingUtil.urlDecode(endpoint.substring(endpoint.indexOf('?q=') + 3), 'UTF-8');
                if (soql.contains('FROM Organization')) {
                    response.setBody('{"done":true,"totalSize":1,"records":[{"Id":"00D1"}]}');
                } else if (soql.contains('FROM MetadataComponentDependency')) {
                    response.setBody('{"done":true,"totalSize":1,"records":[{"MetadataComponentId":"01q","MetadataComponentName":"MyTrigger","MetadataComponentType":"ApexTrigger"}]}');
                } else {
                    response.setBody('{"done":true,"totalSize":0,"records":[]}');
                }
                return response;
            }

            response.setBody('{"done":true,"totalSize":0,"records":[]}');
            return response;
        }
    }

    private static void grantAccessPermission() {
        List<PermissionSet> permissionSets = [
            SELECT Id FROM PermissionSet
            WHERE Name IN ('Where_Is_This_Used_User', 'Where_Is_This_Used_Admin')
            LIMIT 1
        ];
        if (!permissionSets.isEmpty()) {
            List<PermissionSetAssignment> existing = [
                SELECT Id FROM PermissionSetAssignment
                WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :permissionSets[0].Id
                LIMIT 1
            ];
            if (existing.isEmpty()) {
                try {
                    insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = permissionSets[0].Id);
                } catch (DmlException e) {
                    if (e.getMessage().contains('UNABLE_TO_LOCK_ROW')) {
                        return;
                    }
                    throw e;
                }
            }
        }
    }
}
