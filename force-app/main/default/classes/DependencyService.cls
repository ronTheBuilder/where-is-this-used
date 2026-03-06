public with sharing class DependencyService {
    private static final Integer MAX_DEPENDENCY_ROWS = 2000;
    private static final Integer MAX_FLOW_SCAN = 200;

    public class DependencyServiceException extends Exception {}

    public class MetadataOption implements Comparable {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public MetadataOption(String label, String value) {
            this.label = label;
            this.value = value;
        }

        public Integer compareTo(Object other) {
            MetadataOption o = (MetadataOption) other;
            String a = label == null ? '' : label.toLowerCase();
            String b = o.label == null ? '' : o.label.toLowerCase();
            return a.compareTo(b);
        }
    }

    public class DependencyRecord {
        @AuraEnabled public String metadataComponentId;
        @AuraEnabled public String metadataComponentName;
        @AuraEnabled public String metadataComponentType;
        @AuraEnabled public String metadataComponentNamespace;
        @AuraEnabled public String refMetadataComponentName;
        @AuraEnabled public String refMetadataComponentType;
        @AuraEnabled public String accessType;
        @AuraEnabled public String setupUrl;
        @AuraEnabled public Boolean isSubflowReference;
    }

    public class DependencyGroup {
        @AuraEnabled public String componentType;
        @AuraEnabled public Integer count;
        @AuraEnabled public List<DependencyRecord> records;
    }

    public class DependencySearchResponse {
        @AuraEnabled public String metadataType;
        @AuraEnabled public String componentName;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Boolean limitReached;
        @AuraEnabled public String warningMessage;
        @AuraEnabled public List<DependencyGroup> groups;
    }

    public static List<String> getSupportedMetadataTypes() {
        return new List<String>{
            'Standard Field', 'Custom Field', 'Flow', 'Apex Class',
            'Record Type', 'Custom Label', 'Platform Event',
            'Validation Rule', 'Custom Metadata Type'
        };
    }

    public static DependencySearchResponse searchDependencies(String metadataType, String componentName) {
        try {
            ToolingApiClient.enforceAccess();
        } catch (ToolingApiClient.ToolingApiClientException ex) {
            throw new DependencyServiceException(ex.getMessage());
        }

        if (String.isBlank(metadataType) || String.isBlank(componentName)) {
            throw new DependencyServiceException('Metadata type and component name are required.');
        }

        String refType = getRefMetadataType(metadataType);
        if (refType == null) {
            throw new DependencyServiceException('This metadata type is not yet supported.');
        }

        try {
            ToolingApiClient.validateComponentName(componentName);
        } catch (ToolingApiClient.ToolingApiClientException ex) {
            throw new DependencyServiceException(ex.getMessage());
        }
        String trimmedName = componentName.trim();

        // Standard Field: use ID-based query via FieldDefinition (Tooling API doesn't support RefMetadataComponentType = 'StandardEntity')
        if (metadataType == 'Standard Field') {
            return searchStandardFieldDependencies(trimmedName);
        }

        // Validation Rule uses reverse query direction
        if (metadataType == 'Validation Rule') {
            return searchReverseDependencies(metadataType, trimmedName, refType);
        }

        List<Object> filteredRecords = queryDependenciesWithFallback(refType, trimmedName);

        List<DependencyRecord> flattened = parseDependencyRecords(filteredRecords, trimmedName, refType);

        // Bug fix: try both 'Flow' and 'FlowDefinition'
        if (metadataType == 'Flow') {
            flattened.addAll(findSubflowUsages(componentName));
        }

        // Supplementary scan: Layouts & FlexiPages for field types
        // (MetadataComponentDependency doesn't track Layout→Field relationships)
        if (metadataType == 'Standard Field' || metadataType == 'Custom Field') {
            try {
                flattened.addAll(findLayoutsUsingField(trimmedName));
                flattened.addAll(findFlexiPagesUsingField(trimmedName));
            } catch (Exception ex) {
                // Non-fatal: layout/flexipage scan is supplementary
                System.debug(LoggingLevel.WARN, 'Layout/FlexiPage scan failed: ' + ex.getMessage());
            }
        }

        Boolean limitReached = filteredRecords.size() >= MAX_DEPENDENCY_ROWS;

        DependencySearchResponse response = new DependencySearchResponse();
        response.metadataType = metadataType;
        response.componentName = componentName;
        response.totalCount = flattened.size();
        response.limitReached = limitReached;
        response.warningMessage = limitReached
            ? 'Showing first 2,000 results. There may be additional dependencies not displayed.'
            : null;
        response.groups = groupByComponentType(flattened);
        return response;
    }

    /**
     * Reverse query: "what does component X reference?" (used for Validation Rules)
     */
    private static DependencySearchResponse searchReverseDependencies(String metadataType, String componentName, String toolingType) {
        String escapedType = String.escapeSingleQuotes(toolingType);

        String soql =
            'SELECT RefMetadataComponentId, RefMetadataComponentName, RefMetadataComponentType, ' +
            'RefMetadataComponentNamespace, MetadataComponentName ' +
            'FROM MetadataComponentDependency ' +
            'WHERE MetadataComponentType = \'' + escapedType + '\'';

        ToolingApiClient.ToolingQueryResponse queryResult = ToolingApiClient.queryToolingRecords(soql, MAX_DEPENDENCY_ROWS);

        // Client-side filter by MetadataComponentName
        List<DependencyRecord> results = new List<DependencyRecord>();
        for (Object recordObj : queryResult.records) {
            Map<String, Object> row = ToolingApiClient.asMap(recordObj);
            if (row == null) continue;
            String mcName = String.valueOf(row.get('MetadataComponentName'));
            if (mcName != null && mcName.equalsIgnoreCase(componentName)) {
                DependencyRecord dep = new DependencyRecord();
                dep.metadataComponentId = String.valueOf(row.get('RefMetadataComponentId'));
                dep.metadataComponentName = String.valueOf(row.get('RefMetadataComponentName'));
                dep.metadataComponentType = String.valueOf(row.get('RefMetadataComponentType'));
                dep.metadataComponentNamespace = row.get('RefMetadataComponentNamespace') == null
                    ? null : String.valueOf(row.get('RefMetadataComponentNamespace'));
                dep.refMetadataComponentName = componentName;
                dep.refMetadataComponentType = toolingType;
                dep.accessType = 'Read';
                dep.setupUrl = SetupUrlResolver.resolve(dep.metadataComponentType, dep.metadataComponentId, dep.metadataComponentName);
                dep.isSubflowReference = false;
                results.add(dep);
            }
        }

        DependencySearchResponse response = new DependencySearchResponse();
        response.metadataType = metadataType;
        response.componentName = componentName;
        response.totalCount = results.size();
        response.limitReached = queryResult.limitReached;
        response.warningMessage = queryResult.limitReached
            ? 'Showing first 2,000 results. There may be additional dependencies not displayed.'
            : null;
        response.groups = groupByComponentType(results);
        return response;
    }

    private static List<Object> queryDependenciesWithFallback(String refType, String componentName) {
        String selectFields =
            'MetadataComponentId, MetadataComponentName, MetadataComponentType, MetadataComponentNamespace, ' +
            'RefMetadataComponentName, RefMetadataComponentType';

        try {
            ToolingApiClient.ToolingQueryResponse result = ToolingApiClient.queryDependenciesWithNameFallback(
                selectFields, refType, componentName, MAX_DEPENDENCY_ROWS
            );
            return result.records;
        } catch (ToolingApiClient.ToolingApiClientException ex) {
            throw new DependencyServiceException(ex.getMessage());
        }
    }

    public static List<MetadataOption> getActiveFlows() {
        ToolingApiClient.enforceAccess();
        ToolingApiClient.ToolingQueryResponse queryResponse = ToolingApiClient.queryFlowVersionsWithFallback(
            null, 'Status = \'Active\'', MAX_DEPENDENCY_ROWS
        );

        Map<String, MetadataOption> unique = new Map<String, MetadataOption>();
        for (Object recordObj : queryResponse.records) {
            Map<String, Object> record = ToolingApiClient.asMap(recordObj);
            Map<String, Object> flowDefView = ToolingApiClient.asMap(record.get('FlowDefinitionView'));
            if (flowDefView == null) continue;

            String apiName = String.valueOf(flowDefView.get('ApiName'));
            if (String.isBlank(apiName)) continue;

            String label = String.valueOf(flowDefView.get('Label'));
            unique.put(apiName, new MetadataOption(String.isBlank(label) ? apiName : label, apiName));
        }

        List<String> keys = new List<String>(unique.keySet());
        keys.sort();
        List<MetadataOption> options = new List<MetadataOption>();
        for (String key : keys) {
            options.add(unique.get(key));
        }
        return options;
    }

    public static List<MetadataOption> getAllFlows() {
        ToolingApiClient.enforceAccess();
        ToolingApiClient.ToolingQueryResponse queryResponse = ToolingApiClient.queryFlowVersionsWithFallback(
            'Status, VersionNumber',
            'Status IN (\'Active\', \'Draft\', \'Obsolete\', \'InvalidDraft\')',
            MAX_DEPENDENCY_ROWS
        );

        // Deduplicate by ApiName — prefer Active version; include status in label
        Map<String, MetadataOption> unique = new Map<String, MetadataOption>();
        Map<String, String> bestStatus = new Map<String, String>();

        for (Object recordObj : queryResponse.records) {
            Map<String, Object> record = ToolingApiClient.asMap(recordObj);
            Map<String, Object> flowDefView = ToolingApiClient.asMap(record.get('FlowDefinitionView'));
            if (flowDefView == null) continue;

            String apiName = String.valueOf(flowDefView.get('ApiName'));
            if (String.isBlank(apiName)) continue;

            String label = String.valueOf(flowDefView.get('Label'));
            String status = record.get('Status') == null ? 'Unknown' : String.valueOf(record.get('Status'));

            Boolean replace = !unique.containsKey(apiName) || status == 'Active';
            if (replace) {
                String displayLabel = (String.isBlank(label) ? apiName : label) + ' [' + status + ']';
                unique.put(apiName, new MetadataOption(displayLabel, apiName));
                bestStatus.put(apiName, status);
            }
        }

        List<String> keys = new List<String>(unique.keySet());
        keys.sort();
        List<MetadataOption> options = new List<MetadataOption>();
        for (String key : keys) {
            options.add(unique.get(key));
        }
        return options;
    }

    public static List<MetadataOption> getApexClasses() {
        ToolingApiClient.enforceAccess();
        String soql = 'SELECT Id, Name FROM ApexClass WHERE NamespacePrefix = null';
        ToolingApiClient.ToolingQueryResponse queryResponse = ToolingApiClient.queryToolingRecords(soql, MAX_DEPENDENCY_ROWS);

        List<MetadataOption> options = new List<MetadataOption>();
        for (Object recordObj : queryResponse.records) {
            Map<String, Object> record = ToolingApiClient.asMap(recordObj);
            String name = String.valueOf(record.get('Name'));
            if (!String.isBlank(name)) {
                options.add(new MetadataOption(name, name));
            }
        }
        // Sort client-side (removed ORDER BY from SOQL for reliability)
        options.sort();
        return options;
    }

    public static List<MetadataOption> getRecordTypes(String objectName) {
        ToolingApiClient.enforceAccess();
        if (String.isBlank(objectName)) {
            return new List<MetadataOption>();
        }
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectName);
        if (sot == null) {
            return new List<MetadataOption>();
        }
        List<MetadataOption> options = new List<MetadataOption>();
        for (Schema.RecordTypeInfo rti : sot.getDescribe().getRecordTypeInfosByDeveloperName().values()) {
            if (rti.isMaster()) continue;
            options.add(new MetadataOption(rti.getName(), objectName + '.' + rti.getDeveloperName()));
        }
        return options;
    }

    public static List<MetadataOption> getCustomLabels() {
        ToolingApiClient.enforceAccess();
        String soql = 'SELECT Id, Name, Value FROM ExternalString';
        ToolingApiClient.ToolingQueryResponse queryResponse = ToolingApiClient.queryToolingRecords(soql, MAX_DEPENDENCY_ROWS);

        List<MetadataOption> options = new List<MetadataOption>();
        for (Object recordObj : queryResponse.records) {
            Map<String, Object> record = ToolingApiClient.asMap(recordObj);
            String name = String.valueOf(record.get('Name'));
            String value = String.valueOf(record.get('Value'));
            if (String.isBlank(name)) continue;
            String displayLabel = name;
            if (String.isNotBlank(value)) {
                displayLabel += ' (' + (value.length() > 50 ? value.substring(0, 50) + '...' : value) + ')';
            }
            options.add(new MetadataOption(displayLabel, name));
        }
        return options;
    }

    public static List<MetadataOption> getValidationRules(String objectName) {
        ToolingApiClient.enforceAccess();
        if (String.isBlank(objectName)) {
            return new List<MetadataOption>();
        }
        String escapedObj = String.escapeSingleQuotes(objectName);
        String soql =
            'SELECT Id, ValidationName, Active, EntityDefinition.QualifiedApiName ' +
            'FROM ValidationRule ' +
            'WHERE EntityDefinition.QualifiedApiName = \'' + escapedObj + '\'';
        ToolingApiClient.ToolingQueryResponse queryResponse = ToolingApiClient.queryToolingRecords(soql, 200);

        List<MetadataOption> options = new List<MetadataOption>();
        for (Object recordObj : queryResponse.records) {
            Map<String, Object> record = ToolingApiClient.asMap(recordObj);
            String vrName = String.valueOf(record.get('ValidationName'));
            Boolean isActive = record.get('Active') == null ? false : (Boolean) record.get('Active');
            if (String.isBlank(vrName)) continue;
            String displayLabel = vrName + (isActive ? ' [Active]' : ' [Inactive]');
            options.add(new MetadataOption(displayLabel, objectName + '.' + vrName));
        }
        return options;
    }

    public static List<MetadataOption> getPlatformEvents() {
        ToolingApiClient.enforceAccess();
        List<MetadataOption> options = new List<MetadataOption>();
        for (String objName : Schema.getGlobalDescribe().keySet()) {
            if (objName.endsWith('__e')) {
                Schema.SObjectType sot = Schema.getGlobalDescribe().get(objName);
                String label = sot.getDescribe().getLabel();
                options.add(new MetadataOption(label, objName));
            }
        }
        return options;
    }

    public static List<MetadataOption> getCustomMetadataTypes() {
        ToolingApiClient.enforceAccess();
        List<MetadataOption> options = new List<MetadataOption>();
        for (String objName : Schema.getGlobalDescribe().keySet()) {
            if (objName.endsWith('__mdt')) {
                Schema.SObjectType sot = Schema.getGlobalDescribe().get(objName);
                String label = sot.getDescribe().getLabel();
                options.add(new MetadataOption(label, objName));
            }
        }
        return options;
    }

    public static Boolean testConnection() {
        ToolingApiClient.enforceAccess();
        ToolingApiClient.ToolingQueryResponse queryResponse = ToolingApiClient.queryToolingRecords('SELECT Id FROM Organization LIMIT 1', 1);
        return !queryResponse.records.isEmpty();
    }

    /**
     * Scan Page Layouts for a field reference.
     * Field format: ObjectName.FieldName (e.g. Account.Industry)
     * Fetches each layout's metadata JSON and checks for the field API name.
     */
    private static final Integer MAX_LAYOUT_SCAN = 50;

    private static List<DependencyRecord> findLayoutsUsingField(String objectDotField) {
        List<DependencyRecord> results = new List<DependencyRecord>();
        if (String.isBlank(objectDotField) || !objectDotField.contains('.')) {
            return results;
        }

        String objectName = objectDotField.substringBefore('.');
        String fieldName = objectDotField.substringAfter('.');

        String soql = 'SELECT Id, Name, FullName FROM Layout WHERE TableEnumOrId = \'' +
            String.escapeSingleQuotes(objectName) + '\'';

        ToolingApiClient.ToolingQueryResponse layoutResult;
        try {
            layoutResult = ToolingApiClient.queryToolingRecords(soql, MAX_LAYOUT_SCAN);
        } catch (ToolingApiClient.ToolingApiClientException ex) {
            return results;
        }

        for (Object recordObj : layoutResult.records) {
            // Check remaining callout budget before fetching metadata
            if (Limits.getCallouts() >= Limits.getLimitCallouts() - 2) {
                break;
            }

            Map<String, Object> row = ToolingApiClient.asMap(recordObj);
            if (row == null) continue;

            String layoutId = String.valueOf(row.get('Id'));
            String layoutName = String.valueOf(row.get('Name'));
            if (String.isBlank(layoutId)) continue;

            try {
                Map<String, Object> fullRecord = ToolingApiClient.getToolingRecord('Layout', layoutId);
                if (fullRecord == null) continue;

                // Serialize metadata and check for field name (case-insensitive)
                String body = JSON.serialize(fullRecord);
                if (body != null && body.toLowerCase().contains('"' + fieldName.toLowerCase() + '"')) {
                    DependencyRecord dep = new DependencyRecord();
                    dep.metadataComponentId = layoutId;
                    dep.metadataComponentName = layoutName;
                    dep.metadataComponentType = 'Layout';
                    dep.refMetadataComponentName = objectDotField;
                    dep.refMetadataComponentType = 'Field';
                    dep.accessType = 'Layout Field';
                    dep.setupUrl = '/lightning/setup/ObjectManager/' + objectName + '/PageLayouts/view';
                    dep.isSubflowReference = false;
                    results.add(dep);
                }
            } catch (Exception ex) {
                // Skip individual layout errors
                System.debug(LoggingLevel.WARN, 'Layout scan error for ' + layoutId + ': ' + ex.getMessage());
            }
        }

        return results;
    }

    /**
     * Scan Lightning Record Pages (FlexiPages) for a field reference.
     */
    private static final Integer MAX_FLEXIPAGE_SCAN = 30;

    private static List<DependencyRecord> findFlexiPagesUsingField(String objectDotField) {
        List<DependencyRecord> results = new List<DependencyRecord>();
        if (String.isBlank(objectDotField) || !objectDotField.contains('.')) {
            return results;
        }

        String objectName = objectDotField.substringBefore('.');
        String fieldName = objectDotField.substringAfter('.');

        // FlexiPages linked to an object via SobjectType
        String soql = 'SELECT Id, DeveloperName, MasterLabel FROM FlexiPage WHERE SobjectType = \'' +
            String.escapeSingleQuotes(objectName) + '\'';

        ToolingApiClient.ToolingQueryResponse flexiResult;
        try {
            flexiResult = ToolingApiClient.queryToolingRecords(soql, MAX_FLEXIPAGE_SCAN);
        } catch (ToolingApiClient.ToolingApiClientException ex) {
            return results;
        }

        for (Object recordObj : flexiResult.records) {
            if (Limits.getCallouts() >= Limits.getLimitCallouts() - 2) {
                break;
            }

            Map<String, Object> row = ToolingApiClient.asMap(recordObj);
            if (row == null) continue;

            String pageId = String.valueOf(row.get('Id'));
            String pageName = String.valueOf(row.get('MasterLabel'));
            String devName = String.valueOf(row.get('DeveloperName'));
            if (String.isBlank(pageId)) continue;

            try {
                Map<String, Object> fullRecord = ToolingApiClient.getToolingRecord('FlexiPage', pageId);
                if (fullRecord == null) continue;

                String body = JSON.serialize(fullRecord);
                if (body != null && body.toLowerCase().contains('"' + fieldName.toLowerCase() + '"')) {
                    DependencyRecord dep = new DependencyRecord();
                    dep.metadataComponentId = pageId;
                    dep.metadataComponentName = String.isBlank(pageName) ? devName : pageName;
                    dep.metadataComponentType = 'FlexiPage';
                    dep.refMetadataComponentName = objectDotField;
                    dep.refMetadataComponentType = 'Field';
                    dep.accessType = 'Record Page Field';
                    dep.setupUrl = '/lightning/setup/ObjectManager/' + objectName + '/LightningPages/view';
                    dep.isSubflowReference = false;
                    results.add(dep);
                }
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN, 'FlexiPage scan error for ' + pageId + ': ' + ex.getMessage());
            }
        }

        return results;
    }

    @TestVisible
    private static List<DependencyRecord> findSubflowUsages(String flowApiName) {
        if (String.isBlank(flowApiName)) {
            return new List<DependencyRecord>();
        }

        ToolingApiClient.validateComponentName(flowApiName);
        String trimmedName = flowApiName.trim();

        ToolingApiClient.ToolingQueryResponse flowQuery = ToolingApiClient.queryFlowVersionsWithFallback(
            'ProcessType', 'Status = \'Active\'', MAX_FLOW_SCAN
        );
        List<DependencyRecord> subflowRecords = new List<DependencyRecord>();

        for (Object recordObj : flowQuery.records) {
            Map<String, Object> record = ToolingApiClient.asMap(recordObj);
            String flowVersionId = String.valueOf(record.get('Id'));
            if (String.isBlank(flowVersionId)) continue;

            Map<String, Object> flowDefView = ToolingApiClient.asMap(record.get('FlowDefinitionView'));
            String parentApiName = flowDefView == null ? null : String.valueOf(flowDefView.get('ApiName'));
            String parentLabel = flowDefView == null ? null : String.valueOf(flowDefView.get('Label'));

            // Skip the flow we're searching for
            if (parentApiName != null && parentApiName.equalsIgnoreCase(trimmedName)) continue;

            // Skip Screen Flows (they can't contain subflows)
            String processType = String.valueOf(record.get('ProcessType'));
            if (processType == 'Flow') continue; // 'Flow' = Screen Flow in SF terminology

            // Bug fix: wrap in try/catch to handle corrupted flow metadata
            Map<String, Object> flowMetadata;
            try {
                flowMetadata = ToolingApiClient.getFlowMetadata(flowVersionId);
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN, 'Skipping flow ' + parentApiName + ': ' + ex.getMessage());
                continue;
            }

            if (containsFlowReference(flowMetadata, trimmedName)) {
                DependencyRecord dep = new DependencyRecord();
                dep.metadataComponentId = flowVersionId;
                dep.metadataComponentName = String.isBlank(parentLabel) ? parentApiName : parentLabel;
                dep.metadataComponentType = 'Flow';
                dep.metadataComponentNamespace = null;
                dep.refMetadataComponentName = flowApiName;
                dep.refMetadataComponentType = 'Flow';
                dep.accessType = 'Read';
                dep.setupUrl = SetupUrlResolver.resolve('Flow', flowVersionId, parentApiName);
                dep.isSubflowReference = true;
                subflowRecords.add(dep);
            }
        }

        return subflowRecords;
    }


    private static String getRefMetadataType(String metadataType) {
        Map<String, String> refTypes = new Map<String, String>{
            'Standard Field' => 'StandardEntity',
            'Custom Field' => 'CustomField',
            'Flow' => 'FlowDefinition',
            'Apex Class' => 'ApexClass',
            'Record Type' => 'RecordType',
            'Custom Label' => 'CustomLabel',
            'Platform Event' => 'CustomObject',
            'Validation Rule' => 'ValidationRule',
            'Custom Metadata Type' => 'CustomObject'
        };
        return refTypes.get(metadataType);
    }

    private static List<DependencyRecord> parseDependencyRecords(
        List<Object> records,
        String refComponentName,
        String refComponentType
    ) {
        List<DependencyRecord> parsed = new List<DependencyRecord>();
        for (Object recordObj : records) {
            Map<String, Object> row = ToolingApiClient.asMap(recordObj);
            if (row == null) continue;

            DependencyRecord dep = new DependencyRecord();
            dep.metadataComponentId = String.valueOf(row.get('MetadataComponentId'));
            dep.metadataComponentName = String.valueOf(row.get('MetadataComponentName'));
            dep.metadataComponentType = String.valueOf(row.get('MetadataComponentType'));
            dep.metadataComponentNamespace = row.get('MetadataComponentNamespace') == null
                ? null : String.valueOf(row.get('MetadataComponentNamespace'));
            dep.refMetadataComponentName = refComponentName;
            dep.refMetadataComponentType = refComponentType;
            dep.accessType = inferAccessType(dep.metadataComponentType);
            dep.setupUrl = SetupUrlResolver.resolve(dep.metadataComponentType, dep.metadataComponentId, dep.metadataComponentName);
            dep.isSubflowReference = false;
            parsed.add(dep);
        }
        return parsed;
    }

    private static List<DependencyGroup> groupByComponentType(List<DependencyRecord> records) {
        Map<String, List<DependencyRecord>> grouped = new Map<String, List<DependencyRecord>>();

        for (DependencyRecord record : records) {
            String key = String.isBlank(record.metadataComponentType) ? 'Unknown' : record.metadataComponentType;
            if (!grouped.containsKey(key)) {
                grouped.put(key, new List<DependencyRecord>());
            }
            grouped.get(key).add(record);
        }

        List<String> types = new List<String>(grouped.keySet());
        types.sort();

        List<DependencyGroup> result = new List<DependencyGroup>();
        for (String type : types) {
            DependencyGroup grp = new DependencyGroup();
            grp.componentType = type;
            grp.records = grouped.get(type);
            grp.count = grp.records.size();
            result.add(grp);
        }
        return result;
    }

    private static String inferAccessType(String metadataComponentType) {
        if (metadataComponentType == 'ApexTrigger') {
            return 'Write';
        }
        if (metadataComponentType != null && metadataComponentType.startsWith('Apex')) {
            return 'Read';
        }
        return null;
    }

    private static Boolean containsFlowReference(Object metadataNode, String targetFlowApiName) {
        if (metadataNode == null || String.isBlank(targetFlowApiName)) {
            return false;
        }

        if (metadataNode instanceof Map<String, Object>) {
            Map<String, Object> node = (Map<String, Object>) metadataNode;
            if (node.containsKey('flowName')) {
                String flowName = String.valueOf(node.get('flowName'));
                if (!String.isBlank(flowName) && flowName.toLowerCase() == targetFlowApiName.toLowerCase()) {
                    return true;
                }
            }

            for (Object value : node.values()) {
                if (containsFlowReference(value, targetFlowApiName)) {
                    return true;
                }
            }
            return false;
        }

        if (metadataNode instanceof List<Object>) {
            for (Object item : (List<Object>) metadataNode) {
                if (containsFlowReference(item, targetFlowApiName)) {
                    return true;
                }
            }
        }

        return false;
    }
}
