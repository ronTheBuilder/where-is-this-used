public with sharing class BlastRadiusService {
    private static final Integer DEFAULT_MAX_DEPTH = 2;
    private static final Integer ABSOLUTE_MAX_DEPTH = 5;
    private static final Integer MAX_NODES = 500;
    private static final Integer MAX_API_CALLS = 12;

    public interface BlastRadiusDependencyProvider {
        List<DependencyService.DependencyRecord> search(String metadataType, String componentName);
    }

    public class BlastRadiusServiceException extends Exception {}

    public class GraphNode {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String componentType;
        @AuraEnabled public Integer depth;
        @AuraEnabled public Boolean isRoot;
        @AuraEnabled public Boolean isCycleNode;
        @AuraEnabled public String setupUrl;
    }

    public class GraphEdge {
        @AuraEnabled public String sourceId;
        @AuraEnabled public String targetId;
        @AuraEnabled public String edgeType;
    }

    public class GraphStats {
        @AuraEnabled public Integer totalNodes;
        @AuraEnabled public Integer totalEdges;
        @AuraEnabled public Integer maxDepthReached;
        @AuraEnabled public Map<String, Integer> nodesByType;
    }

    public class BlastRadiusResponse {
        @AuraEnabled public List<GraphNode> nodes;
        @AuraEnabled public List<GraphEdge> edges;
        @AuraEnabled public Integer totalDepth;
        @AuraEnabled public Boolean limitReached;
        @AuraEnabled public String warningMessage;
        @AuraEnabled public GraphStats stats;
    }

    private class GraphContext {
        public Map<String, GraphNode> nodesByKey = new Map<String, GraphNode>();
        public Map<String, String> keyToId = new Map<String, String>();
        public Set<String> edgeKeys = new Set<String>();
        public List<GraphEdge> edges = new List<GraphEdge>();
        public Integer apiCalls = 0;
        public Boolean limitReached = false;
        public Set<String> warnings = new Set<String>();
        public Integer maxDepthReached = 0;
    }

    private class DefaultBlastRadiusDependencyProvider implements BlastRadiusDependencyProvider {
        public List<DependencyService.DependencyRecord> search(String metadataType, String componentName) {
            DependencyService.DependencySearchResponse searchResult =
                DependencyService.searchDependencies(metadataType, componentName);

            List<DependencyService.DependencyRecord> records = new List<DependencyService.DependencyRecord>();
            if (searchResult == null || searchResult.groups == null) {
                return records;
            }

            for (DependencyService.DependencyGroup depGroup : searchResult.groups) {
                if (depGroup != null && depGroup.records != null) {
                    records.addAll(depGroup.records);
                }
            }
            return records;
        }
    }

    @TestVisible
    private static BlastRadiusDependencyProvider dependencyProvider = new DefaultBlastRadiusDependencyProvider();

    @TestVisible
    static void setDependencyProviderForTest(BlastRadiusDependencyProvider provider) {
        dependencyProvider = provider == null ? new DefaultBlastRadiusDependencyProvider() : provider;
    }

    @TestVisible
    static void resetDependencyProviderForTest() {
        dependencyProvider = new DefaultBlastRadiusDependencyProvider();
    }

    private class ComponentRef implements Comparable {
        public String id;
        public String name;
        public String type;
        public Integer depth;

        public ComponentRef(String id, String name, String type, Integer depth) {
            this.id = id;
            this.name = name;
            this.type = type;
            this.depth = depth;
        }

        public String key() {
            return makeNodeKey(type, name);
        }

        public Integer compareTo(Object other) {
            ComponentRef o = (ComponentRef) other;
            Integer c = (name == null ? '' : name).compareTo(o.name == null ? '' : o.name);
            if (c != 0) return c;
            return (type == null ? '' : type).compareTo(o.type == null ? '' : o.type);
        }
    }

    public static BlastRadiusResponse getBlastRadius(String metadataType, String componentName, Integer maxDepth) {
        try {
            ToolingApiClient.enforceAccess();
        } catch (ToolingApiClient.ToolingApiClientException ex) {
            throw new BlastRadiusServiceException(ex.getMessage());
        }

        if (String.isBlank(metadataType) || String.isBlank(componentName)) {
            throw new BlastRadiusServiceException('Metadata type and component name are required.');
        }

        // Flow names may contain spaces/dashes (MasterLabel fallback),
        // so use a looser validation for Flows (letters, digits, spaces, dashes, underscores, dots).
        if (metadataType == 'Flow') {
            if (!Pattern.compile('^[a-zA-Z0-9 _\\-.]+$').matcher(componentName.trim()).matches()) {
                throw new BlastRadiusServiceException('Component name contains invalid characters.');
            }
        } else {
            try {
                ToolingApiClient.validateComponentName(componentName);
            } catch (ToolingApiClient.ToolingApiClientException ex) {
                throw new BlastRadiusServiceException(ex.getMessage());
            }
        }
        Integer effectiveDepth = normalizeMaxDepth(maxDepth);
        String normalizedRootType = normalizeTypeForRoot(metadataType);

        GraphContext context = new GraphContext();
        String trimmedName = componentName.trim();

        String rootId = buildSyntheticId(normalizedRootType, trimmedName);
        addOrUpdateNode(context, rootId, trimmedName, normalizedRootType, 0, true);

        ComponentRef root = new ComponentRef(rootId, trimmedName, normalizedRootType, 0);
        traverseDependents(root, effectiveDepth, context, new Set<String>{ root.key() });

        BlastRadiusResponse response = new BlastRadiusResponse();
        response.nodes = new List<GraphNode>(context.nodesByKey.values());
        response.edges = context.edges;
        response.totalDepth = context.maxDepthReached;
        response.limitReached = context.limitReached;
        response.warningMessage = buildWarningMessage(context.warnings);
        response.stats = buildStats(response.nodes, response.edges, context.maxDepthReached);
        return response;
    }

    private static void traverseDependents(
        ComponentRef current,
        Integer maxDepth,
        GraphContext context,
        Set<String> path
    ) {
        if (context.limitReached || current.depth >= maxDepth) {
            return;
        }

        if (context.apiCalls >= MAX_API_CALLS) {
            context.limitReached = true;
            context.warnings.add('Maximum API call limit reached (' + String.valueOf(MAX_API_CALLS) + '). Returned a partial graph.');
            return;
        }

        List<ComponentRef> directDependents = fetchDependents(current, current.depth + 1, context);
        for (ComponentRef dependent : directDependents) {
            if (context.limitReached) {
                return;
            }

            if (context.nodesByKey.size() >= MAX_NODES && !context.nodesByKey.containsKey(dependent.key())) {
                context.limitReached = true;
                context.warnings.add('Maximum node limit reached (' + String.valueOf(MAX_NODES) + '). Returned a partial graph.');
                return;
            }

            GraphNode dependentNode = addOrUpdateNode(
                context,
                dependent.id,
                dependent.name,
                dependent.type,
                dependent.depth,
                false
            );
            String currentId = context.keyToId.get(current.key());
            String dependentId = context.keyToId.get(dependent.key());
            addEdge(context, currentId, dependentId, 'direct');

            Boolean inCurrentPath = path.contains(dependent.key());
            if (inCurrentPath) {
                dependentNode.isCycleNode = true;
                GraphNode currentNode = context.nodesByKey.get(current.key());
                if (currentNode != null) {
                    currentNode.isCycleNode = true;
                }
                continue;
            }

            Set<String> nextPath = new Set<String>(path);
            nextPath.add(dependent.key());
            traverseDependents(dependent, maxDepth, context, nextPath);
        }
    }

    private static List<ComponentRef> fetchDependents(ComponentRef component, Integer nextDepth, GraphContext context) {
        context.apiCalls++;

        String searchType = reverseNormalizeType(component.type);
        List<DependencyService.DependencyRecord> dependencyRecords;
        try {
            dependencyRecords = dependencyProvider.search(searchType, component.name);
        } catch (Exception ex) {
            context.warnings.add('Could not fetch dependents for ' + component.name + ': ' + ex.getMessage());
            return new List<ComponentRef>();
        }

        List<ComponentRef> dependents = new List<ComponentRef>();
        if (dependencyRecords == null) {
            return dependents;
        }

        for (DependencyService.DependencyRecord rec : dependencyRecords) {
            if (rec == null || String.isBlank(rec.metadataComponentName) || String.isBlank(rec.metadataComponentType)) {
                continue;
            }

            String depId = String.isBlank(rec.metadataComponentId)
                ? buildSyntheticId(rec.metadataComponentType, rec.metadataComponentName)
                : rec.metadataComponentId;
            dependents.add(new ComponentRef(depId, rec.metadataComponentName, rec.metadataComponentType, nextDepth));
        }

        dependents.sort();
        return dependents;
    }

    private static String reverseNormalizeType(String internalType) {
        Map<String, String> reverseMap = new Map<String, String>{
            'StandardEntity' => 'Standard Field',
            'CustomField' => 'Custom Field',
            'FlowDefinition' => 'Flow',
            'ApexClass' => 'Apex Class'
        };
        return reverseMap.containsKey(internalType) ? reverseMap.get(internalType) : internalType;
    }

    private static GraphNode addOrUpdateNode(
        GraphContext context,
        String nodeId,
        String nodeName,
        String nodeType,
        Integer depth,
        Boolean isRoot
    ) {
        String key = makeNodeKey(nodeType, nodeName);
        String existingId = context.keyToId.get(key);

        if (existingId == null) {
            context.keyToId.put(key, nodeId);
            GraphNode node = new GraphNode();
            node.id = nodeId;
            node.name = nodeName;
            node.componentType = nodeType;
            node.depth = depth;
            node.isRoot = isRoot;
            node.isCycleNode = false;
            node.setupUrl = SetupUrlResolver.resolve(nodeType, nodeId, nodeName);
            context.nodesByKey.put(key, node);
            context.maxDepthReached = Math.max(context.maxDepthReached, depth);
            return node;
        }

        GraphNode existing = context.nodesByKey.get(key);
        if (existing != null) {
            existing.depth = Math.min(existing.depth, depth);
            existing.isRoot = existing.isRoot || isRoot;
            context.maxDepthReached = Math.max(context.maxDepthReached, depth);
        }
        return existing;
    }

    private static void addEdge(GraphContext context, String sourceId, String targetId, String edgeType) {
        if (String.isBlank(sourceId) || String.isBlank(targetId)) {
            return;
        }

        String key = sourceId + '|' + targetId;
        if (context.edgeKeys.contains(key)) {
            return;
        }

        context.edgeKeys.add(key);
        GraphEdge edge = new GraphEdge();
        edge.sourceId = sourceId;
        edge.targetId = targetId;
        edge.edgeType = edgeType;
        context.edges.add(edge);
    }

    private static String buildWarningMessage(Set<String> warnings) {
        if (warnings == null || warnings.isEmpty()) {
            return null;
        }

        List<String> ordered = new List<String>(warnings);
        ordered.sort();
        return String.join(ordered, ' ');
    }

    private static GraphStats buildStats(List<GraphNode> nodes, List<GraphEdge> edges, Integer maxDepthReached) {
        GraphStats stats = new GraphStats();
        stats.totalNodes = nodes == null ? 0 : nodes.size();
        stats.totalEdges = edges == null ? 0 : edges.size();
        stats.maxDepthReached = maxDepthReached;
        stats.nodesByType = new Map<String, Integer>();

        if (nodes != null) {
            for (GraphNode node : nodes) {
                String typeKey = String.isBlank(node.componentType) ? 'Unknown' : node.componentType;
                Integer count = stats.nodesByType.containsKey(typeKey) ? stats.nodesByType.get(typeKey) : 0;
                stats.nodesByType.put(typeKey, count + 1);
            }
        }

        return stats;
    }

    private static Integer normalizeMaxDepth(Integer maxDepth) {
        Integer depth = maxDepth == null ? DEFAULT_MAX_DEPTH : maxDepth;
        if (depth < 1) {
            return DEFAULT_MAX_DEPTH;
        }
        return Math.min(depth, ABSOLUTE_MAX_DEPTH);
    }

    private static String normalizeTypeForRoot(String metadataType) {
        String type = metadataType == null ? null : metadataType.trim();
        Map<String, String> mapped = new Map<String, String>{
            'Standard Field' => 'StandardEntity',
            'Custom Field' => 'CustomField',
            'Flow' => 'FlowDefinition',
            'Apex Class' => 'ApexClass'
        };

        if (mapped.containsKey(type)) {
            return mapped.get(type);
        }

        if (String.isBlank(type)) {
            throw new BlastRadiusServiceException('Metadata type is required.');
        }

        if (!Pattern.compile('^[a-zA-Z][a-zA-Z0-9_]*$').matcher(type).matches()) {
            throw new BlastRadiusServiceException('Metadata type contains invalid characters.');
        }
        return type;
    }

    private static String makeNodeKey(String componentType, String componentName) {
        return (String.isBlank(componentType) ? 'Unknown' : componentType) + '::' +
            (String.isBlank(componentName) ? '' : componentName);
    }

    private static String buildSyntheticId(String componentType, String componentName) {
        return 'synthetic:' + makeNodeKey(componentType, componentName);
    }

}
