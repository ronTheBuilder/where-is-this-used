@IsTest
private with sharing class MetadataPickerControllerTest {
    @IsTest
    static void getObjects_returnsAccessibleObjects() {
        List<DependencyService.MetadataOption> objects = MetadataPickerController.getObjects();
        System.assert(!objects.isEmpty());

        Boolean hasAccount = false;
        for (DependencyService.MetadataOption option : objects) {
            if (option.value == 'Account') {
                hasAccount = true;
            }
        }
        System.assertEquals(true, hasAccount);
    }

    @IsTest
    static void getFields_returnsStandardAndCustomTypes() {
        List<MetadataPickerController.FieldOption> fields = MetadataPickerController.getFields('Account');
        System.assert(!fields.isEmpty());

        Boolean sawStandard = false;
        for (MetadataPickerController.FieldOption field : fields) {
            if (field.metadataType == 'Standard Field') {
                sawStandard = true;
                break;
            }
        }

        System.assertEquals(true, sawStandard);
    }

    @IsTest
    static void getFields_throwsForInvalidObject() {
        Boolean thrown = false;

        try {
            MetadataPickerController.getFields('Definitely_Not_An_Object__c');
        } catch (AuraHandledException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('Object not found'));
        }

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void getFlowsAndApexClasses_returnToolingData() {
        Test.setMock(HttpCalloutMock.class, new PickerMock());

        Test.startTest();
        List<DependencyService.MetadataOption> flows = MetadataPickerController.getFlows();
        List<DependencyService.MetadataOption> classes = MetadataPickerController.getApexClasses();
        Test.stopTest();

        System.assertEquals(1, flows.size());
        System.assertEquals('My Active Flow', flows[0].label);
        System.assertEquals('MyActiveFlow', flows[0].value);
        System.assertEquals(1, classes.size());
        System.assertEquals('MyUtility', classes[0].value);
    }

    private class PickerMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();
            if (endpoint.contains('/query/?q=')) {
                String soql = EncodingUtil.urlDecode(endpoint.substring(endpoint.indexOf('?q=') + 3), 'UTF-8');
                if (soql.contains('FROM FlowVersionView')) {
                    response.setBody('{"done":true,"totalSize":1,"records":[{"Id":"3011","FlowDefinitionView":{"ApiName":"MyActiveFlow","Label":"My Active Flow"}}]}');
                } else if (soql.contains('FROM ApexClass')) {
                    response.setBody('{"done":true,"totalSize":1,"records":[{"Id":"01p1","Name":"MyUtility"}]}');
                } else {
                    response.setBody('{"done":true,"totalSize":0,"records":[]}');
                }
                return response;
            }

            response.setBody('{"done":true,"totalSize":0,"records":[]}');
            return response;
        }
    }
}
