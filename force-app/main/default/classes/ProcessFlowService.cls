public with sharing class ProcessFlowService {
    private static final String NAMED_CREDENTIAL = 'callout:WITU_ToolingAPI';
    private static final String TOOLING_BASE_PATH = '/services/data/v65.0/tooling';
    private static final String CUSTOM_PERMISSION = 'WITU_Access';

    private static final Integer MAX_TRIGGERS = 50;
    private static final Integer MAX_VALIDATION_RULES = 200;
    private static final Integer MAX_FLOWS = 100;
    private static final Integer MAX_OBJECT_NAME_LENGTH = 80;

    private static final Pattern VALID_OBJECT_NAME = Pattern.compile('^[a-zA-Z][a-zA-Z0-9_]*$');

    @TestVisible
    private static Boolean bypassAccessCheckForTests = false;

    public class ProcessFlowServiceException extends Exception {}

    public class ToolingQueryResponse {
        public List<Object> records = new List<Object>();
        public Boolean done;
        public Integer totalSize;
        public String nextRecordsUrl;
        public Boolean limitReached = false;
    }

    public class PhaseDefinition {
        public Integer phaseNumber;
        public String phaseName;
        public String phaseDescription;

        public PhaseDefinition(Integer phaseNumber, String phaseName, String phaseDescription) {
            this.phaseNumber = phaseNumber;
            this.phaseName = phaseName;
            this.phaseDescription = phaseDescription;
        }
    }

    public class AutomationStep {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String automationType;
        @AuraEnabled public Integer executionPhase;
        @AuraEnabled public String phaseName;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public String triggerContext;
        @AuraEnabled public String description;
        @AuraEnabled public String setupUrl;
        @AuraEnabled public List<String> fieldsReferenced;
        @AuraEnabled public List<String> fieldsModified;
    }

    public class AutomationPhase {
        @AuraEnabled public Integer phaseNumber;
        @AuraEnabled public String phaseName;
        @AuraEnabled public String phaseDescription;
        @AuraEnabled public List<AutomationStep> steps;
    }

    public class ProcessFlowResponse {
        @AuraEnabled public String objectName;
        @AuraEnabled public String triggerContext;
        @AuraEnabled public List<AutomationPhase> phases;
        @AuraEnabled public Integer totalAutomations;
        @AuraEnabled public List<String> warnings;
    }

    private static final List<PhaseDefinition> EXECUTION_ORDER = new List<PhaseDefinition>{
        new PhaseDefinition(1, 'System Validations', 'Required fields, field formats, max length'),
        new PhaseDefinition(2, 'Before Triggers', 'Apex before insert/update/delete triggers'),
        new PhaseDefinition(3, 'Custom Validation Rules', 'Active validation rules on the object'),
        new PhaseDefinition(4, 'After Triggers', 'Apex after insert/update/delete/undelete triggers'),
        new PhaseDefinition(5, 'Assignment Rules', 'Lead and Case assignment rules'),
        new PhaseDefinition(6, 'Auto-Response Rules', 'Lead and Case auto-response rules'),
        new PhaseDefinition(7, 'Before-Save Flows', 'Record-triggered flows (before save)'),
        new PhaseDefinition(8, 'Workflow Rules', 'Legacy workflow rules and immediate actions'),
        new PhaseDefinition(9, 'Workflow Field Updates', 'Field updates from workflow rules (may re-trigger)'),
        new PhaseDefinition(10, 'After-Save Flows', 'Record-triggered flows (after save)'),
        new PhaseDefinition(11, 'Entitlement Rules', 'Entitlement and milestone processing'),
        new PhaseDefinition(12, 'Async Flows', 'Record-triggered flows (run asynchronously)')
    };

    public static ProcessFlowResponse getProcessFlow(String objectName, String triggerContext) {
        enforceAccess();

        String normalizedObject = validateObjectName(objectName);
        String normalizedContext = normalizeTriggerContext(triggerContext);

        ProcessFlowResponse response = new ProcessFlowResponse();
        response.objectName = normalizedObject;
        response.triggerContext = normalizedContext;
        response.warnings = new List<String>();

        Map<Integer, AutomationPhase> phaseMap = initializePhases();

        loadTriggers(normalizedObject, normalizedContext, phaseMap, response.warnings);
        loadValidationRules(normalizedObject, normalizedContext, phaseMap);
        loadRecordTriggeredFlows(normalizedObject, normalizedContext, phaseMap, response.warnings);

        response.phases = toOrderedPhaseList(phaseMap);
        response.totalAutomations = countSteps(response.phases);
        return response;
    }

    @TestVisible
    private static void enforceAccess() {
        if (Test.isRunningTest() && bypassAccessCheckForTests) {
            return;
        }
        if (!FeatureManagement.checkPermission(CUSTOM_PERMISSION)) {
            throw new ProcessFlowServiceException(
                'Insufficient permissions. The custom permission "' + CUSTOM_PERMISSION + '" is required. ' +
                'Ask your admin to assign the "Where Is This Used? User" permission set.'
            );
        }
    }

    private static String validateObjectName(String objectName) {
        if (String.isBlank(objectName)) {
            throw new ProcessFlowServiceException('Object API name is required.');
        }

        String trimmed = objectName.trim();
        if (trimmed.length() > MAX_OBJECT_NAME_LENGTH) {
            throw new ProcessFlowServiceException('Object API name exceeds maximum length.');
        }
        if (!VALID_OBJECT_NAME.matcher(trimmed).matches()) {
            throw new ProcessFlowServiceException('Object API name contains invalid characters.');
        }
        return trimmed;
    }

    private static String normalizeTriggerContext(String triggerContext) {
        String normalized = String.isBlank(triggerContext) ? 'All' : triggerContext.trim();
        Set<String> allowed = new Set<String>{ 'Insert', 'Update', 'Delete', 'All' };
        if (!allowed.contains(normalized)) {
            throw new ProcessFlowServiceException('Trigger context must be Insert, Update, Delete, or All.');
        }
        return normalized;
    }

    private static Map<Integer, AutomationPhase> initializePhases() {
        Map<Integer, AutomationPhase> phaseMap = new Map<Integer, AutomationPhase>();
        for (PhaseDefinition definition : EXECUTION_ORDER) {
            AutomationPhase phase = new AutomationPhase();
            phase.phaseNumber = definition.phaseNumber;
            phase.phaseName = definition.phaseName;
            phase.phaseDescription = definition.phaseDescription;
            phase.steps = new List<AutomationStep>();
            phaseMap.put(phase.phaseNumber, phase);
        }
        return phaseMap;
    }

    private static List<AutomationPhase> toOrderedPhaseList(Map<Integer, AutomationPhase> phaseMap) {
        List<AutomationPhase> ordered = new List<AutomationPhase>();
        for (PhaseDefinition definition : EXECUTION_ORDER) {
            ordered.add(phaseMap.get(definition.phaseNumber));
        }
        return ordered;
    }

    private static Integer countSteps(List<AutomationPhase> phases) {
        Integer total = 0;
        for (AutomationPhase phase : phases) {
            total += phase.steps.size();
        }
        return total;
    }

    private static void loadTriggers(
        String objectName,
        String triggerContext,
        Map<Integer, AutomationPhase> phaseMap,
        List<String> warnings
    ) {
        String soql =
            'SELECT Id, Name, TableEnumOrId, UsageBeforeInsert, UsageAfterInsert, UsageBeforeUpdate, UsageAfterUpdate, ' +
            'UsageBeforeDelete, UsageAfterDelete, UsageAfterUndelete, Status ' +
            'FROM ApexTrigger ' +
            'WHERE TableEnumOrId = \'' + String.escapeSingleQuotes(objectName) + '\'';

        ToolingQueryResponse queryResponse = queryToolingRecords(soql, MAX_TRIGGERS);
        if (queryResponse.limitReached) {
            warnings.add('Showing first ' + MAX_TRIGGERS + ' triggers due to API safety limits.');
        }

        for (Object recordObj : queryResponse.records) {
            Map<String, Object> row = asMap(recordObj);
            if (row == null) {
                continue;
            }

            String status = String.valueOf(row.get('Status'));
            String triggerName = String.valueOf(row.get('Name'));
            String triggerId = String.valueOf(row.get('Id'));

            List<String> beforeContexts = new List<String>();
            if (toBoolean(row.get('UsageBeforeInsert'))) {
                beforeContexts.add('Insert');
            }
            if (toBoolean(row.get('UsageBeforeUpdate'))) {
                beforeContexts.add('Update');
            }
            if (toBoolean(row.get('UsageBeforeDelete'))) {
                beforeContexts.add('Delete');
            }

            List<String> afterContexts = new List<String>();
            if (toBoolean(row.get('UsageAfterInsert'))) {
                afterContexts.add('Insert');
            }
            if (toBoolean(row.get('UsageAfterUpdate'))) {
                afterContexts.add('Update');
            }
            if (toBoolean(row.get('UsageAfterDelete'))) {
                afterContexts.add('Delete');
            }
            if (toBoolean(row.get('UsageAfterUndelete'))) {
                afterContexts.add('Undelete');
            }

            if (matchesContext(beforeContexts, triggerContext)) {
                phaseMap.get(2).steps.add(buildStep(
                    triggerId,
                    triggerName,
                    'BeforeTrigger',
                    2,
                    phaseMap.get(2).phaseName,
                    status == 'Active',
                    String.join(beforeContexts, ', '),
                    'Runs before DML commit for contexts: ' + String.join(beforeContexts, ', '),
                    '/lightning/setup/ApexTriggers/home'
                ));
            }

            if (matchesContext(afterContexts, triggerContext)) {
                phaseMap.get(4).steps.add(buildStep(
                    triggerId,
                    triggerName,
                    'AfterTrigger',
                    4,
                    phaseMap.get(4).phaseName,
                    status == 'Active',
                    String.join(afterContexts, ', '),
                    'Runs after record save logic for contexts: ' + String.join(afterContexts, ', '),
                    '/lightning/setup/ApexTriggers/home'
                ));
            }
        }
    }

    private static void loadValidationRules(
        String objectName,
        String triggerContext,
        Map<Integer, AutomationPhase> phaseMap
    ) {
        if (triggerContext == 'Delete') {
            return;
        }

        String soql =
            'SELECT Id, ValidationName, Active, ErrorConditionFormula, EntityDefinition.QualifiedApiName ' +
            'FROM ValidationRule ' +
            'WHERE EntityDefinition.QualifiedApiName = \'' + String.escapeSingleQuotes(objectName) + '\' ' +
            'AND Active = true';

        ToolingQueryResponse queryResponse = queryToolingRecords(soql, MAX_VALIDATION_RULES);
        for (Object recordObj : queryResponse.records) {
            Map<String, Object> row = asMap(recordObj);
            if (row == null) {
                continue;
            }

            String formula = String.valueOf(row.get('ErrorConditionFormula'));
            String setupUrl = '/lightning/setup/ObjectManager/' + objectName + '/ValidationRules/view';
            phaseMap.get(3).steps.add(buildStep(
                String.valueOf(row.get('Id')),
                String.valueOf(row.get('ValidationName')),
                'ValidationRule',
                3,
                phaseMap.get(3).phaseName,
                true,
                'Insert, Update',
                String.isBlank(formula) ? 'Validation rule condition not available.' : formula,
                setupUrl
            ));
        }
    }

    private static void loadRecordTriggeredFlows(
        String objectName,
        String triggerContext,
        Map<Integer, AutomationPhase> phaseMap,
        List<String> warnings
    ) {
        if (triggerContext == 'Delete') {
            // Delete-only filtering is supported for triggers today.
            return;
        }

        String soql =
            'SELECT Id, Status, VersionNumber, FlowDefinitionView.ApiName, FlowDefinitionView.Label, TriggerObjectOrEvent, TriggerType ' +
            'FROM FlowVersionView ' +
            'WHERE ProcessType = \'AutoLaunchedFlow\' ' +
            'AND Status = \'Active\'';

        ToolingQueryResponse queryResponse = queryToolingRecords(soql, MAX_FLOWS);
        if (queryResponse.limitReached) {
            warnings.add('Showing first ' + MAX_FLOWS + ' record-triggered flows due to API safety limits.');
        }

        for (Object recordObj : queryResponse.records) {
            Map<String, Object> row = asMap(recordObj);
            if (row == null || !matchesTriggerObject(row.get('TriggerObjectOrEvent'), objectName)) {
                continue;
            }

            String flowVersionId = String.valueOf(row.get('Id'));
            Map<String, Object> metadata = getFlowMetadata(flowVersionId);
            Integer phase = determineFlowPhase(row, metadata);
            if (phase == null) {
                warnings.add('Unable to determine flow execution phase for flow version ' + flowVersionId + '.');
                continue;
            }

            List<String> contexts = inferFlowContexts(metadata);
            if (!matchesContext(contexts, triggerContext)) {
                continue;
            }

            Map<String, Object> flowDefView = asMap(row.get('FlowDefinitionView'));
            String apiName = flowDefView == null ? null : String.valueOf(flowDefView.get('ApiName'));
            String label = flowDefView == null ? null : String.valueOf(flowDefView.get('Label'));
            String name = String.isBlank(label) ? apiName : label;

            String triggerType = String.valueOf(row.get('TriggerType'));
            if (String.isBlank(triggerType)) {
                triggerType = inferTriggerTypeFromMetadata(metadata);
            }

            phaseMap.get(phase).steps.add(buildStep(
                flowVersionId,
                name,
                phase == 7 ? 'Flow_BeforeSave' : (phase == 10 ? 'Flow_AfterSave' : 'Flow_Async'),
                phase,
                phaseMap.get(phase).phaseName,
                String.valueOf(row.get('Status')) == 'Active',
                String.join(contexts, ', '),
                buildFlowDescription(triggerType, metadata),
                '/lightning/setup/Flows/home'
            ));
        }
    }

    private static AutomationStep buildStep(
        String id,
        String name,
        String automationType,
        Integer executionPhase,
        String phaseName,
        Boolean isActive,
        String triggerContext,
        String description,
        String setupUrl
    ) {
        AutomationStep step = new AutomationStep();
        step.id = id;
        step.name = name;
        step.automationType = automationType;
        step.executionPhase = executionPhase;
        step.phaseName = phaseName;
        step.isActive = isActive;
        step.triggerContext = triggerContext;
        step.description = description;
        step.setupUrl = setupUrl;
        step.fieldsReferenced = new List<String>();
        step.fieldsModified = new List<String>();
        return step;
    }

    private static Boolean matchesTriggerObject(Object triggerObjectOrEvent, String objectName) {
        if (triggerObjectOrEvent == null || String.isBlank(objectName)) {
            return false;
        }

        if (triggerObjectOrEvent instanceof String) {
            return String.valueOf(triggerObjectOrEvent).toLowerCase() == objectName.toLowerCase();
        }

        Map<String, Object> triggerMap = asMap(triggerObjectOrEvent);
        if (triggerMap != null) {
            String qualified = String.valueOf(triggerMap.get('QualifiedApiName'));
            if (!String.isBlank(qualified) && qualified.toLowerCase() == objectName.toLowerCase()) {
                return true;
            }

            String developerName = String.valueOf(triggerMap.get('DeveloperName'));
            if (!String.isBlank(developerName) && developerName.toLowerCase() == objectName.toLowerCase()) {
                return true;
            }
        }

        return false;
    }

    private static Integer determineFlowPhase(Map<String, Object> row, Map<String, Object> metadata) {
        String triggerType = String.valueOf(row.get('TriggerType'));
        if (String.isBlank(triggerType)) {
            triggerType = inferTriggerTypeFromMetadata(metadata);
        }

        if (String.isBlank(triggerType)) {
            return null;
        }

        String normalized = triggerType.toLowerCase();
        if (normalized.contains('before')) {
            return 7;
        }
        if (normalized.contains('async')) {
            return 12;
        }
        if (normalized.contains('after')) {
            return 10;
        }
        return null;
    }

    private static String inferTriggerTypeFromMetadata(Map<String, Object> metadata) {
        if (metadata == null) {
            return null;
        }

        List<String> candidates = new List<String>();
        collectStringValues(metadata, 'triggerType', candidates);
        collectStringValues(metadata, 'recordTriggerType', candidates);
        collectStringValues(metadata, 'runAsynchronously', candidates);

        if (!candidates.isEmpty()) {
            for (String candidate : candidates) {
                if (String.isBlank(candidate)) {
                    continue;
                }
                String normalized = candidate.toLowerCase();
                if (normalized == 'true') {
                    return 'RecordAfterSaveAsync';
                }
                if (normalized.contains('before')) {
                    return candidate;
                }
                if (normalized.contains('after') || normalized.contains('async')) {
                    return candidate;
                }
            }
        }

        String serialized = JSON.serialize(metadata).toLowerCase();
        if (serialized.contains('before')) {
            return 'RecordBeforeSave';
        }
        if (serialized.contains('async')) {
            return 'RecordAfterSaveAsync';
        }
        if (serialized.contains('after')) {
            return 'RecordAfterSave';
        }
        return null;
    }

    private static List<String> inferFlowContexts(Map<String, Object> metadata) {
        List<String> contexts = new List<String>();
        if (metadata == null) {
            contexts.add('Insert');
            contexts.add('Update');
            return contexts;
        }

        String serialized = JSON.serialize(metadata).toLowerCase();
        if (serialized.contains('create') || serialized.contains('insert')) {
            contexts.add('Insert');
        }
        if (serialized.contains('update')) {
            contexts.add('Update');
        }
        if (serialized.contains('delete')) {
            contexts.add('Delete');
        }

        if (contexts.isEmpty()) {
            contexts.add('Insert');
            contexts.add('Update');
        }

        return contexts;
    }

    private static String buildFlowDescription(String triggerType, Map<String, Object> metadata) {
        String base = String.isBlank(triggerType)
            ? 'Record-triggered flow'
            : 'Record-triggered flow (' + triggerType + ')';

        if (metadata == null) {
            return base;
        }

        List<String> snippets = new List<String>();
        collectStringValues(metadata, 'label', snippets);
        collectStringValues(metadata, 'description', snippets);

        if (!snippets.isEmpty()) {
            return base + ': ' + snippets[0];
        }
        return base;
    }

    private static Boolean matchesContext(List<String> contexts, String requestedContext) {
        if (requestedContext == 'All') {
            return !contexts.isEmpty();
        }
        for (String context : contexts) {
            if (context == requestedContext) {
                return true;
            }
        }
        return false;
    }

    private static void collectStringValues(Object node, String keyName, List<String> output) {
        if (node == null) {
            return;
        }

        Map<String, Object> mapNode = asMap(node);
        if (mapNode != null) {
            for (String key : mapNode.keySet()) {
                Object value = mapNode.get(key);
                if (key.toLowerCase() == keyName.toLowerCase() && value != null) {
                    output.add(String.valueOf(value));
                }
                collectStringValues(value, keyName, output);
            }
            return;
        }

        List<Object> listNode = asList(node);
        if (listNode != null) {
            for (Object item : listNode) {
                collectStringValues(item, keyName, output);
            }
        }
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
            aggregate.totalSize = payload.get('totalSize') == null
                ? aggregate.records.size()
                : Integer.valueOf(String.valueOf(payload.get('totalSize')));
            aggregate.nextRecordsUrl = payload.get('nextRecordsUrl') == null
                ? null
                : String.valueOf(payload.get('nextRecordsUrl'));

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
            throw new ProcessFlowServiceException(userMessage);
        }
        return response;
    }

    private static String resolveEndpoint(String path) {
        if (String.isBlank(path)) {
            throw new ProcessFlowServiceException('Tooling API path cannot be empty.');
        }
        if (path.startsWith('/services/')) {
            return NAMED_CREDENTIAL + path;
        }
        return NAMED_CREDENTIAL + path;
    }

    private static Boolean toBoolean(Object value) {
        if (value == null) {
            return false;
        }
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        return String.valueOf(value).toLowerCase() == 'true';
    }

    private static Map<String, Object> asMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : null;
    }

    private static List<Object> asList(Object value) {
        return value instanceof List<Object> ? (List<Object>) value : null;
    }
}
