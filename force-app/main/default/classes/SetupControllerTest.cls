@IsTest
private with sharing class SetupControllerTest {

    @IsTest
    static void getAuthMode_defaultsToSession() {
        ToolingApiClient.bypassAccessCheckForTests = true;

        Test.startTest();
        String mode = SetupController.getAuthMode();
        Test.stopTest();

        System.assertEquals('session', mode);
    }

    @IsTest
    static void setAuthMode_setsNamedCredential() {
        ToolingApiClient.bypassAccessCheckForTests = true;

        Test.startTest();
        SetupController.setAuthMode('namedCredential');
        Test.stopTest();

        WITU_Settings__c settings = WITU_Settings__c.getOrgDefaults();
        System.assertEquals(true, settings.Use_Named_Credential__c);
    }

    @IsTest
    static void setAuthMode_setsSession() {
        ToolingApiClient.bypassAccessCheckForTests = true;
        WITU_Settings__c settings = WITU_Settings__c.getOrgDefaults();
        settings.Use_Named_Credential__c = true;
        upsert settings;

        Test.startTest();
        SetupController.setAuthMode('session');
        Test.stopTest();

        settings = WITU_Settings__c.getOrgDefaults();
        System.assertEquals(false, settings.Use_Named_Credential__c);
    }

    @IsTest
    static void testConnection_delegatesToService() {
        ToolingApiClient.bypassAccessCheckForTests = true;
        Test.setMock(HttpCalloutMock.class, new ConnectionMock());

        Test.startTest();
        Boolean result = SetupController.testConnection();
        Test.stopTest();

        System.assertEquals(true, result);
    }

    @IsTest
    static void getOrgDomainUrl_returnsUrl() {
        ToolingApiClient.bypassAccessCheckForTests = true;

        Test.startTest();
        String url = SetupController.getOrgDomainUrl();
        Test.stopTest();

        System.assertNotEquals(null, url);
        System.assert(url.startsWith('https://'));
    }

    @IsTest
    static void getUsers_returnsResults() {
        ToolingApiClient.bypassAccessCheckForTests = true;

        Test.startTest();
        List<SetupController.UserInfo> users = SetupController.getUsers('Admin');
        Test.stopTest();

        // At least the running user should match in most test contexts
        System.assertNotEquals(null, users);
    }

    @IsTest
    static void getPermissionSetAssignments_returnsResults() {
        ToolingApiClient.bypassAccessCheckForTests = true;

        Test.startTest();
        List<SetupController.PermissionAssignmentInfo> assignments = SetupController.getPermissionSetAssignments();
        Test.stopTest();

        System.assertNotEquals(null, assignments);
    }

    @IsTest
    static void assignPermissionSet_throwsOnEmpty() {
        ToolingApiClient.bypassAccessCheckForTests = true;

        try {
            Test.startTest();
            SetupController.assignPermissionSet(new List<Id>(), 'Where_Is_This_Used_User');
            Test.stopTest();
            System.assert(false, 'Expected exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('No users'));
        }
    }

    @IsTest
    static void removePermissionSetAssignment_handlesNull() {
        ToolingApiClient.bypassAccessCheckForTests = true;

        try {
            Test.startTest();
            SetupController.removePermissionSetAssignment(null);
            Test.stopTest();
            System.assert(false, 'Expected exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Assignment ID'));
        }
    }

    @IsTest
    static void createNamedCredentialSetup_throwsOnBlankName() {
        ToolingApiClient.bypassAccessCheckForTests = true;

        try {
            Test.startTest();
            SetupController.createNamedCredentialSetup('');
            Test.stopTest();
            System.assert(false, 'Expected exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Auth Provider'));
        }
    }

    @IsTest
    static void createNamedCredentialSetup_createsSuccessfully() {
        ToolingApiClient.bypassAccessCheckForTests = true;
        Test.setMock(HttpCalloutMock.class, new NcSetupMock(true));

        Test.startTest();
        Map<String, String> result = SetupController.createNamedCredentialSetup('WITU_Auth');
        Test.stopTest();

        System.assertEquals('created', result.get('externalCredential'));
        System.assertEquals('created', result.get('namedCredential'));
    }

    @IsTest
    static void createNamedCredentialSetup_handlesAlreadyExists() {
        ToolingApiClient.bypassAccessCheckForTests = true;
        Test.setMock(HttpCalloutMock.class, new NcSetupMock(false));

        Test.startTest();
        Map<String, String> result = SetupController.createNamedCredentialSetup('WITU_Auth');
        Test.stopTest();

        System.assertEquals('exists', result.get('externalCredential'));
        System.assertEquals('exists', result.get('namedCredential'));
    }

    private class NcSetupMock implements HttpCalloutMock {
        private final Boolean success;

        NcSetupMock(Boolean success) {
            this.success = success;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            if (this.success) {
                response.setStatusCode(201);
                response.setBody('{"id":"0XA000000000001"}');
            } else {
                response.setStatusCode(400);
                response.setBody('[{"message":"This entity already exists","errorCode":"DUPLICATE_VALUE"}]');
            }
            return response;
        }
    }

    private class ConnectionMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"done":true,"totalSize":1,"records":[{"Id":"00DTEST"}]}');
            return response;
        }
    }
}
