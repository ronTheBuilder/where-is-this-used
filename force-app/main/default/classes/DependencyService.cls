public with sharing class DependencyService {
    private static final String NAMED_CREDENTIAL = 'callout:WITU_ToolingAPI';
    private static final String TOOLING_BASE_PATH = '/services/data/v65.0/tooling';
    private static final Integer MAX_DEPENDENCY_ROWS = 2000;
    private static final Integer MAX_FLOW_SCAN = 200;

    public class DependencyServiceException extends Exception {}

    public class ToolingQueryResponse {
        public List<Object> records = new List<Object>();
        public Boolean done;
        public Integer totalSize;
        public String nextRecordsUrl;
        public Boolean limitReached = false;
    }

    public class MetadataOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public MetadataOption(String label, String value) {
            this.label = label;
            this.value = value;
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

    // ═══════════════════════════════════════
    // Security: Custom Permission gate
    // ═══════════════════════════════════════
    private static final String CUSTOM_PERMISSION = 'WITU_Access';
    private static final Integer MAX_COMPONENT_NAME_LENGTH = 255;
    // Whitelist: only allow alphanumeric, dots, underscores (valid SF metadata names)
    private static final Pattern VALID_COMPONENT_NAME = Pattern.compile('^[a-zA-Z][a-zA-Z0-9_.]*$');

    @TestVisible
    private static void enforceAccess() {
        if (!FeatureManagement.checkPermission(CUSTOM_PERMISSION)) {
            throw new DependencyServiceException(
                'Insufficient permissions. The custom permission "' + CUSTOM_PERMISSION + '" is required. ' +
                'Ask your admin to assign the "Where Is This Used? User" permission set.'
            );
        }
    }

    private static void validateComponentName(String componentName) {
        if (String.isBlank(componentName)) {
            throw new DependencyServiceException('Component name is required.');
        }
        String trimmed = componentName.trim();
        if (trimmed.length() > MAX_COMPONENT_NAME_LENGTH) {
            throw new DependencyServiceException('Component name exceeds maximum length.');
        }
        if (!VALID_COMPONENT_NAME.matcher(trimmed).matches()) {
            throw new DependencyServiceException('Component name contains invalid characters. Only letters, numbers, dots, and underscores are allowed.');
        }
    }

    public static List<String> getSupportedMetadataTypes() {
        return new List<String>{ 'Standard Field', 'Custom Field', 'Flow', 'Apex Class' };
    }

    public static DependencySearchResponse searchDependencies(String metadataType, String componentName) {
        enforceAccess();

        if (String.isBlank(metadataType) || String.isBlank(componentName)) {
            throw new DependencyServiceException('Metadata type and component name are required.');
        }

        String refType = getRefMetadataType(metadataType);
        if (refType == null) {
            throw new DependencyServiceException('This metadata type is not yet supported.');
        }

        validateComponentName(componentName);
        String escapedName = String.escapeSingleQuotes(componentName.trim());
        String soql =
            'SELECT MetadataComponentId, MetadataComponentName, MetadataComponentType, MetadataComponentNamespace, ' +
            'RefMetadataComponentName, RefMetadataComponentType ' +
            'FROM MetadataComponentDependency ' +
            'WHERE RefMetadataComponentName = \'' + escapedName + '\' ' +
            'AND RefMetadataComponentType = \'' + String.escapeSingleQuotes(refType) + '\' ' +
            'ORDER BY MetadataComponentType, MetadataComponentName';

        ToolingQueryResponse dependencyQuery = queryToolingRecords(soql, MAX_DEPENDENCY_ROWS);
        List<DependencyRecord> flattened = parseDependencyRecords(dependencyQuery.records, componentName, refType);

        if (metadataType == 'Flow') {
            flattened.addAll(findSubflowUsages(componentName));
        }

        DependencySearchResponse response = new DependencySearchResponse();
        response.metadataType = metadataType;
        response.componentName = componentName;
        response.totalCount = flattened.size();
        response.limitReached = dependencyQuery.limitReached;
        response.warningMessage = dependencyQuery.limitReached
            ? 'Showing first 2,000 results. There may be additional dependencies not displayed.'
            : null;
        response.groups = groupByComponentType(flattened);
        return response;
    }

    public static List<MetadataOption> getActiveFlows() {
        enforceAccess();
        String soql =
            'SELECT Id, FlowDefinitionView.ApiName, FlowDefinitionView.Label ' +
            'FROM FlowVersionView ' +
            'WHERE Status = \'Active\' ' +
            'ORDER BY FlowDefinitionView.Label';
        ToolingQueryResponse queryResponse = queryToolingRecords(soql, MAX_DEPENDENCY_ROWS);

        Map<String, MetadataOption> unique = new Map<String, MetadataOption>();
        for (Object recordObj : queryResponse.records) {
            Map<String, Object> record = asMap(recordObj);
            Map<String, Object> flowDefView = asMap(record.get('FlowDefinitionView'));
            if (flowDefView == null) {
                continue;
            }

            String apiName = String.valueOf(flowDefView.get('ApiName'));
            if (String.isBlank(apiName)) {
                continue;
            }

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

    public static List<MetadataOption> getApexClasses() {
        enforceAccess();
        String soql = 'SELECT Id, Name FROM ApexClass ORDER BY Name';
        ToolingQueryResponse queryResponse = queryToolingRecords(soql, MAX_DEPENDENCY_ROWS);

        List<MetadataOption> options = new List<MetadataOption>();
        for (Object recordObj : queryResponse.records) {
            Map<String, Object> record = asMap(recordObj);
            String name = String.valueOf(record.get('Name'));
            if (!String.isBlank(name)) {
                options.add(new MetadataOption(name, name));
            }
        }
        return options;
    }

    public static Boolean testConnection() {
        enforceAccess();
        ToolingQueryResponse queryResponse = queryToolingRecords('SELECT Id FROM Organization LIMIT 1', 1);
        return !queryResponse.records.isEmpty();
    }

    @TestVisible
    private static List<DependencyRecord> findSubflowUsages(String flowApiName) {
        if (String.isBlank(flowApiName)) {
            return new List<DependencyRecord>();
        }

        validateComponentName(flowApiName);
        String escapedName = String.escapeSingleQuotes(flowApiName.trim());
        String soql =
            'SELECT Id, FlowDefinitionView.ApiName, FlowDefinitionView.Label ' +
            'FROM FlowVersionView ' +
            'WHERE Status = \'Active\' ' +
            'AND FlowDefinitionView.ApiName != \'' + escapedName + '\' ' +
            'ORDER BY FlowDefinitionView.ApiName';

        ToolingQueryResponse flowQuery = queryToolingRecords(soql, MAX_FLOW_SCAN);
        List<DependencyRecord> subflowRecords = new List<DependencyRecord>();

        for (Object recordObj : flowQuery.records) {
            Map<String, Object> record = asMap(recordObj);
            String flowVersionId = String.valueOf(record.get('Id'));
            if (String.isBlank(flowVersionId)) {
                continue;
            }

            Map<String, Object> flowDefView = asMap(record.get('FlowDefinitionView'));
            String parentApiName = flowDefView == null ? null : String.valueOf(flowDefView.get('ApiName'));
            String parentLabel = flowDefView == null ? null : String.valueOf(flowDefView.get('Label'));

            Map<String, Object> flowMetadata = getFlowMetadata(flowVersionId);
            if (containsFlowReference(flowMetadata, flowApiName)) {
                DependencyRecord dep = new DependencyRecord();
                dep.metadataComponentId = flowVersionId;
                dep.metadataComponentName = String.isBlank(parentLabel) ? parentApiName : parentLabel;
                dep.metadataComponentType = 'Flow';
                dep.metadataComponentNamespace = null;
                dep.refMetadataComponentName = flowApiName;
                dep.refMetadataComponentType = 'Flow';
                dep.accessType = 'Read';
                dep.setupUrl = '/lightning/setup/Flows/home';
                dep.isSubflowReference = true;
                subflowRecords.add(dep);
            }
        }

        return subflowRecords;
    }

    private static Map<String, Object> getFlowMetadata(String flowVersionId) {
        HttpResponse response = sendGet(TOOLING_BASE_PATH + '/sobjects/Flow/' + flowVersionId);
        Map<String, Object> payload = asMap(JSON.deserializeUntyped(response.getBody()));
        return asMap(payload.get('Metadata'));
    }

    private static ToolingQueryResponse queryToolingRecords(String soql, Integer maxRows) {
        ToolingQueryResponse aggregate = new ToolingQueryResponse();
        String path = TOOLING_BASE_PATH + '/query/?q=' + EncodingUtil.urlEncode(soql, 'UTF-8');

        while (path != null) {
            HttpResponse response = sendGet(path);
            Map<String, Object> payload = asMap(JSON.deserializeUntyped(response.getBody()));
            List<Object> records = asList(payload.get('records'));
            if (records != null) {
                for (Object item : records) {
                    if (aggregate.records.size() >= maxRows) {
                        aggregate.limitReached = true;
                        aggregate.done = false;
                        aggregate.nextRecordsUrl = String.valueOf(payload.get('nextRecordsUrl'));
                        return aggregate;
                    }
                    aggregate.records.add(item);
                }
            }

            aggregate.done = payload.get('done') == null ? true : (Boolean) payload.get('done');
            aggregate.totalSize = payload.get('totalSize') == null ? aggregate.records.size() : Integer.valueOf(String.valueOf(payload.get('totalSize')));
            aggregate.nextRecordsUrl = payload.get('nextRecordsUrl') == null ? null : String.valueOf(payload.get('nextRecordsUrl'));

            if (aggregate.done == true || String.isBlank(aggregate.nextRecordsUrl)) {
                break;
            }
            path = aggregate.nextRecordsUrl;
        }

        return aggregate;
    }

    private static HttpResponse sendGet(String path) {
        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        request.setTimeout(120000);
        request.setEndpoint(resolveEndpoint(path));

        HttpResponse response = new Http().send(request);
        Integer status = response.getStatusCode();
        if (status < 200 || status >= 300) {
            // Log full error for debugging but don't expose raw API response to users
            System.debug(LoggingLevel.ERROR, 'Tooling API error (' + status + '): ' + response.getBody());

            String userMessage;
            if (status == 401 || status == 403) {
                userMessage = 'Authentication failed. Please verify your Named Credential (WITU_ToolingAPI) is configured correctly.';
            } else if (status == 404) {
                userMessage = 'Tooling API endpoint not found. Please verify your org\'s API version supports this feature.';
            } else if (status == 429) {
                userMessage = 'API rate limit exceeded. Please wait a moment and try again.';
            } else {
                userMessage = 'Tooling API request failed (HTTP ' + status + '). Check Setup > Debug Logs for details.';
            }
            throw new DependencyServiceException(userMessage);
        }
        return response;
    }

    private static String resolveEndpoint(String path) {
        if (String.isBlank(path)) {
            throw new DependencyServiceException('Tooling API path cannot be empty.');
        }

        if (path.startsWith('/services/')) {
            return NAMED_CREDENTIAL + path;
        }
        return NAMED_CREDENTIAL + path;
    }

    private static String getRefMetadataType(String metadataType) {
        Map<String, String> refTypes = new Map<String, String>{
            'Standard Field' => 'StandardEntity',
            'Custom Field' => 'CustomField',
            'Flow' => 'Flow',
            'Apex Class' => 'ApexClass'
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
            Map<String, Object> row = asMap(recordObj);
            if (row == null) {
                continue;
            }

            DependencyRecord dep = new DependencyRecord();
            dep.metadataComponentId = String.valueOf(row.get('MetadataComponentId'));
            dep.metadataComponentName = String.valueOf(row.get('MetadataComponentName'));
            dep.metadataComponentType = String.valueOf(row.get('MetadataComponentType'));
            dep.metadataComponentNamespace = row.get('MetadataComponentNamespace') == null
                ? null
                : String.valueOf(row.get('MetadataComponentNamespace'));
            dep.refMetadataComponentName = refComponentName;
            dep.refMetadataComponentType = refComponentType;
            dep.accessType = inferAccessType(dep.metadataComponentType);
            dep.setupUrl = buildSetupUrl(dep.metadataComponentType);
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

    private static String buildSetupUrl(String metadataComponentType) {
        if (String.isBlank(metadataComponentType)) {
            return '/lightning/setup/home';
        }

        Map<String, String> setupRoutes = new Map<String, String>{
            'ApexClass' => '/lightning/setup/ApexClasses/home',
            'ApexTrigger' => '/lightning/setup/ApexTriggers/home',
            'Flow' => '/lightning/setup/Flows/home',
            'ValidationRule' => '/lightning/setup/ObjectManager/home',
            'Layout' => '/lightning/setup/ObjectManager/home',
            'LightningComponentBundle' => '/lightning/setup/LightningComponentBundles/home',
            'AuraDefinitionBundle' => '/lightning/setup/AuraDefinitionBundles/home'
        };

        return setupRoutes.containsKey(metadataComponentType)
            ? setupRoutes.get(metadataComponentType)
            : '/lightning/setup/home';
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

    private static Map<String, Object> asMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : null;
    }

    private static List<Object> asList(Object value) {
        return value instanceof List<Object> ? (List<Object>) value : null;
    }
}
