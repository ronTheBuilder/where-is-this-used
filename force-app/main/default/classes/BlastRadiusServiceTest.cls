@IsTest
private with sharing class BlastRadiusServiceTest {
    @TestSetup
    static void setupPermission() {
        grantAccessPermission();
    }

    @IsTest
    static void getBlastRadius_resolvesBasicGraph() {
        BlastRadiusService.setDependencyProviderForTest(
            new FakeDependencyProvider(new Map<String, List<DependencyService.DependencyRecord>>{
                key('Custom Field', 'Account.MyField__c') => new List<DependencyService.DependencyRecord>{
                    rec('301A', 'FlowUsage', 'Flow'),
                    rec('01pA', 'ClassUsage', 'ApexClass')
                },
                key('Flow', 'FlowUsage') => new List<DependencyService.DependencyRecord>{
                    rec('01qA', 'TriggerUsage', 'ApexTrigger')
                },
                key('Apex Class', 'ClassUsage') => new List<DependencyService.DependencyRecord>(),
                key('ApexTrigger', 'TriggerUsage') => new List<DependencyService.DependencyRecord>()
            }, false)
        );

        try {
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
        } finally {
            BlastRadiusService.resetDependencyProviderForTest();
        }
    }

    @IsTest
    static void getBlastRadius_marksCycleNodes() {
        BlastRadiusService.setDependencyProviderForTest(
            new FakeDependencyProvider(new Map<String, List<DependencyService.DependencyRecord>>{
                key('Flow', 'CycleRoot') => new List<DependencyService.DependencyRecord>{
                    rec('301CC', 'CycleChild', 'Flow')
                },
                key('Flow', 'CycleChild') => new List<DependencyService.DependencyRecord>{
                    rec('301CR', 'CycleRoot', 'FlowDefinition')
                }
            }, false)
        );

        try {
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
        } finally {
            BlastRadiusService.resetDependencyProviderForTest();
        }
    }

    @IsTest
    static void getBlastRadius_enforcesDepthLimit() {
        BlastRadiusService.setDependencyProviderForTest(
            new FakeDependencyProvider(new Map<String, List<DependencyService.DependencyRecord>>{
                key('Flow', 'DepthRoot') => new List<DependencyService.DependencyRecord>{
                    rec('301D1', 'DepthL1', 'Flow')
                },
                key('Flow', 'DepthL1') => new List<DependencyService.DependencyRecord>{
                    rec('301D2', 'DepthL2', 'Flow')
                },
                key('Flow', 'DepthL2') => new List<DependencyService.DependencyRecord>{
                    rec('301D3', 'DepthL3', 'Flow')
                }
            }, false)
        );

        try {
            Test.startTest();
            BlastRadiusService.BlastRadiusResponse response = BlastRadiusService.getBlastRadius('Flow', 'DepthRoot', 2);
            Test.stopTest();

            System.assertNotEquals(null, findNode(response.nodes, 'DepthL1'));
            System.assertNotEquals(null, findNode(response.nodes, 'DepthL2'));
            System.assertEquals(null, findNode(response.nodes, 'DepthL3'));
            System.assertEquals(2, response.totalDepth);
        } finally {
            BlastRadiusService.resetDependencyProviderForTest();
        }
    }

    @IsTest
    static void getBlastRadius_stopsAtNodeCap() {
        List<DependencyService.DependencyRecord> rootChildren = new List<DependencyService.DependencyRecord>();
        for (Integer i = 0; i < 501; i++) {
            rootChildren.add(rec('01pNC' + String.valueOf(i), 'NodeCapChild' + String.valueOf(i), 'ApexClass'));
        }

        BlastRadiusService.setDependencyProviderForTest(
            new FakeDependencyProvider(new Map<String, List<DependencyService.DependencyRecord>>{
                key('Flow', 'NodeCapRoot') => rootChildren
            }, false)
        );

        try {
            Test.startTest();
            BlastRadiusService.BlastRadiusResponse response = BlastRadiusService.getBlastRadius('Flow', 'NodeCapRoot', 1);
            Test.stopTest();

            System.assertEquals(true, response.limitReached);
            System.assert(response.stats.totalNodes > 1, 'Expected multiple nodes, got: ' + response.stats.totalNodes);
            System.assert(response.stats.totalNodes <= 500, 'Expected at most 500 nodes');
            System.assert(response.warningMessage != null);
            System.assert(response.warningMessage.contains('limit reached'));
        } finally {
            BlastRadiusService.resetDependencyProviderForTest();
        }
    }

    @IsTest
    static void getBlastRadius_addsWarningWhenDependencyLookupFails() {
        BlastRadiusService.setDependencyProviderForTest(new FakeDependencyProvider(
            new Map<String, List<DependencyService.DependencyRecord>>(),
            true
        ));

        try {
            Test.startTest();
            BlastRadiusService.BlastRadiusResponse response = BlastRadiusService.getBlastRadius('Flow', 'ErrorRoot', 3);
            Test.stopTest();

            System.assertEquals(false, response.limitReached);
            System.assertEquals(1, response.stats.totalNodes);
            System.assertEquals(0, response.stats.totalEdges);
            System.assertNotEquals(null, response.warningMessage);
            System.assert(response.warningMessage.contains('Could not fetch dependents for ErrorRoot'));
        } finally {
            BlastRadiusService.resetDependencyProviderForTest();
        }
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

    private static String key(String metadataType, String componentName) {
        return metadataType + '|' + componentName;
    }

    private static DependencyService.DependencyRecord rec(String idValue, String name, String type) {
        DependencyService.DependencyRecord record = new DependencyService.DependencyRecord();
        record.metadataComponentId = idValue;
        record.metadataComponentName = name;
        record.metadataComponentType = type;
        record.metadataComponentNamespace = null;
        record.refMetadataComponentName = null;
        record.refMetadataComponentType = null;
        record.accessType = null;
        record.setupUrl = null;
        record.isSubflowReference = false;
        return record;
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

    private class FakeDependencyProvider implements BlastRadiusService.BlastRadiusDependencyProvider {
        private final Map<String, List<DependencyService.DependencyRecord>> recordsByKey;
        private final Boolean shouldThrow;

        FakeDependencyProvider(Map<String, List<DependencyService.DependencyRecord>> recordsByKey, Boolean shouldThrow) {
            this.recordsByKey = recordsByKey == null
                ? new Map<String, List<DependencyService.DependencyRecord>>()
                : recordsByKey;
            this.shouldThrow = shouldThrow;
        }

        public List<DependencyService.DependencyRecord> search(String metadataType, String componentName) {
            if (shouldThrow == true) {
                throw new BlastRadiusService.BlastRadiusServiceException('Tooling API request failed: boom');
            }
            String searchKey = key(metadataType, componentName);
            if (!recordsByKey.containsKey(searchKey)) {
                return new List<DependencyService.DependencyRecord>();
            }
            return recordsByKey.get(searchKey);
        }
    }
}
