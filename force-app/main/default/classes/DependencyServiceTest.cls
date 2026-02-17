@IsTest
private with sharing class DependencyServiceTest {
    @TestSetup
    static void setupPermission() {
        grantAccessPermission();
    }

    @IsTest
    static void searchDependencies_groupsByType() {
        Test.setMock(HttpCalloutMock.class, new DependencyServiceMock());

        Test.startTest();
        DependencyService.DependencySearchResponse response = DependencyService.searchDependencies(
            'Custom Field',
            'Account.MyField__c'
        );
        Test.stopTest();

        System.assertEquals('Custom Field', response.metadataType);
        System.assertEquals('Account.MyField__c', response.componentName);
        System.assertEquals(2, response.totalCount);
        System.assertEquals(false, response.limitReached);
        System.assertEquals(2, response.groups.size());
        System.assertEquals('ApexClass', response.groups[0].componentType);
        System.assertEquals('Flow', response.groups[1].componentType);
    }

    @IsTest
    static void searchDependencies_marksLimitReachedAt2000() {
        Test.setMock(HttpCalloutMock.class, new DependencyServiceMock());

        Test.startTest();
        DependencyService.DependencySearchResponse response = DependencyService.searchDependencies(
            'Custom Field',
            'BigField'
        );
        Test.stopTest();

        System.assertEquals(true, response.limitReached);
        System.assertEquals(2000, response.totalCount);
        System.assert(response.warningMessage != null && response.warningMessage.contains('2,000'));
    }

    @IsTest
    static void searchDependencies_includesSubflowUsage() {
        Test.setMock(HttpCalloutMock.class, new DependencyServiceMock());

        Test.startTest();
        DependencyService.DependencySearchResponse response = DependencyService.searchDependencies('Flow', 'TargetFlow');
        Test.stopTest();

        Boolean foundSubflow = false;
        for (DependencyService.DependencyGroup grp : response.groups) {
            for (DependencyService.DependencyRecord record : grp.records) {
                if (record.isSubflowReference == true && record.metadataComponentName == 'Parent One') {
                    foundSubflow = true;
                }
            }
        }
        System.assertEquals(true, foundSubflow);
    }

    @IsTest
    static void testConnection_success() {
        Test.setMock(HttpCalloutMock.class, new DependencyServiceMock());

        Test.startTest();
        Boolean connected = DependencyService.testConnection();
        Test.stopTest();

        System.assertEquals(true, connected);
    }

    private class DependencyServiceMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            String endpoint = req.getEndpoint();
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');

            if (endpoint.contains('/sobjects/Flow/301A')) {
                response.setBody('{"Metadata":{"subflows":[{"flowName":"TargetFlow"}]}}');
                return response;
            }
            if (endpoint.contains('/sobjects/Flow/301B')) {
                response.setBody('{"Metadata":{"subflows":[{"flowName":"AnotherFlow"}]}}');
                return response;
            }
            if (endpoint.contains('/query/?q=')) {
                String soql = decodeSoql(endpoint);
                response.setBody(buildQueryResponse(soql));
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
            if (soql.contains('FROM Organization')) {
                return '{"done":true,"totalSize":1,"records":[{"Id":"00Dxx0000000001"}]}';
            }

            if (soql.contains('FROM MetadataComponentDependency') && soql.contains('BigField')) {
                List<Object> largeSet = new List<Object>();
                for (Integer i = 0; i < 2000; i++) {
                    largeSet.add(new Map<String, Object>{
                        'MetadataComponentId' => '01p' + String.valueOf(i),
                        'MetadataComponentName' => 'Class' + String.valueOf(i),
                        'MetadataComponentType' => 'ApexClass',
                        'MetadataComponentNamespace' => null
                    });
                }
                Map<String, Object> payload = new Map<String, Object>{
                    'done' => false,
                    'totalSize' => 2500,
                    'nextRecordsUrl' => '/services/data/v65.0/tooling/query/01gNEXT',
                    'records' => largeSet
                };
                return JSON.serialize(payload);
            }

            if (soql.contains('FROM MetadataComponentDependency') && soql.contains('Account.MyField__c')) {
                return '{"done":true,"totalSize":2,"records":[' +
                    '{"MetadataComponentId":"01pA","MetadataComponentName":"UsageClass","MetadataComponentType":"ApexClass","MetadataComponentNamespace":null},' +
                    '{"MetadataComponentId":"301A","MetadataComponentName":"FieldFlow","MetadataComponentType":"Flow","MetadataComponentNamespace":null}' +
                ']}';
            }

            if (soql.contains('FROM MetadataComponentDependency') && soql.contains('TargetFlow')) {
                return '{"done":true,"totalSize":0,"records":[]}';
            }

            if (soql.contains('FROM FlowVersionView') && soql.contains('FlowDefinitionView.ApiName !=')) {
                return '{"done":true,"totalSize":2,"records":[' +
                    '{"Id":"301A","FlowDefinitionView":{"ApiName":"Parent_One","Label":"Parent One"}},' +
                    '{"Id":"301B","FlowDefinitionView":{"ApiName":"Parent_Two","Label":"Parent Two"}}' +
                ']}';
            }

            return '{"done":true,"totalSize":0,"records":[]}';
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
                        // Parallel test; another test class may have assigned it
                        return;
                    }
                    throw e;
                }
            }
        }
    }
}
