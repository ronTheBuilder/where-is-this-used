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
        BlastRadiusService.setDependencyProviderForTest(
            new ControllerFakeProvider(new Map<String, List<DependencyService.DependencyRecord>>{
                key('Flow', 'RootFlow') => new List<DependencyService.DependencyRecord>{
                    rec('01pB', 'UsingClass', 'ApexClass')
                },
                key('Apex Class', 'UsingClass') => new List<DependencyService.DependencyRecord>()
            })
        );

        try {
            Test.startTest();
            BlastRadiusService.BlastRadiusResponse response = BlastRadiusController.getBlastRadius('Flow', 'RootFlow', 3);
            Test.stopTest();

            System.assertEquals(2, response.stats.totalNodes);
            System.assertEquals(1, response.stats.totalEdges);
            System.assertEquals(false, response.limitReached);
        } finally {
            BlastRadiusService.resetDependencyProviderForTest();
        }
    }

    @IsTest
    static void getBlastRadius_wrapsServiceException() {
        Boolean thrown = false;
        try {
            BlastRadiusController.getBlastRadius('Flow', 'Invalid Name!', 3);
        } catch (AuraHandledException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('invalid characters'));
        }

        System.assertEquals(true, thrown);
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

    private class ControllerFakeProvider implements BlastRadiusService.BlastRadiusDependencyProvider {
        private final Map<String, List<DependencyService.DependencyRecord>> recordsByKey;

        ControllerFakeProvider(Map<String, List<DependencyService.DependencyRecord>> recordsByKey) {
            this.recordsByKey = recordsByKey == null
                ? new Map<String, List<DependencyService.DependencyRecord>>()
                : recordsByKey;
        }

        public List<DependencyService.DependencyRecord> search(String metadataType, String componentName) {
            String searchKey = key(metadataType, componentName);
            if (!recordsByKey.containsKey(searchKey)) {
                return new List<DependencyService.DependencyRecord>();
            }
            return recordsByKey.get(searchKey);
        }
    }
}
