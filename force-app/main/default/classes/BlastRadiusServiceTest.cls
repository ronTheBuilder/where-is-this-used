@IsTest
private with sharing class BlastRadiusServiceTest {
    @TestSetup
    static void setupPermission() {
        grantAccessPermission();
    }

    @IsTest
    static void getBlastRadius_resolvesBasicGraph() {
        Test.setMock(HttpCalloutMock.class, new BlastRadiusMock('basic'));

        Test.startTest();
        BlastRadiusService.BlastRadiusResponse response = BlastRadiusService.getBlastRadius(
            'Custom Field',
            'Account.MyField__c',
            3
        );
        Test.stopTest();

        System.assertEquals(false, response.limitReached);
        System.assertEquals(4, response.stats.totalNodes);
        System.assertEquals(3, response.stats.totalEdges);
        System.assertEquals(2, response.totalDepth);

        BlastRadiusService.GraphNode root = findNode(response.nodes, 'Account.MyField__c');
        System.assertNotEquals(null, root);
        System.assertEquals(true, root.isRoot);
        System.assertEquals('CustomField', root.componentType);
    }

    @IsTest
    static void getBlastRadius_marksCycleNodes() {
        Test.setMock(HttpCalloutMock.class, new BlastRadiusMock('cycle'));

        Test.startTest();
        BlastRadiusService.BlastRadiusResponse response = BlastRadiusService.getBlastRadius('Flow', 'CycleRoot', 5);
        Test.stopTest();

        BlastRadiusService.GraphNode root = findNode(response.nodes, 'CycleRoot');
        BlastRadiusService.GraphNode child = findNode(response.nodes, 'CycleChild');
        System.assertNotEquals(null, root);
        System.assertNotEquals(null, child);
        System.assertEquals(true, root.isCycleNode);
        System.assertEquals(true, child.isCycleNode);
        System.assertEquals(2, response.stats.totalEdges);
    }

    @IsTest
    static void getBlastRadius_enforcesDepthLimit() {
        Test.setMock(HttpCalloutMock.class, new BlastRadiusMock('depth'));

        Test.startTest();
        BlastRadiusService.BlastRadiusResponse response = BlastRadiusService.getBlastRadius('Flow', 'DepthRoot', 2);
        Test.stopTest();

        System.assertNotEquals(null, findNode(response.nodes, 'DepthL1'));
        System.assertNotEquals(null, findNode(response.nodes, 'DepthL2'));
        System.assertEquals(null, findNode(response.nodes, 'DepthL3'));
        System.assertEquals(2, response.totalDepth);
    }

    @IsTest
    static void getBlastRadius_stopsAtNodeCap() {
        Test.setMock(HttpCalloutMock.class, new BlastRadiusMock('nodeCap'));

        Test.startTest();
        BlastRadiusService.BlastRadiusResponse response = BlastRadiusService.getBlastRadius('Flow', 'NodeCapRoot', 3);
        Test.stopTest();

        System.assertEquals(true, response.limitReached);
        // With MAX_API_CALLS=50, root uses 1 call then each child uses 1 → ~51 nodes
        System.assert(response.stats.totalNodes > 1, 'Expected multiple nodes, got: ' + response.stats.totalNodes);
        System.assert(response.stats.totalNodes <= 500, 'Expected at most 500 nodes');
        System.assert(response.warningMessage != null);
    }

    @IsTest
    static void getBlastRadius_throwsOnToolingError() {
        Test.setMock(HttpCalloutMock.class, new BlastRadiusMock('error'));

        Boolean thrown = false;
        try {
            Test.startTest();
            BlastRadiusService.getBlastRadius('Flow', 'ErrorRoot', 3);
            Test.stopTest();
        } catch (BlastRadiusService.BlastRadiusServiceException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('Tooling API request failed'));
        }

        System.assertEquals(true, thrown);
    }

    @IsTest
    static void getBlastRadius_rejectsInvalidInput() {
        Boolean thrown = false;

        try {
            BlastRadiusService.getBlastRadius('Flow', 'Invalid Name!', 3);
        } catch (BlastRadiusService.BlastRadiusServiceException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('invalid characters'));
        }

        System.assertEquals(true, thrown);
    }

    private static BlastRadiusService.GraphNode findNode(List<BlastRadiusService.GraphNode> nodes, String name) {
        for (BlastRadiusService.GraphNode node : nodes) {
            if (node.name == name) {
                return node;
            }
        }
        return null;
    }

    private static void grantAccessPermission() {
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

        PermissionSet target = permissionSets[0];
        List<PermissionSetAssignment> existing = [
            SELECT Id
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            AND PermissionSetId = :target.Id
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = target.Id);
        }
    }

    private class BlastRadiusMock implements HttpCalloutMock {
        private final String scenario;

        BlastRadiusMock(String scenario) {
            this.scenario = scenario;
        }

        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();
            if (scenario == 'error') {
                response.setStatusCode(500);
                response.setBody('{"message":"boom"}');
                return response;
            }

            response.setStatusCode(200);
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
            if (scenario == 'basic') {
                return basicResponse(soql);
            }
            if (scenario == 'cycle') {
                return cycleResponse(soql);
            }
            if (scenario == 'depth') {
                return depthResponse(soql);
            }
            if (scenario == 'nodeCap') {
                return nodeCapResponse(soql);
            }
            return '{"done":true,"totalSize":0,"records":[]}';
        }

        private String basicResponse(String soql) {
            // Refactored: queries by RefMetadataComponentType only; client-side filters by RefMetadataComponentName
            if (soql.contains('RefMetadataComponentType = \'CustomField\'')) {
                return '{"done":true,"totalSize":2,"records":[' +
                    '{"MetadataComponentId":"301A","MetadataComponentName":"FlowUsage","MetadataComponentType":"Flow","RefMetadataComponentName":"Account.MyField__c"},' +
                    '{"MetadataComponentId":"01pA","MetadataComponentName":"ClassUsage","MetadataComponentType":"ApexClass","RefMetadataComponentName":"Account.MyField__c"}' +
                ']}';
            }
            if (soql.contains('RefMetadataComponentType = \'Flow\'')) {
                return '{"done":true,"totalSize":1,"records":[' +
                    '{"MetadataComponentId":"01qA","MetadataComponentName":"TriggerUsage","MetadataComponentType":"ApexTrigger","RefMetadataComponentName":"FlowUsage"}' +
                ']}';
            }
            if (soql.contains('RefMetadataComponentType = \'ApexClass\'')) {
                return '{"done":true,"totalSize":0,"records":[]}';
            }
            return '{"done":true,"totalSize":0,"records":[]}';
        }

        private String cycleResponse(String soql) {
            if (soql.contains('RefMetadataComponentType = \'FlowDefinition\'') || soql.contains('RefMetadataComponentType = \'Flow\'')) {
                // Return both; CycleRoot uses FlowDefinition type to match root key
                return '{"done":true,"totalSize":2,"records":[' +
                    '{"MetadataComponentId":"301CC","MetadataComponentName":"CycleChild","MetadataComponentType":"Flow","RefMetadataComponentName":"CycleRoot"},' +
                    '{"MetadataComponentId":"301CR","MetadataComponentName":"CycleRoot","MetadataComponentType":"FlowDefinition","RefMetadataComponentName":"CycleChild"}' +
                ']}';
            }
            return '{"done":true,"totalSize":0,"records":[]}';
        }

        private String depthResponse(String soql) {
            if (soql.contains('RefMetadataComponentType = \'FlowDefinition\'') || soql.contains('RefMetadataComponentType = \'Flow\'')) {
                return '{"done":true,"totalSize":3,"records":[' +
                    '{"MetadataComponentId":"301D1","MetadataComponentName":"DepthL1","MetadataComponentType":"Flow","RefMetadataComponentName":"DepthRoot"},' +
                    '{"MetadataComponentId":"301D2","MetadataComponentName":"DepthL2","MetadataComponentType":"Flow","RefMetadataComponentName":"DepthL1"},' +
                    '{"MetadataComponentId":"301D3","MetadataComponentName":"DepthL3","MetadataComponentType":"Flow","RefMetadataComponentName":"DepthL2"}' +
                ']}';
            }
            return '{"done":true,"totalSize":0,"records":[]}';
        }

        private String nodeCapResponse(String soql) {
            if (!soql.contains('RefMetadataComponentType = \'FlowDefinition\'') && !soql.contains('RefMetadataComponentType = \'Flow\'')) {
                return '{"done":true,"totalSize":0,"records":[]}';
            }

            List<Object> rows = new List<Object>();
            for (Integer i = 0; i < 501; i++) {
                rows.add(new Map<String, Object>{
                    'MetadataComponentId' => '01pNC' + String.valueOf(i),
                    'MetadataComponentName' => 'NodeCapChild' + String.valueOf(i),
                    'MetadataComponentType' => 'ApexClass',
                    'RefMetadataComponentName' => 'NodeCapRoot'
                });
            }

            Map<String, Object> payload = new Map<String, Object>{
                'done' => true,
                'totalSize' => 501,
                'records' => rows
            };
            return JSON.serialize(payload);
        }
    }
}
