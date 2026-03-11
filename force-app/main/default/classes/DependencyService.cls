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
            'Validation Rule', 'Custom Metadata Type', 'Formula Field'
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

        // Formula Field: parse formula and show field dependencies
        // Handled before getRefMetadataType() since Formula Field has no refType mapping
        if (metadataType == 'Formula Field') {
            try {
                ToolingApiClient.validateComponentName(componentName);
            } catch (ToolingApiClient.ToolingApiClientException ex) {
                throw new DependencyServiceException(ex.getMessage());
            }
            return searchFormulaFieldDependencies(metadataType, componentName.trim());
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

        // Validation Rule: what references it + what fields it references (formula parsing)
        if (metadataType == 'Validation Rule') {
            return searchValidationRuleDependencies(metadataType, trimmedName, refType);
        }

        // Strip object prefix for field types — Tooling API stores RefMetadataComponentName
        // as just the field API name (e.g. "My_Field__c"), not "Object.My_Field__c"
        String queryName = trimmedName;
        if ((metadataType == 'Standard Field' || metadataType == 'Custom Field') && trimmedName.contains('.')) {
            queryName = trimmedName.substringAfter('.');
        }
        List<Object> filteredRecords = queryDependenciesWithFallback(refType, queryName);

        // Custom Label fallback: if name-based search returns nothing, try ID-based search
        if (filteredRecords.isEmpty() && metadataType == 'Custom Label') {
            filteredRecords = queryCustomLabelDependenciesById(trimmedName);
        }

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
     * Validation Rule search: components that reference it + fields it references (formula parsing).
     */
    private static DependencySearchResponse searchValidationRuleDependencies(String metadataType, String componentName, String toolingType) {
        DependencySearchResponse reverse = searchReverseDependencies(metadataType, componentName, toolingType);
        List<DependencyRecord> formulaRefs = getValidationRuleFormulaReferences(componentName);
        if (formulaRefs.isEmpty()) {
            return reverse;
        }
        List<DependencyRecord> combined = new List<DependencyRecord>();
        for (DependencyGroup g : reverse.groups) {
            if (g.records != null) combined.addAll(g.records);
        }
        combined.addAll(formulaRefs);
        reverse.totalCount = combined.size();
        reverse.groups = groupByComponentType(combined);
        return reverse;
    }

    /**
     * Formula Field: parse formula and return field dependencies.
     */
    private static DependencySearchResponse searchFormulaFieldDependencies(String metadataType, String componentName) {
        List<DependencyRecord> results = new List<DependencyRecord>();
        List<String> parts = componentName.split('\\.');
        if (parts.size() != 2) {
            return buildEmptyResponse(metadataType, componentName);
        }
        String objectName = parts[0].trim();
        String fieldName = parts[1].trim();
        if (String.isBlank(objectName) || String.isBlank(fieldName)) {
            return buildEmptyResponse(metadataType, componentName);
        }
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectName);
        if (sot == null) {
            return buildEmptyResponse(metadataType, componentName);
        }
        Map<String, Schema.SObjectField> fieldsMap = sot.getDescribe().fields.getMap();
        Schema.SObjectField fieldToken = fieldsMap.get(fieldName);
        if (fieldToken == null) {
            return buildEmptyResponse(metadataType, componentName);
        }
        Schema.DescribeFieldResult dfr = fieldToken.getDescribe();
        if (dfr == null || String.isBlank(dfr.getCalculatedFormula())) {
            return buildEmptyResponse(metadataType, componentName);
        }
        String formula = dfr.getCalculatedFormula();
        List<String> fieldRefs = FlowFieldAnalyzer.extractFieldReferencesFromFormula(formula);
        for (String fieldRef : fieldRefs) {
            if (String.isBlank(fieldRef)) continue;
            String refType = fieldRef.endsWith('__c') ? 'CustomField' : 'StandardEntity';
            DependencyRecord dep = new DependencyRecord();
            dep.metadataComponentId = null;
            dep.metadataComponentName = fieldRef;
            dep.metadataComponentType = refType;
            dep.metadataComponentNamespace = null;
            dep.refMetadataComponentName = componentName;
            dep.refMetadataComponentType = 'Formula Field';
            dep.accessType = 'Read';
            dep.setupUrl = SetupUrlResolver.resolve(refType, null, fieldRef);
            dep.isSubflowReference = false;
            results.add(dep);
        }
        DependencySearchResponse response = new DependencySearchResponse();
        response.metadataType = metadataType;
        response.componentName = componentName;
        response.totalCount = results.size();
        response.limitReached = false;
        response.warningMessage = null;
        response.groups = groupByComponentType(results);
        return response;
    }

    private static DependencySearchResponse buildEmptyResponse(String metadataType, String componentName) {
        DependencySearchResponse r = new DependencySearchResponse();
        r.metadataType = metadataType;
        r.componentName = componentName;
        r.totalCount = 0;
        r.limitReached = false;
        r.warningMessage = null;
        r.groups = new List<DependencyGroup>();
        return r;
    }

    /**
     * Parse ValidationRule formula to get field references. Returns DependencyRecords for each field.
     */
    private static List<DependencyRecord> getValidationRuleFormulaReferences(String componentName) {
        List<DependencyRecord> results = new List<DependencyRecord>();
        List<String> parts = componentName.split('\\.');
        if (parts.size() != 2) {
            return results;
        }
        String objectName = parts[0].trim();
        String vrName = parts[1].trim();
        if (String.isBlank(objectName) || String.isBlank(vrName)) {
            return results;
        }
        String escapedObj = String.escapeSingleQuotes(objectName);
        String escapedVr = String.escapeSingleQuotes(vrName);
        String soql = 'SELECT Id, ValidationName FROM ValidationRule ' +
            'WHERE EntityDefinition.QualifiedApiName = \'' + escapedObj + '\' AND ValidationName = \'' + escapedVr + '\'';
        ToolingApiClient.ToolingQueryResponse q = ToolingApiClient.queryToolingRecords(soql, 1);
        if (q.records.isEmpty()) {
            return results;
        }
        Map<String, Object> row = ToolingApiClient.asMap(q.records[0]);
        String vrId = row == null ? null : String.valueOf(row.get('Id'));
        if (String.isBlank(vrId)) {
            return results;
        }
        String metaSoql = 'SELECT Id, Metadata FROM ValidationRule WHERE Id = \'' + String.escapeSingleQuotes(vrId) + '\'';
        ToolingApiClient.ToolingQueryResponse metaQ = ToolingApiClient.queryToolingRecords(metaSoql, 1);
        if (metaQ.records.isEmpty()) {
            return results;
        }
        Map<String, Object> metaRow = ToolingApiClient.asMap(metaQ.records[0]);
        Object metaObj = metaRow == null ? null : metaRow.get('Metadata');
        Map<String, Object> meta = ToolingApiClient.asMap(metaObj);
        Object formulaObj = meta == null ? null : (meta.get('errorConditionFormula') != null
            ? meta.get('errorConditionFormula') : meta.get('ErrorConditionFormula'));
        String formula = formulaObj == null ? null : String.valueOf(formulaObj);
        if (String.isBlank(formula)) {
            return results;
        }
        List<String> fieldRefs = FlowFieldAnalyzer.extractFieldReferencesFromFormula(formula);
        for (String fieldRef : fieldRefs) {
            if (String.isBlank(fieldRef)) continue;
            String refType = fieldRef.endsWith('__c') ? 'CustomField' : 'StandardEntity';
            DependencyRecord dep = new DependencyRecord();
            dep.metadataComponentId = vrId;
            dep.metadataComponentName = componentName;
            dep.metadataComponentType = 'ValidationRule';
            dep.metadataComponentNamespace = null;
            dep.refMetadataComponentName = fieldRef;
            dep.refMetadataComponentType = refType;
            dep.accessType = 'Read';
            dep.setupUrl = SetupUrlResolver.resolve(refType, null, fieldRef);
            dep.isSubflowReference = false;
            results.add(dep);
        }
        return results;
    }

    /**
     * Reverse query: "what references component X?" (used for Validation Rules)
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

    /**
     * Fallback for Custom Labels: resolve the ExternalString ID first, then query by RefMetadataComponentId.
     * Handles cases where RefMetadataComponentType='CustomLabel' name-based query returns nothing
     * (common with managed package labels or org-specific Tooling API behavior).
     */
    private static List<Object> queryCustomLabelDependenciesById(String labelName) {
        try {
            String soql = 'SELECT Id FROM ExternalString WHERE Name = \'' +
                String.escapeSingleQuotes(labelName) + '\' LIMIT 1';
            ToolingApiClient.ToolingQueryResponse labelResult = ToolingApiClient.queryToolingRecords(soql, 1);
            if (labelResult.records.isEmpty()) return new List<Object>();

            Map<String, Object> labelRec = ToolingApiClient.asMap(labelResult.records[0]);
            String labelId = String.valueOf(labelRec.get('Id'));
            if (String.isBlank(labelId)) return new List<Object>();

            String depSoql =
                'SELECT MetadataComponentId, MetadataComponentName, MetadataComponentType, MetadataComponentNamespace, ' +
                'RefMetadataComponentName, RefMetadataComponentType ' +
                'FROM MetadataComponentDependency WHERE RefMetadataComponentId = \'' +
                String.escapeSingleQuotes(labelId) + '\'';

            ToolingApiClient.ToolingQueryResponse depResult = ToolingApiClient.queryToolingRecords(depSoql, MAX_DEPENDENCY_ROWS);
            return depResult.records;
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'Custom label ID-based fallback failed: ' + ex.getMessage());
            return new List<Object>();
        }
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
            String namespace = flowDefView.get('NamespacePrefix') == null ? null : String.valueOf(flowDefView.get('NamespacePrefix'));

            // Qualified name for managed package flows (e.g., npe03__Payments_Flow)
            String qualifiedName = String.isNotBlank(namespace) ? namespace + '__' + apiName : apiName;
            String displayLabel = String.isBlank(label) ? qualifiedName : label;
            if (String.isNotBlank(namespace)) {
                displayLabel += ' [' + namespace + ']';
            }

            unique.put(qualifiedName, new MetadataOption(displayLabel, qualifiedName));
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

        // Deduplicate by qualifiedName — prefer Active version; include status + namespace in label
        Map<String, MetadataOption> unique = new Map<String, MetadataOption>();
        Map<String, String> bestStatus = new Map<String, String>();

        for (Object recordObj : queryResponse.records) {
            Map<String, Object> record = ToolingApiClient.asMap(recordObj);
            Map<String, Object> flowDefView = ToolingApiClient.asMap(record.get('FlowDefinitionView'));
            if (flowDefView == null) continue;

            String apiName = String.valueOf(flowDefView.get('ApiName'));
            if (String.isBlank(apiName)) continue;

            String label = String.valueOf(flowDefView.get('Label'));
            String namespace = flowDefView.get('NamespacePrefix') == null ? null : String.valueOf(flowDefView.get('NamespacePrefix'));
            String status = record.get('Status') == null ? 'Unknown' : String.valueOf(record.get('Status'));

            String qualifiedName = String.isNotBlank(namespace) ? namespace + '__' + apiName : apiName;
            Boolean replace = !unique.containsKey(qualifiedName) || status == 'Active';
            if (replace) {
                String displayLabel = (String.isBlank(label) ? qualifiedName : label) + ' [' + status + ']';
                if (String.isNotBlank(namespace)) {
                    displayLabel += ' [' + namespace + ']';
                }
                unique.put(qualifiedName, new MetadataOption(displayLabel, qualifiedName));
                bestStatus.put(qualifiedName, status);
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
        return searchApexClasses(null);
    }

    /**
     * Search Apex classes by name (search-as-you-type).
     * Empty or null searchTerm returns first 50 classes alphabetically.
     */
    public static List<MetadataOption> searchApexClasses(String searchTerm) {
        ToolingApiClient.enforceAccess();
        String baseSoql = 'SELECT Id, Name, NamespacePrefix FROM ApexClass';
        String soql;
        if (String.isBlank(searchTerm)) {
            soql = baseSoql + ' ORDER BY Name LIMIT 50';
        } else {
            String escaped = String.escapeSingleQuotes(searchTerm.trim());
            String likePattern = '%' + escaped + '%';
            soql = baseSoql + ' WHERE Name LIKE \'' + likePattern + '\' ORDER BY Name LIMIT 50';
        }
        ToolingApiClient.ToolingQueryResponse queryResponse = ToolingApiClient.queryToolingRecords(soql, 50);

        List<MetadataOption> options = new List<MetadataOption>();
        for (Object recordObj : queryResponse.records) {
            Map<String, Object> record = ToolingApiClient.asMap(recordObj);
            String name = String.valueOf(record.get('Name'));
            String namespace = record.get('NamespacePrefix') == null ? null : String.valueOf(record.get('NamespacePrefix'));
            if (String.isBlank(name)) continue;

            String qualifiedName = String.isNotBlank(namespace) ? namespace + '.' + name : name;
            String displayLabel = name;
            if (String.isNotBlank(namespace)) {
                displayLabel += ' [' + namespace + ']';
            }
            options.add(new MetadataOption(displayLabel, qualifiedName));
        }
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

    /**
     * Find custom fields on a given object that have ZERO dependencies.
     * Useful for org cleanup — identifying fields safe to remove.
     */
    public static List<MetadataOption> findUnusedCustomFields(String objectName) {
        ToolingApiClient.enforceAccess();
        if (String.isBlank(objectName)) {
            return new List<MetadataOption>();
        }

        String escapedObj = String.escapeSingleQuotes(objectName);

        // Get all custom fields on the object
        String fieldSoql = 'SELECT Id, DeveloperName, TableEnumOrId FROM CustomField WHERE TableEnumOrId = \'' + escapedObj + '\'';
        ToolingApiClient.ToolingQueryResponse fieldResult = ToolingApiClient.queryToolingRecords(fieldSoql, MAX_DEPENDENCY_ROWS);

        if (fieldResult.records.isEmpty()) {
            return new List<MetadataOption>();
        }

        // Collect all field IDs
        Map<String, String> fieldIdToName = new Map<String, String>();
        for (Object recordObj : fieldResult.records) {
            Map<String, Object> rec = ToolingApiClient.asMap(recordObj);
            if (rec == null) continue;
            String fieldId = String.valueOf(rec.get('Id'));
            String devName = String.valueOf(rec.get('DeveloperName'));
            if (String.isNotBlank(fieldId) && String.isNotBlank(devName)) {
                fieldIdToName.put(fieldId, devName);
            }
        }

        if (fieldIdToName.isEmpty()) {
            return new List<MetadataOption>();
        }

        // Query dependencies for ALL these fields in one go
        Set<String> referencedFieldIds = new Set<String>();
        // Query in batches of 50 IDs (SOQL IN clause limit is 100 for Tooling API)
        List<String> allIds = new List<String>(fieldIdToName.keySet());
        for (Integer i = 0; i < allIds.size(); i += 50) {
            Integer endIdx = Math.min(i + 50, allIds.size());
            List<String> batch = new List<String>();
            for (Integer j = i; j < endIdx; j++) {
                batch.add('\'' + String.escapeSingleQuotes(allIds[j]) + '\'');
            }
            String idList = String.join(batch, ', ');

            try {
                String depSoql = 'SELECT RefMetadataComponentId FROM MetadataComponentDependency WHERE RefMetadataComponentId IN (' + idList + ')';
                ToolingApiClient.ToolingQueryResponse depResult = ToolingApiClient.queryToolingRecords(depSoql, MAX_DEPENDENCY_ROWS);
                for (Object depObj : depResult.records) {
                    Map<String, Object> dep = ToolingApiClient.asMap(depObj);
                    if (dep != null && dep.get('RefMetadataComponentId') != null) {
                        referencedFieldIds.add(String.valueOf(dep.get('RefMetadataComponentId')));
                    }
                }
            } catch (ToolingApiClient.ToolingApiClientException ex) {
                // Some orgs might not support this query; skip batch
                System.debug(LoggingLevel.WARN, 'Unused field scan batch failed: ' + ex.getMessage());
            }
        }

        // Fields NOT in referencedFieldIds are unused
        List<MetadataOption> unused = new List<MetadataOption>();
        for (String fieldId : fieldIdToName.keySet()) {
            if (!referencedFieldIds.contains(fieldId)) {
                String devName = fieldIdToName.get(fieldId);
                unused.add(new MetadataOption(
                    objectName + '.' + devName + '__c',
                    objectName + '.' + devName + '__c'
                ));
            }
        }
        unused.sort();
        return unused;
    }

    public static List<MetadataOption> getCustomLabels() {
        ToolingApiClient.enforceAccess();
        String soql = 'SELECT Id, Name, NamespacePrefix, Value FROM ExternalString';
        ToolingApiClient.ToolingQueryResponse queryResponse = ToolingApiClient.queryToolingRecords(soql, MAX_DEPENDENCY_ROWS);

        List<MetadataOption> options = new List<MetadataOption>();
        for (Object recordObj : queryResponse.records) {
            Map<String, Object> record = ToolingApiClient.asMap(recordObj);
            String name = String.valueOf(record.get('Name'));
            String value = String.valueOf(record.get('Value'));
            String namespace = record.get('NamespacePrefix') == null ? null : String.valueOf(record.get('NamespacePrefix'));
            if (String.isBlank(name)) continue;

            String displayLabel = name;
            if (String.isNotBlank(namespace)) {
                displayLabel = namespace + '__' + name;
            }
            if (String.isNotBlank(value)) {
                displayLabel += ' (' + (value.length() > 50 ? value.substring(0, 50) + '...' : value) + ')';
            }
            // Use the full qualified name (with namespace) as value for searching
            String searchValue = String.isNotBlank(namespace) ? namespace + '__' + name : name;
            options.add(new MetadataOption(displayLabel, searchValue));
        }
        return options;
    }

    public static List<MetadataOption> getFormulaFields(String objectName) {
        ToolingApiClient.enforceAccess();
        if (String.isBlank(objectName)) {
            return new List<MetadataOption>();
        }
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectName);
        if (sot == null) {
            return new List<MetadataOption>();
        }
        Map<String, String> labelByApiName = new Map<String, String>();
        for (Schema.SObjectField fieldToken : sot.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult dfr = fieldToken.getDescribe();
            if (!dfr.isAccessible()) continue;
            if (String.isBlank(dfr.getCalculatedFormula())) continue;
            labelByApiName.put(dfr.getName(), dfr.getLabel());
        }
        List<String> names = new List<String>(labelByApiName.keySet());
        names.sort();
        List<MetadataOption> options = new List<MetadataOption>();
        for (String apiName : names) {
            String label = labelByApiName.get(apiName);
            options.add(new MetadataOption(label + ' (' + apiName + ')', objectName + '.' + apiName));
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
