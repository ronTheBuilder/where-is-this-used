public with sharing class FlowFieldAnalyzer {
    public class FlowFieldAnalysis {
        @AuraEnabled public List<String> fieldsRead;
        @AuraEnabled public List<String> fieldsWritten;
        @AuraEnabled public List<String> subflowsCalled;

        public FlowFieldAnalysis() {
            fieldsRead = new List<String>();
            fieldsWritten = new List<String>();
            subflowsCalled = new List<String>();
        }
    }

    private static final Pattern TOKEN_PATTERN = Pattern.compile('[a-zA-Z_$][a-zA-Z0-9_$]*(?:\\.[a-zA-Z_$][a-zA-Z0-9_$]*)+');

    public static FlowFieldAnalysis analyzeFlow(Map<String, Object> flowMetadata) {
        FlowFieldAnalysis result = new FlowFieldAnalysis();
        if (flowMetadata == null) {
            return result;
        }

        Set<String> reads = new Set<String>();
        Set<String> writes = new Set<String>();
        Set<String> subflows = new Set<String>();

        scanDecisionElements(asList(flowMetadata.get('decisions')), reads);
        scanAssignmentElements(asList(flowMetadata.get('assignments')), reads, writes);
        scanRecordMutationElements(asList(flowMetadata.get('recordUpdates')), reads, writes);
        scanRecordMutationElements(asList(flowMetadata.get('recordCreates')), reads, writes);
        scanRecordLookupElements(asList(flowMetadata.get('recordLookups')), reads);
        scanFormulaElements(asList(flowMetadata.get('formulas')), reads);
        scanSubflows(asList(flowMetadata.get('subflows')), subflows);

        result.fieldsRead.addAll(new List<String>(reads));
        result.fieldsWritten.addAll(new List<String>(writes));
        result.subflowsCalled.addAll(new List<String>(subflows));

        result.fieldsRead.sort();
        result.fieldsWritten.sort();
        result.subflowsCalled.sort();
        return result;
    }

    private static void scanDecisionElements(List<Object> decisions, Set<String> reads) {
        if (decisions == null) {
            return;
        }
        for (Object decisionObj : decisions) {
            scanObjectForFieldTokens(decisionObj, reads);
        }
    }

    private static void scanAssignmentElements(List<Object> assignments, Set<String> reads, Set<String> writes) {
        if (assignments == null) {
            return;
        }

        for (Object assignmentObj : assignments) {
            Map<String, Object> assignment = asMap(assignmentObj);
            if (assignment == null) {
                scanObjectForFieldTokens(assignmentObj, reads);
                continue;
            }

            List<Object> items = asList(assignment.get('assignmentItems'));
            if (items == null) {
                items = asList(assignment.get('inputAssignments'));
            }

            if (items != null) {
                for (Object itemObj : items) {
                    Map<String, Object> item = asMap(itemObj);
                    if (item == null) {
                        scanObjectForFieldTokens(itemObj, reads);
                        continue;
                    }

                    addPotentialWrite(item.get('assignToReference'), writes);
                    addPotentialWrite(item.get('field'), writes);
                    addPotentialRead(item.get('value'), reads);
                    addPotentialRead(item.get('valueElementReference'), reads);
                    scanObjectForFieldTokens(itemObj, reads);
                }
            } else {
                scanObjectForFieldTokens(assignmentObj, reads);
            }
        }
    }

    private static void scanRecordMutationElements(List<Object> elements, Set<String> reads, Set<String> writes) {
        if (elements == null) {
            return;
        }

        for (Object elementObj : elements) {
            Map<String, Object> element = asMap(elementObj);
            if (element == null) {
                scanObjectForFieldTokens(elementObj, reads);
                continue;
            }

            List<Object> inputAssignments = asList(element.get('inputAssignments'));
            List<Object> fieldValues = asList(element.get('fieldValues'));
            List<Object> filters = asList(element.get('filters'));

            if (inputAssignments != null) {
                for (Object assignmentObj : inputAssignments) {
                    Map<String, Object> assignment = asMap(assignmentObj);
                    if (assignment != null) {
                        addPotentialWrite(assignment.get('field'), writes);
                        addPotentialWrite(assignment.get('assignToReference'), writes);
                        addPotentialRead(assignment.get('value'), reads);
                        addPotentialRead(assignment.get('valueElementReference'), reads);
                    }
                    scanObjectForFieldTokens(assignmentObj, reads);
                }
            }

            if (fieldValues != null) {
                for (Object fieldValueObj : fieldValues) {
                    Map<String, Object> fieldValue = asMap(fieldValueObj);
                    if (fieldValue != null) {
                        addPotentialWrite(fieldValue.get('field'), writes);
                        addPotentialRead(fieldValue.get('value'), reads);
                    }
                    scanObjectForFieldTokens(fieldValueObj, reads);
                }
            }

            if (filters != null) {
                for (Object filterObj : filters) {
                    scanObjectForFieldTokens(filterObj, reads);
                }
            }

            scanObjectForFieldTokens(elementObj, reads);
        }
    }

    private static void scanRecordLookupElements(List<Object> lookups, Set<String> reads) {
        if (lookups == null) {
            return;
        }
        for (Object lookupObj : lookups) {
            scanObjectForFieldTokens(lookupObj, reads);
        }
    }

    private static void scanFormulaElements(List<Object> formulas, Set<String> reads) {
        if (formulas == null) {
            return;
        }
        for (Object formulaObj : formulas) {
            scanObjectForFieldTokens(formulaObj, reads);
        }
    }

    private static void scanSubflows(List<Object> subflowElements, Set<String> subflows) {
        if (subflowElements == null) {
            return;
        }

        for (Object subflowObj : subflowElements) {
            Map<String, Object> subflow = asMap(subflowObj);
            if (subflow == null) {
                continue;
            }
            String flowName = normalize(String.valueOf(subflow.get('flowName')));
            if (!String.isBlank(flowName)) {
                subflows.add(flowName);
            }
        }
    }

    private static void addPotentialWrite(Object value, Set<String> writes) {
        String normalized = normalizeReference(value);
        if (!String.isBlank(normalized)) {
            writes.add(normalized);
        }
    }

    private static void addPotentialRead(Object value, Set<String> reads) {
        if (value == null) {
            return;
        }

        if (value instanceof String) {
            String text = String.valueOf(value);
            for (String token : extractTokens(text)) {
                reads.add(token);
            }
            return;
        }

        scanObjectForFieldTokens(value, reads);
    }

    private static void scanObjectForFieldTokens(Object node, Set<String> collector) {
        if (node == null) {
            return;
        }

        if (node instanceof Map<String, Object>) {
            for (Object value : ((Map<String, Object>) node).values()) {
                scanObjectForFieldTokens(value, collector);
            }
            return;
        }

        if (node instanceof List<Object>) {
            for (Object value : (List<Object>) node) {
                scanObjectForFieldTokens(value, collector);
            }
            return;
        }

        if (!(node instanceof String)) {
            return;
        }

        String text = String.valueOf(node);
        for (String token : extractTokens(text)) {
            collector.add(token);
        }
    }

    private static Set<String> extractTokens(String text) {
        Set<String> tokens = new Set<String>();
        if (String.isBlank(text)) {
            return tokens;
        }

        Matcher matcher = TOKEN_PATTERN.matcher(text);
        while (matcher.find()) {
            String token = normalize(matcher.group());
            if (String.isBlank(token)) {
                continue;
            }
            String lower = token.toLowerCase();
            if (lower.startsWith('system.') || lower.startsWith('math.') || lower.startsWith('text.') || lower.startsWith('date.') || lower.startsWith('datetime.') || lower.startsWith('ispickval.') || lower.startsWith('and.') || lower.startsWith('or.')) {
                continue;
            }
            if (token.contains('__') || token.contains('.') || token.startsWith('$Record.') || token.startsWith('record.')) {
                tokens.add(token);
            }
        }

        return tokens;
    }

    private static String normalizeReference(Object raw) {
        if (raw == null) {
            return null;
        }

        if (raw instanceof Map<String, Object> || raw instanceof List<Object>) {
            Set<String> extracted = new Set<String>();
            scanObjectForFieldTokens(raw, extracted);
            if (extracted.isEmpty()) {
                return null;
            }
            return new List<String>(extracted)[0];
        }

        return normalize(String.valueOf(raw));
    }

    private static String normalize(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        String normalized = value.trim();
        if (normalized.startsWith('{!') && normalized.endsWith('}')) {
            normalized = normalized.substring(2, normalized.length() - 1).trim();
        }

        while (normalized.endsWith(')')) {
            normalized = normalized.substring(0, normalized.length() - 1).trim();
        }

        return normalized;
    }

    private static Map<String, Object> asMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : null;
    }

    private static List<Object> asList(Object value) {
        return value instanceof List<Object> ? (List<Object>) value : null;
    }
}
