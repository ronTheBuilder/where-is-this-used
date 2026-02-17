public with sharing class DataJourneyService {
    private static final String NAMED_CREDENTIAL = 'callout:WITU_ToolingAPI';
    private static final String TOOLING_BASE_PATH = '/services/data/v65.0/tooling';

    private static final Integer MAX_DEPTH = 3;
    private static final Integer MAX_DEPENDENCY_ROWS = 2000;
    private static final Integer MAX_DOWNSTREAM_NODES = 200;
    private static final Integer MAX_UPSTREAM_NODES = 50;
    private static final Integer MAX_FLOW_METADATA_RETRIEVALS = 50;

    private static final String CUSTOM_PERMISSION = 'WITU_Access';
    private static final Integer MAX_NAME_LENGTH = 255;
    private static final Pattern VALID_NAME = Pattern.compile('^[a-zA-Z][a-zA-Z0-9_]*$');
    private static final Pattern VALID_FIELD = Pattern.compile('^[a-zA-Z][a-zA-Z0-9_]*(__c|__pc|__s)?$');

    public class DataJourneyServiceException extends Exception {}

    public class DataJourneyNode {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String nodeType;
        @AuraEnabled public String direction;
        @AuraEnabled public String accessType;
        @AuraEnabled public Integer depth;
        @AuraEnabled public String setupUrl;
        @AuraEnabled public String detail;
    }

    public class DataJourneyEdge {
        @AuraEnabled public String sourceId;
        @AuraEnabled public String targetId;
        @AuraEnabled public String relationship;
        @AuraEnabled public String detail;
    }

    public class DataJourneyResponse {
        @AuraEnabled public String fieldName;
        @AuraEnabled public String objectName;
        @AuraEnabled public List<DataJourneyNode> nodes;
        @AuraEnabled public List<DataJourneyEdge> edges;
        @AuraEnabled public List<String> warnings;
        @AuraEnabled public Boolean limitReached;
    }

    private class ToolingQueryResponse {
        public List<Object> records = new List<Object>();
        public Boolean done;
        public Integer totalSize;
        public String nextRecordsUrl;
        public Boolean limitReached = false;
    }

    private class DependencyHit {
        public String metadataComponentId;
        public String metadataComponentName;
        public String metadataComponentType;
        public String metadataComponentNamespace;
        public String accessType;
        public String setupUrl;
    }

    private class ActiveFlowVersion {
        public String id;
        public String apiName;
        public String label;
    }

    private class FieldHop {
        public String fieldApi;
        public Integer depth;

        public FieldHop(String fieldApi, Integer depth) {
            this.fieldApi = fieldApi;
            this.depth = depth;
        }
    }

    private class TraceContext {
        public Integer downstreamNodeCount = 0;
        public Integer upstreamNodeCount = 0;
        public Integer flowRetrievalCount = 0;
        public Boolean flowRetrievalLimitReached = false;
        public Set<String> warningSet = new Set<String>();
        public Map<String, FlowFieldAnalyzer.FlowFieldAnalysis> flowAnalysisByVersionId =
            new Map<String, FlowFieldAnalyzer.FlowFieldAnalysis>();
    }

    @TestVisible
    private static void enforceAccess() {
        if (!FeatureManagement.checkPermission(CUSTOM_PERMISSION)) {
            throw new DataJourneyServiceException(
                'Insufficient permissions. The custom permission "' + CUSTOM_PERMISSION + '" is required. ' +
                'Ask your admin to assign the "Where Is This Used? User" permission set.'
            );
        }
    }

    public static DataJourneyResponse traceDataJourney(String objectName, String fieldName, Integer maxDepth) {
        enforceAccess();
        Integer depth = sanitizeMaxDepth(maxDepth);
        String validatedObject = validateObjectName(objectName);
        String validatedField = validateFieldName(fieldName);

        DataJourneyResponse response = initializeResponse(validatedObject, validatedField);
        TraceContext context = new TraceContext();
        Map<String, DataJourneyNode> nodeIndex = new Map<String, DataJourneyNode>();
        Set<String> edgeIndex = new Set<String>();

        addOrMergeNode(response, nodeIndex, buildFieldNode(validatedObject, validatedField, 'root', 'readwrite', 0, null, null), context);
        traceDownstreamInternal(validatedObject, validatedField, depth, response, nodeIndex, edgeIndex, context);
        traceUpstreamInternal(validatedObject, validatedField, response, nodeIndex, edgeIndex, context);
        finalizeResponse(response, context);
        return response;
    }

    public static DataJourneyResponse traceDownstream(String objectName, String fieldName, Integer maxDepth) {
        enforceAccess();
        Integer depth = sanitizeMaxDepth(maxDepth);
        String validatedObject = validateObjectName(objectName);
        String validatedField = validateFieldName(fieldName);

        DataJourneyResponse response = initializeResponse(validatedObject, validatedField);
        TraceContext context = new TraceContext();
        Map<String, DataJourneyNode> nodeIndex = new Map<String, DataJourneyNode>();
        Set<String> edgeIndex = new Set<String>();

        addOrMergeNode(response, nodeIndex, buildFieldNode(validatedObject, validatedField, 'root', 'readwrite', 0, null, null), context);
        traceDownstreamInternal(validatedObject, validatedField, depth, response, nodeIndex, edgeIndex, context);
        finalizeResponse(response, context);
        return response;
    }

    public static DataJourneyResponse traceUpstream(String objectName, String fieldName, Integer maxDepth) {
        enforceAccess();
        String validatedObject = validateObjectName(objectName);
        String validatedField = validateFieldName(fieldName);

        DataJourneyResponse response = initializeResponse(validatedObject, validatedField);
        TraceContext context = new TraceContext();
        Map<String, DataJourneyNode> nodeIndex = new Map<String, DataJourneyNode>();
        Set<String> edgeIndex = new Set<String>();

        addOrMergeNode(response, nodeIndex, buildFieldNode(validatedObject, validatedField, 'root', 'readwrite', 0, null, null), context);
        traceUpstreamInternal(validatedObject, validatedField, response, nodeIndex, edgeIndex, context);
        finalizeResponse(response, context);
        return response;
    }

    private static void traceDownstreamInternal(
        String objectName,
        String fieldName,
        Integer maxDepth,
        DataJourneyResponse response,
        Map<String, DataJourneyNode> nodeIndex,
        Set<String> edgeIndex,
        TraceContext context
    ) {
        List<FieldHop> queue = new List<FieldHop>{ new FieldHop(buildFullFieldName(objectName, fieldName), 1) };
        Set<String> visitedFields = new Set<String>();

        while (!queue.isEmpty()) {
            FieldHop hop = queue.remove(0);
            String currentField = hop.fieldApi;
            if (String.isBlank(currentField) || hop.depth > maxDepth) {
                continue;
            }

            String currentKey = currentField.toLowerCase();
            if (visitedFields.contains(currentKey)) {
                continue;
            }
            visitedFields.add(currentKey);

            List<DependencyHit> dependencies = queryDependenciesForField(currentField);
            String currentObject = extractObjectName(currentField);
            String currentFieldOnly = extractFieldName(currentField);

            for (DependencyHit dependency : dependencies) {
                if (context.downstreamNodeCount >= MAX_DOWNSTREAM_NODES) {
                    addWarning(response, context, 'Downstream node limit reached (' + MAX_DOWNSTREAM_NODES + ').');
                    response.limitReached = true;
                    return;
                }

                if (String.isBlank(dependency.metadataComponentType) || String.isBlank(dependency.metadataComponentName)) {
                    continue;
                }

                DataJourneyNode componentNode = buildComponentNode(
                    dependency,
                    'downstream',
                    'read',
                    hop.depth,
                    null
                );
                Boolean addedComponent = addOrMergeNode(response, nodeIndex, componentNode, context);
                if (addedComponent && context.downstreamNodeCount > MAX_DOWNSTREAM_NODES) {
                    addWarning(response, context, 'Downstream node limit reached (' + MAX_DOWNSTREAM_NODES + ').');
                    response.limitReached = true;
                    return;
                }

                addEdge(
                    response,
                    edgeIndex,
                    buildFieldNodeId(currentField),
                    componentNode.id,
                    'read_by',
                    'Referenced via MetadataComponentDependency.'
                );

                if (dependency.metadataComponentType != 'Flow') {
                    continue;
                }

                FlowFieldAnalyzer.FlowFieldAnalysis analysis = getFlowAnalysisByVersionId(dependency.metadataComponentId, context, response);
                if (analysis == null || !analysisReadsField(analysis, currentObject, currentFieldOnly, currentField)) {
                    continue;
                }

                for (String writtenReference : analysis.fieldsWritten) {
                    if (context.downstreamNodeCount >= MAX_DOWNSTREAM_NODES) {
                        addWarning(response, context, 'Downstream node limit reached (' + MAX_DOWNSTREAM_NODES + ').');
                        response.limitReached = true;
                        return;
                    }

                    String canonicalWrittenField = canonicalizeFieldReference(writtenReference, currentObject);
                    if (String.isBlank(canonicalWrittenField)) {
                        continue;
                    }

                    DataJourneyNode writtenFieldNode = buildFieldNode(
                        extractObjectName(canonicalWrittenField),
                        extractFieldName(canonicalWrittenField),
                        'downstream',
                        'write',
                        hop.depth,
                        '/lightning/setup/ObjectManager/home',
                        'Field written by Flow assignment or record mutation.'
                    );
                    addOrMergeNode(response, nodeIndex, writtenFieldNode, context);

                    addEdge(
                        response,
                        edgeIndex,
                        componentNode.id,
                        writtenFieldNode.id,
                        'writes_to',
                        'Flow writes this field.'
                    );

                    if (hop.depth < maxDepth && canonicalWrittenField.toLowerCase() != currentKey) {
                        queue.add(new FieldHop(canonicalWrittenField, hop.depth + 1));
                    }
                }
            }
        }
    }

    private static void traceUpstreamInternal(
        String objectName,
        String fieldName,
        DataJourneyResponse response,
        Map<String, DataJourneyNode> nodeIndex,
        Set<String> edgeIndex,
        TraceContext context
    ) {
        String fullFieldName = buildFullFieldName(objectName, fieldName);

        List<ActiveFlowVersion> flows = queryActiveFlows();
        for (ActiveFlowVersion flow : flows) {
            if (context.upstreamNodeCount >= MAX_UPSTREAM_NODES) {
                addWarning(response, context, 'Upstream node limit reached (' + MAX_UPSTREAM_NODES + ').');
                response.limitReached = true;
                break;
            }

            FlowFieldAnalyzer.FlowFieldAnalysis analysis = getFlowAnalysisByVersionId(flow.id, context, response);
            if (analysis == null || !analysisWritesField(analysis, objectName, fieldName, fullFieldName)) {
                continue;
            }

            DependencyHit hit = new DependencyHit();
            hit.metadataComponentId = flow.id;
            hit.metadataComponentName = String.isBlank(flow.label) ? flow.apiName : flow.label;
            hit.metadataComponentType = 'Flow';
            hit.setupUrl = '/lightning/setup/Flows/home';

            DataJourneyNode flowNode = buildComponentNode(hit, 'upstream', 'write', 1, 'Flow writes to this field.');
            addOrMergeNode(response, nodeIndex, flowNode, context);
            addEdge(response, edgeIndex, flowNode.id, buildFieldNodeId(fullFieldName), 'writes_to', 'Flow assignment or record update.');
        }

        List<DependencyHit> dependencies = queryDependenciesForField(fullFieldName);
        for (DependencyHit dependency : dependencies) {
            if (context.upstreamNodeCount >= MAX_UPSTREAM_NODES) {
                addWarning(response, context, 'Upstream node limit reached (' + MAX_UPSTREAM_NODES + ').');
                response.limitReached = true;
                break;
            }

            if (dependency.metadataComponentType == null || !dependency.metadataComponentType.startsWith('Apex')) {
                continue;
            }

            DataJourneyNode apexNode = buildComponentNode(
                dependency,
                'upstream',
                'write',
                1,
                'Potential write inferred from Apex metadata reference.'
            );
            addOrMergeNode(response, nodeIndex, apexNode, context);
            addEdge(response, edgeIndex, apexNode.id, buildFieldNodeId(fullFieldName), 'writes_to', 'Apex reference (heuristic write inference).');
        }
    }

    private static DataJourneyResponse initializeResponse(String objectName, String fieldName) {
        DataJourneyResponse response = new DataJourneyResponse();
        response.objectName = objectName;
        response.fieldName = fieldName;
        response.nodes = new List<DataJourneyNode>();
        response.edges = new List<DataJourneyEdge>();
        response.warnings = new List<String>();
        response.limitReached = false;
        return response;
    }

    private static void finalizeResponse(DataJourneyResponse response, TraceContext context) {
        if (context.flowRetrievalLimitReached) {
            response.limitReached = true;
            addWarning(response, context, 'Flow metadata retrieval limit reached (' + MAX_FLOW_METADATA_RETRIEVALS + ').');
        }
    }

    private static DataJourneyNode buildFieldNode(
        String objectName,
        String fieldName,
        String direction,
        String accessType,
        Integer depth,
        String setupUrl,
        String detail
    ) {
        DataJourneyNode node = new DataJourneyNode();
        node.id = buildFieldNodeId(buildFullFieldName(objectName, fieldName));
        node.name = buildFullFieldName(objectName, fieldName);
        node.nodeType = 'field';
        node.direction = direction;
        node.accessType = accessType;
        node.depth = depth;
        node.setupUrl = setupUrl;
        node.detail = detail;
        return node;
    }

    private static DataJourneyNode buildComponentNode(
        DependencyHit hit,
        String direction,
        String accessType,
        Integer depth,
        String detail
    ) {
        DataJourneyNode node = new DataJourneyNode();
        node.id = buildComponentNodeId(hit.metadataComponentType, hit.metadataComponentId, hit.metadataComponentName);
        node.name = hit.metadataComponentName;
        node.nodeType = mapComponentToNodeType(hit.metadataComponentType);
        node.direction = direction;
        node.accessType = accessType;
        node.depth = depth;
        node.setupUrl = String.isBlank(hit.setupUrl) ? buildSetupUrl(hit.metadataComponentType) : hit.setupUrl;
        node.detail = detail;
        return node;
    }

    private static Boolean addOrMergeNode(
        DataJourneyResponse response,
        Map<String, DataJourneyNode> nodeIndex,
        DataJourneyNode candidate,
        TraceContext context
    ) {
        if (candidate == null || String.isBlank(candidate.id)) {
            return false;
        }

        if (nodeIndex.containsKey(candidate.id)) {
            DataJourneyNode existing = nodeIndex.get(candidate.id);
            if (existing.direction != candidate.direction && existing.direction != 'root') {
                existing.direction = 'readwrite';
            }
            if (existing.depth == null || (candidate.depth != null && candidate.depth < existing.depth)) {
                existing.depth = candidate.depth;
            }
            return false;
        }

        nodeIndex.put(candidate.id, candidate);
        response.nodes.add(candidate);

        if (candidate.direction == 'downstream') {
            context.downstreamNodeCount++;
        } else if (candidate.direction == 'upstream') {
            context.upstreamNodeCount++;
        }

        return true;
    }

    private static void addEdge(
        DataJourneyResponse response,
        Set<String> edgeIndex,
        String sourceId,
        String targetId,
        String relationship,
        String detail
    ) {
        if (String.isBlank(sourceId) || String.isBlank(targetId)) {
            return;
        }

        String key = sourceId + '|' + targetId + '|' + relationship;
        if (edgeIndex.contains(key)) {
            return;
        }

        DataJourneyEdge edge = new DataJourneyEdge();
        edge.sourceId = sourceId;
        edge.targetId = targetId;
        edge.relationship = relationship;
        edge.detail = detail;
        response.edges.add(edge);
        edgeIndex.add(key);
    }

    private static void addWarning(DataJourneyResponse response, TraceContext context, String warning) {
        if (String.isBlank(warning) || context.warningSet.contains(warning)) {
            return;
        }

        context.warningSet.add(warning);
        response.warnings.add(warning);
    }

    private static List<DependencyHit> queryDependenciesForField(String fullFieldName) {
        String fieldName = extractFieldName(fullFieldName);
        String refType = isCustomField(fieldName) ? 'CustomField' : 'StandardEntity';
        String escapedField = String.escapeSingleQuotes(fullFieldName);

        String soql =
            'SELECT MetadataComponentId, MetadataComponentName, MetadataComponentType, MetadataComponentNamespace, RefMetadataComponentName ' +
            'FROM MetadataComponentDependency ' +
            'WHERE RefMetadataComponentType = \'' + String.escapeSingleQuotes(refType) + '\' ' +
            'ORDER BY MetadataComponentType, MetadataComponentName';

        ToolingQueryResponse queryResponse = queryToolingRecords(soql, MAX_DEPENDENCY_ROWS);
        List<DependencyHit> hits = new List<DependencyHit>();

        for (Object recordObj : queryResponse.records) {
            Map<String, Object> row = asMap(recordObj);
            if (row == null) {
                continue;
            }
            // Client-side filter by name
            String refName = String.valueOf(row.get('RefMetadataComponentName'));
            if (refName == null || !refName.equalsIgnoreCase(fullFieldName)) {
                continue;
            }

            DependencyHit hit = new DependencyHit();
            hit.metadataComponentId = stringValue(row.get('MetadataComponentId'));
            hit.metadataComponentName = stringValue(row.get('MetadataComponentName'));
            hit.metadataComponentType = stringValue(row.get('MetadataComponentType'));
            hit.metadataComponentNamespace = stringValue(row.get('MetadataComponentNamespace'));
            hit.accessType = inferAccessType(hit.metadataComponentType);
            hit.setupUrl = buildSetupUrl(hit.metadataComponentType);
            hits.add(hit);
        }

        return hits;
    }

    private static List<ActiveFlowVersion> queryActiveFlows() {
        String soql =
            'SELECT Id, FlowDefinitionView.ApiName, FlowDefinitionView.Label ' +
            'FROM FlowVersionView ' +
            'WHERE Status = \'Active\' ' +
            'ORDER BY FlowDefinitionView.ApiName';

        ToolingQueryResponse queryResponse = queryToolingRecords(soql, MAX_DEPENDENCY_ROWS);
        List<ActiveFlowVersion> flows = new List<ActiveFlowVersion>();

        for (Object recordObj : queryResponse.records) {
            Map<String, Object> record = asMap(recordObj);
            if (record == null) {
                continue;
            }

            Map<String, Object> def = asMap(record.get('FlowDefinitionView'));
            ActiveFlowVersion flow = new ActiveFlowVersion();
            flow.id = stringValue(record.get('Id'));
            flow.apiName = def == null ? null : stringValue(def.get('ApiName'));
            flow.label = def == null ? null : stringValue(def.get('Label'));
            if (!String.isBlank(flow.id) && !String.isBlank(flow.apiName)) {
                flows.add(flow);
            }
        }

        return flows;
    }

    private static FlowFieldAnalyzer.FlowFieldAnalysis getFlowAnalysisByVersionId(
        String flowVersionId,
        TraceContext context,
        DataJourneyResponse response
    ) {
        if (String.isBlank(flowVersionId)) {
            return null;
        }

        if (context.flowAnalysisByVersionId.containsKey(flowVersionId)) {
            return context.flowAnalysisByVersionId.get(flowVersionId);
        }

        if (context.flowRetrievalCount >= MAX_FLOW_METADATA_RETRIEVALS) {
            context.flowRetrievalLimitReached = true;
            addWarning(response, context, 'Flow metadata retrieval limit reached (' + MAX_FLOW_METADATA_RETRIEVALS + ').');
            return null;
        }

        context.flowRetrievalCount++;
        HttpResponse callout = sendGet(TOOLING_BASE_PATH + '/sobjects/Flow/' + flowVersionId);
        Map<String, Object> payload = asMap(JSON.deserializeUntyped(callout.getBody()));
        Map<String, Object> metadata = payload == null ? null : asMap(payload.get('Metadata'));
        FlowFieldAnalyzer.FlowFieldAnalysis analysis = FlowFieldAnalyzer.analyzeFlow(metadata);
        context.flowAnalysisByVersionId.put(flowVersionId, analysis);
        return analysis;
    }

    private static Boolean analysisReadsField(
        FlowFieldAnalyzer.FlowFieldAnalysis analysis,
        String objectName,
        String fieldName,
        String fullFieldName
    ) {
        for (String reference : analysis.fieldsRead) {
            if (fieldReferenceMatches(reference, objectName, fieldName, fullFieldName)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean analysisWritesField(
        FlowFieldAnalyzer.FlowFieldAnalysis analysis,
        String objectName,
        String fieldName,
        String fullFieldName
    ) {
        for (String reference : analysis.fieldsWritten) {
            if (fieldReferenceMatches(reference, objectName, fieldName, fullFieldName)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean fieldReferenceMatches(
        String reference,
        String objectName,
        String fieldName,
        String fullFieldName
    ) {
        if (String.isBlank(reference)) {
            return false;
        }

        String normalized = normalizeReference(reference);
        if (String.isBlank(normalized)) {
            return false;
        }

        String lower = normalized.toLowerCase();
        String targetFull = fullFieldName.toLowerCase();
        String targetField = fieldName.toLowerCase();

        if (lower == targetFull || lower == targetField) {
            return true;
        }
        if (lower == ('$record.' + targetField) || lower == ('record.' + targetField)) {
            return true;
        }
        if (lower.endsWith('.' + targetField)) {
            return true;
        }

        String canonical = canonicalizeFieldReference(normalized, objectName);
        return canonical != null && canonical.toLowerCase() == targetFull;
    }

    private static String canonicalizeFieldReference(String reference, String defaultObject) {
        if (String.isBlank(reference)) {
            return null;
        }

        String normalized = normalizeReference(reference);
        if (String.isBlank(normalized)) {
            return null;
        }

        if (normalized.startsWith('$Record.') || normalized.startsWith('record.')) {
            String suffix = normalized.substring(normalized.indexOf('.') + 1);
            return isLikelyFieldName(suffix) ? buildFullFieldName(defaultObject, suffix) : null;
        }

        if (!normalized.contains('.')) {
            return isLikelyFieldName(normalized) ? buildFullFieldName(defaultObject, normalized) : null;
        }

        List<String> parts = normalized.split('\\.');
        if (parts.size() < 2) {
            return null;
        }

        String first = parts[0];
        String last = parts[parts.size() - 1];
        if (String.isBlank(last) || !isLikelyFieldName(last)) {
            return null;
        }

        if (first.startsWith('$') || first == 'var' || first == 'vars') {
            return buildFullFieldName(defaultObject, last);
        }

        if (isLikelyObjectName(first)) {
            return buildFullFieldName(first, last);
        }

        return buildFullFieldName(defaultObject, last);
    }

    private static ToolingQueryResponse queryToolingRecords(String soql, Integer maxRows) {
        ToolingQueryResponse aggregate = new ToolingQueryResponse();
        String path = TOOLING_BASE_PATH + '/query/?q=' + EncodingUtil.urlEncode(soql, 'UTF-8');

        while (path != null) {
            HttpResponse response = sendGet(path);
            Map<String, Object> payload = asMap(JSON.deserializeUntyped(response.getBody()));
            List<Object> records = payload == null ? null : asList(payload.get('records'));

            if (records != null) {
                for (Object item : records) {
                    if (aggregate.records.size() >= maxRows) {
                        aggregate.limitReached = true;
                        aggregate.done = false;
                        aggregate.nextRecordsUrl = payload == null ? null : stringValue(payload.get('nextRecordsUrl'));
                        return aggregate;
                    }
                    aggregate.records.add(item);
                }
            }

            aggregate.done = payload == null || payload.get('done') == null ? true : (Boolean) payload.get('done');
            aggregate.totalSize = payload == null || payload.get('totalSize') == null
                ? aggregate.records.size()
                : Integer.valueOf(String.valueOf(payload.get('totalSize')));
            aggregate.nextRecordsUrl = payload == null || payload.get('nextRecordsUrl') == null
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
            throw new DataJourneyServiceException(userMessage);
        }

        return response;
    }

    private static String resolveEndpoint(String path) {
        if (String.isBlank(path)) {
            throw new DataJourneyServiceException('Tooling API path cannot be empty.');
        }

        if (path.startsWith('/services/')) {
            return NAMED_CREDENTIAL + path;
        }
        return NAMED_CREDENTIAL + path;
    }

    private static Integer sanitizeMaxDepth(Integer maxDepth) {
        Integer depth = maxDepth == null ? MAX_DEPTH : maxDepth;
        if (depth < 1) {
            throw new DataJourneyServiceException('Max depth must be at least 1.');
        }
        if (depth > MAX_DEPTH) {
            return MAX_DEPTH;
        }
        return depth;
    }

    private static String validateObjectName(String objectName) {
        if (String.isBlank(objectName)) {
            throw new DataJourneyServiceException('Object name is required.');
        }

        String value = objectName.trim();
        if (value.length() > MAX_NAME_LENGTH) {
            throw new DataJourneyServiceException('Object name exceeds maximum length.');
        }
        if (!VALID_NAME.matcher(value).matches()) {
            throw new DataJourneyServiceException('Object name contains invalid characters.');
        }
        return value;
    }

    private static String validateFieldName(String fieldName) {
        if (String.isBlank(fieldName)) {
            throw new DataJourneyServiceException('Field name is required.');
        }

        String value = fieldName.trim();
        if (value.length() > MAX_NAME_LENGTH) {
            throw new DataJourneyServiceException('Field name exceeds maximum length.');
        }
        if (!VALID_FIELD.matcher(value).matches()) {
            throw new DataJourneyServiceException('Field name contains invalid characters.');
        }
        return value;
    }

    private static String buildFieldNodeId(String fullFieldName) {
        return 'field:' + fullFieldName;
    }

    private static String buildComponentNodeId(String type, String id, String name) {
        String stable = !String.isBlank(id) ? id : name;
        return mapComponentToNodeType(type) + ':' + stable;
    }

    private static String mapComponentToNodeType(String metadataComponentType) {
        if (metadataComponentType == 'Flow') {
            return 'flow';
        }
        if (metadataComponentType == 'ValidationRule') {
            return 'validationRule';
        }
        if (metadataComponentType == 'WorkflowFieldUpdate') {
            return 'workflowUpdate';
        }
        if (metadataComponentType != null && metadataComponentType.startsWith('Apex')) {
            return 'apex';
        }
        if (metadataComponentType == 'CustomField' || metadataComponentType == 'StandardEntity') {
            return 'field';
        }
        return 'metadata';
    }

    private static String inferAccessType(String metadataComponentType) {
        if (metadataComponentType == 'ApexTrigger') {
            return 'Write';
        }
        if (metadataComponentType != null && metadataComponentType.startsWith('Apex')) {
            return 'Read';
        }
        return 'Read';
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

    private static String normalizeReference(String reference) {
        if (String.isBlank(reference)) {
            return null;
        }

        String value = reference.trim();
        if (value.startsWith('{!') && value.endsWith('}')) {
            value = value.substring(2, value.length() - 1).trim();
        }
        return value;
    }

    private static String buildFullFieldName(String objectName, String fieldName) {
        return objectName + '.' + fieldName;
    }

    private static String extractObjectName(String fullFieldName) {
        Integer dot = fullFieldName == null ? -1 : fullFieldName.indexOf('.');
        return dot > 0 ? fullFieldName.substring(0, dot) : null;
    }

    private static String extractFieldName(String fullFieldName) {
        Integer dot = fullFieldName == null ? -1 : fullFieldName.indexOf('.');
        return dot > 0 ? fullFieldName.substring(dot + 1) : fullFieldName;
    }

    private static Boolean isCustomField(String fieldName) {
        return !String.isBlank(fieldName) && fieldName.toLowerCase().endsWith('__c');
    }

    private static Boolean isLikelyObjectName(String token) {
        return !String.isBlank(token) && token.length() <= MAX_NAME_LENGTH && VALID_NAME.matcher(token).matches();
    }

    private static Boolean isLikelyFieldName(String token) {
        return !String.isBlank(token) && token.length() <= MAX_NAME_LENGTH && VALID_FIELD.matcher(token).matches();
    }

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Map<String, Object> asMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : null;
    }

    private static List<Object> asList(Object value) {
        return value instanceof List<Object> ? (List<Object>) value : null;
    }
}
