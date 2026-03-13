public with sharing class ToolingApiClient {
    public static final String API_VERSION = '66.0';
    public static final String NAMED_CREDENTIAL = 'callout:WITU_ToolingAPI';
    public static final String TOOLING_BASE_PATH = '/services/data/v' + API_VERSION + '/tooling';

    private static final String CUSTOM_PERMISSION = 'WITU_Access';
    private static final Integer MAX_COMPONENT_NAME_LENGTH = 255;
    private static final Integer HTTP_TIMEOUT_MS = 120000;
    private static final Integer MAX_RETRY_ATTEMPTS = 3;
    private static final Pattern VALID_COMPONENT_NAME = Pattern.compile('^[a-zA-Z][a-zA-Z0-9_.]*$');

    @TestVisible
    private static Boolean bypassAccessCheckForTests = false;

    @TestVisible
    private static Boolean useNamedCredential;

    @TestVisible
    private static String mockSessionId;

    public static Boolean isNamedCredentialMode() {
        if (useNamedCredential != null) return useNamedCredential;
        WITU_Settings__c settings = WITU_Settings__c.getInstance();
        useNamedCredential = settings != null && settings.Use_Named_Credential__c == true;
        return useNamedCredential;
    }

    public class ToolingApiClientException extends Exception {}

    public class ToolingQueryResponse {
        public List<Object> records = new List<Object>();
        public Boolean done;
        public Integer totalSize;
        public String nextRecordsUrl;
        public Boolean limitReached = false;
    }

    @TestVisible
    public static void enforceAccess() {
        if (Test.isRunningTest() && bypassAccessCheckForTests) {
            return;
        }
        if (!FeatureManagement.checkPermission(CUSTOM_PERMISSION)) {
            throw new ToolingApiClientException(
                'Insufficient permissions. The custom permission "' + CUSTOM_PERMISSION + '" is required. ' +
                'Ask your admin to assign the "Where Is This Used? User" permission set.'
            );
        }
    }

    public static void validateComponentName(String componentName) {
        if (String.isBlank(componentName)) {
            throw new ToolingApiClientException('Component name is required.');
        }

        String trimmed = componentName.trim();
        if (trimmed.length() > MAX_COMPONENT_NAME_LENGTH) {
            throw new ToolingApiClientException('Component name exceeds maximum length.');
        }

        if (!VALID_COMPONENT_NAME.matcher(trimmed).matches()) {
            throw new ToolingApiClientException(
                'Component name contains invalid characters. Only letters, numbers, dots, and underscores are allowed.'
            );
        }
    }

    public static ToolingQueryResponse queryToolingRecords(String soql, Integer maxRows) {
        enforceAccess();
        if (String.isBlank(soql)) {
            throw new ToolingApiClientException('SOQL query is required.');
        }

        Integer rowCap = maxRows == null || maxRows <= 0 ? 2000 : maxRows;
        ToolingQueryResponse aggregate = new ToolingQueryResponse();
        String path = TOOLING_BASE_PATH + '/query/?q=' + EncodingUtil.urlEncode(soql, 'UTF-8');

        while (path != null) {
            HttpResponse response = sendGet(path);
            Map<String, Object> payload = asMap(JSON.deserializeUntyped(response.getBody()));
            List<Object> records = payload == null ? null : asList(payload.get('records'));

            if (records != null) {
                for (Object item : records) {
                    if (aggregate.records.size() >= rowCap) {
                        aggregate.limitReached = true;
                        aggregate.done = false;
                        aggregate.nextRecordsUrl = payload == null ? null : String.valueOf(payload.get('nextRecordsUrl'));
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

    public static Map<String, ToolingQueryResponse> compositeToolingQueries(Map<String, String> labeledQueries) {
        enforceAccess();
        Map<String, ToolingQueryResponse> responseMap = new Map<String, ToolingQueryResponse>();
        if (labeledQueries == null || labeledQueries.isEmpty()) {
            return responseMap;
        }

        List<Map<String, Object>> subrequests = new List<Map<String, Object>>();
        for (String label : labeledQueries.keySet()) {
            String soql = labeledQueries.get(label);
            if (String.isBlank(label) || String.isBlank(soql)) {
                continue;
            }
            Map<String, Object> sub = new Map<String, Object>();
            sub.put('method', 'GET');
            sub.put('url', '/services/data/v' + API_VERSION + '/tooling/query/?q=' + EncodingUtil.urlEncode(soql, 'UTF-8'));
            sub.put('referenceId', label);
            subrequests.add(sub);
        }
        if (subrequests.isEmpty()) {
            return responseMap;
        }

        checkCalloutBudget();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(resolveEndpoint('/services/data/v' + API_VERSION + '/tooling/composite'));
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        if (!isNamedCredentialMode()) {
            req.setHeader('Authorization', 'Bearer ' + getSessionId());
        }
        req.setBody(JSON.serialize(new Map<String, Object>{ 'compositeRequest' => subrequests }));
        req.setTimeout(HTTP_TIMEOUT_MS);

        HttpResponse res = new Http().send(req);
        Integer statusCode = res == null ? 0 : res.getStatusCode();
        if (statusCode < 200 || statusCode >= 300) {
            throw new ToolingApiClientException(buildErrorMessage(statusCode, res == null ? null : res.getBody()));
        }

        Map<String, Object> payload = asMap(JSON.deserializeUntyped(res.getBody()));
        List<Object> results = payload == null ? null : asList(payload.get('compositeResponse'));
        if (results == null) {
            return responseMap;
        }

        for (Object resultObj : results) {
            Map<String, Object> result = asMap(resultObj);
            if (result == null) {
                continue;
            }
            String refId = result.get('referenceId') == null ? null : String.valueOf(result.get('referenceId'));
            if (String.isBlank(refId)) {
                continue;
            }

            ToolingQueryResponse tqr = new ToolingQueryResponse();
            Integer subStatusCode = result.get('httpStatusCode') == null ? 0 : Integer.valueOf(String.valueOf(result.get('httpStatusCode')));
            if (subStatusCode >= 200 && subStatusCode < 300) {
                Map<String, Object> body = asMap(result.get('body'));
                tqr.totalSize = body == null || body.get('totalSize') == null
                    ? 0
                    : Integer.valueOf(String.valueOf(body.get('totalSize')));
                tqr.done = body == null || body.get('done') == null ? true : (Boolean) body.get('done');
                tqr.nextRecordsUrl = body == null || body.get('nextRecordsUrl') == null
                    ? null
                    : String.valueOf(body.get('nextRecordsUrl'));
                tqr.records = body != null && body.containsKey('records')
                    ? (asList(body.get('records')) == null ? new List<Object>() : asList(body.get('records')))
                    : new List<Object>();
            } else {
                tqr.totalSize = 0;
                tqr.done = true;
                tqr.records = new List<Object>();
                System.debug(LoggingLevel.WARN, 'Composite sub-request failed for ' + refId + ': ' + String.valueOf(result.get('body')));
            }
            responseMap.put(refId, tqr);
        }

        return responseMap;
    }

    public static HttpResponse sendGet(String path) {
        Integer attempt = 0;
        HttpResponse response;

        while (attempt < MAX_RETRY_ATTEMPTS) {
            attempt++;
            checkCalloutBudget();

            HttpRequest request = new HttpRequest();
            request.setMethod('GET');
            request.setTimeout(HTTP_TIMEOUT_MS);
            request.setEndpoint(resolveEndpoint(path));
            if (!isNamedCredentialMode()) {
                request.setHeader('Authorization', 'Bearer ' + getSessionId());
            }

            response = new Http().send(request);
            Integer status = response.getStatusCode();
            if (status >= 200 && status < 300) {
                return response;
            }

            System.debug(LoggingLevel.ERROR, 'Tooling API error (' + status + '): ' + response.getBody());
            // Retry only on 503 (server unavailable); 429 (rate limit) cannot benefit from
            // immediate retry since Apex has no Thread.sleep() for backoff.
            if (status == 503 && attempt < MAX_RETRY_ATTEMPTS) {
                continue;
            }

            throw new ToolingApiClientException(buildErrorMessage(status, response.getBody()));
        }

        throw new ToolingApiClientException('Tooling API request failed after retries.');
    }

    public static String resolveEndpoint(String path) {
        if (String.isBlank(path)) {
            throw new ToolingApiClientException('Tooling API path cannot be empty.');
        }

        if (path.startsWith('callout:')) {
            return path;
        }
        String basePath = path.startsWith('/') ? path : '/' + path;
        if (isNamedCredentialMode()) {
            return NAMED_CREDENTIAL + basePath;
        }
        return URL.getOrgDomainUrl().toExternalForm() + basePath;
    }

    public static void checkCalloutBudget() {
        Integer remaining = Limits.getLimitCallouts() - Limits.getCallouts();
        if (remaining <= 0) {
            throw new ToolingApiClientException('Callout limit reached for this transaction.');
        }
    }

    /**
     * Obtain a valid session ID. UserInfo.getSessionId() returns null in
     * Lightning / @AuraEnabled context, so we fall back to a lightweight
     * Visualforce page that exposes {!$Api.Session_ID}.
     */
    @TestVisible
    private static String cachedSessionId;

    @TestVisible
    public static String getSessionId() {
        if (Test.isRunningTest() && mockSessionId != null) {
            return mockSessionId;
        }

        if (String.isNotBlank(cachedSessionId)) {
            return cachedSessionId;
        }

        // UserInfo.getSessionId() returns null or a restricted session in
        // Lightning / @AuraEnabled context, so prefer the VF page approach
        // which always returns a full API-enabled session ID.
        try {
            String content = Page.WITU_SessionBridge.getContent().toString().trim();
            if (String.isNotBlank(content)) {
                cachedSessionId = content;
                return cachedSessionId;
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'VF session bridge failed: ' + ex.getMessage());
        }

        // Fall back to UserInfo (works in non-Lightning contexts)
        String sid = System.UserInfo.getSessionId();
        if (String.isNotBlank(sid)) {
            cachedSessionId = sid;
            return cachedSessionId;
        }

        return null;
    }

    public static Map<String, Object> asMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : null;
    }

    public static List<Object> asList(Object value) {
        return value instanceof List<Object> ? (List<Object>) value : null;
    }

    private static String buildErrorMessage(Integer status, String responseBody) {
        if (status == 400) {
            String parsedMessage = parseErrorBodyMessage(responseBody);
            if (!String.isBlank(parsedMessage)) {
                return 'Tooling API request was invalid: ' + parsedMessage;
            }
            return 'Tooling API request was invalid (HTTP 400). Check Setup > Debug Logs for details.';
        }
        if (status == 401 || status == 403) {
            if (isNamedCredentialMode()) {
                return 'Authentication failed. Verify your Named Credential (WITU_ToolingAPI) is configured correctly.';
            }
            return 'Authentication failed. Refresh the page and try again. If the issue persists, check that your user has API access enabled.';
        }
        if (status == 404) {
            return 'Tooling API endpoint not found. Please verify your org\'s API version supports this feature.';
        }
        if (status == 429) {
            return 'API rate limit exceeded. Please wait a moment and try again.';
        }
        if (status == 503) {
            return 'Tooling API is temporarily unavailable. Please wait a moment and try again.';
        }
        return 'Tooling API request failed (HTTP ' + status + '). Check Setup > Debug Logs for details.';
    }

    /**
     * Retrieve flow metadata for a given FlowVersionView Id.
     * Null-safe: returns null if the response or Metadata key is absent.
     */
    public static Map<String, Object> getFlowMetadata(String flowVersionId) {
        HttpResponse response = sendGet(TOOLING_BASE_PATH + '/sobjects/Flow/' + flowVersionId);
        Map<String, Object> payload = asMap(JSON.deserializeUntyped(response.getBody()));
        return payload == null ? null : asMap(payload.get('Metadata'));
    }

    /**
     * Generic: retrieve a Tooling API record by sObject type and Id.
     * Returns the full deserialized response body as a Map.
     */
    public static Map<String, Object> getToolingRecord(String sObjectType, String recordId) {
        if (String.isBlank(sObjectType) || String.isBlank(recordId)) {
            return null;
        }
        HttpResponse response = sendGet(TOOLING_BASE_PATH + '/sobjects/' + sObjectType + '/' + recordId);
        return asMap(JSON.deserializeUntyped(response.getBody()));
    }

    /**
     * Query FlowVersionView with FlowDefinitionView relationship fields.
     * Three-level fallback:
     *   1. FlowVersionView WITH relationship fields
     *   2. FlowVersionView WITHOUT relationship fields + separate FlowDefinitionView lookup
     *   3. FlowDefinitionView only (when FlowVersionView is entirely unavailable)
     *
     * @param additionalFields Extra fields beyond Id (e.g. 'ProcessType, TriggerObjectOrEvent, TriggerType, Status, VersionNumber'). May be null.
     * @param whereClause      WHERE clause without the WHERE keyword (e.g. 'Status = \'Active\'')
     * @param maxRows          Maximum rows to return
     */
    public static ToolingQueryResponse queryFlowVersionsWithFallback(String additionalFields, String whereClause, Integer maxRows) {
        // Level 1: FlowVersionView with relationship fields (incl. NamespacePrefix for managed packages)
        String relFields = 'Id, FlowDefinitionView.ApiName, FlowDefinitionView.Label, FlowDefinitionView.NamespacePrefix';
        if (String.isNotBlank(additionalFields)) {
            relFields += ', ' + additionalFields;
        }

        String whereFragment = String.isBlank(whereClause) ? '' : ' WHERE ' + whereClause;
        String soql = 'SELECT ' + relFields + ' FROM FlowVersionView' + whereFragment;
        try {
            ToolingQueryResponse result = queryToolingRecords(soql, maxRows);
            if (!result.records.isEmpty()) {
                return result;
            }
            System.debug(LoggingLevel.WARN, 'FlowVersionView relationship query returned 0 rows; trying broader fallback queries.');
        } catch (ToolingApiClientException ex) {
            if (!isQueryError(ex)) {
                throw ex;
            }
        }

        // Level 2: FlowVersionView without relationship fields + FlowDefinitionView enrichment
        String fallbackFields = 'Id';
        if (String.isNotBlank(additionalFields)) {
            fallbackFields += ', ' + additionalFields;
        }

        String fallbackSoql = 'SELECT ' + fallbackFields + ' FROM FlowVersionView' + whereFragment;
        try {
            ToolingQueryResponse result = queryToolingRecords(fallbackSoql, maxRows);
            enrichWithFlowDefinitionView(result, maxRows);
            if (!result.records.isEmpty()) {
                return result;
            }
            System.debug(LoggingLevel.WARN, 'FlowVersionView enrichment fallback returned 0 rows; trying FlowDefinition fallbacks.');
        } catch (ToolingApiClientException ex) {
            if (!isQueryError(ex)) {
                throw ex;
            }
        }

        // Level 3: FlowDefinitionView only (FlowVersionView not available on this org)
        try {
            ToolingQueryResponse result = queryFlowDefinitionViewOnly(maxRows);
            if (!result.records.isEmpty()) {
                return result;
            }
            System.debug(LoggingLevel.WARN, 'FlowDefinitionView fallback returned 0 rows; trying FlowDefinition.');
        } catch (ToolingApiClientException ex) {
            if (!isQueryError(ex)) {
                throw ex;
            }
        }

        // Level 4: FlowDefinition (handles orgs where FlowVersionView filters miss managed-installed flows)
        try {
            ToolingQueryResponse result = queryFlowDefinitionOnly(maxRows);
            if (!result.records.isEmpty()) {
                return result;
            }
        } catch (ToolingApiClientException ex) {
            if (!isQueryError(ex)) {
                throw ex;
            }
        }

        // Level 5: Flow sObject directly (last resort)
        return queryFlowSObjectOnly(maxRows);
    }

    /**
     * Enrich FlowVersionView records with FlowDefinitionView data via ActiveVersionId lookup.
     */
    private static void enrichWithFlowDefinitionView(ToolingQueryResponse result, Integer maxRows) {
        ToolingQueryResponse defResult = queryToolingRecords(
            'SELECT ApiName, Label, NamespacePrefix, ActiveVersionId FROM FlowDefinitionView WHERE IsActive = true',
            maxRows
        );

        Map<String, Map<String, String>> defLookup = new Map<String, Map<String, String>>();
        for (Object rec : defResult.records) {
            Map<String, Object> row = asMap(rec);
            if (row == null) continue;
            String activeVersionId = row.get('ActiveVersionId') == null ? null : String.valueOf(row.get('ActiveVersionId'));
            if (String.isBlank(activeVersionId)) continue;
            defLookup.put(activeVersionId, new Map<String, String>{
                'ApiName' => row.get('ApiName') == null ? null : String.valueOf(row.get('ApiName')),
                'Label' => row.get('Label') == null ? null : String.valueOf(row.get('Label')),
                'NamespacePrefix' => row.get('NamespacePrefix') == null ? null : String.valueOf(row.get('NamespacePrefix'))
            });
        }

        for (Object rec : result.records) {
            Map<String, Object> row = asMap(rec);
            if (row == null) continue;
            String versionId = row.get('Id') == null ? null : String.valueOf(row.get('Id'));
            if (String.isBlank(versionId) || !defLookup.containsKey(versionId)) continue;
            Map<String, String> def = defLookup.get(versionId);
            row.put('FlowDefinitionView', new Map<String, Object>{
                'ApiName' => def.get('ApiName'),
                'Label' => def.get('Label'),
                'NamespacePrefix' => def.get('NamespacePrefix')
            });
        }
    }

    /**
     * Last-resort fallback: query FlowDefinitionView directly.
     * Returns records shaped like FlowVersionView with ActiveVersionId as Id
     * and FlowDefinitionView as a nested map.
     */
    private static ToolingQueryResponse queryFlowDefinitionViewOnly(Integer maxRows) {
        ToolingQueryResponse defResult = queryToolingRecords(
            'SELECT ApiName, Label, NamespacePrefix, ActiveVersionId FROM FlowDefinitionView WHERE IsActive = true',
            maxRows
        );

        ToolingQueryResponse shaped = new ToolingQueryResponse();
        shaped.done = defResult.done;
        shaped.totalSize = defResult.totalSize;
        shaped.limitReached = defResult.limitReached;

        for (Object rec : defResult.records) {
            Map<String, Object> row = asMap(rec);
            if (row == null) continue;
            String activeVersionId = row.get('ActiveVersionId') == null ? null : String.valueOf(row.get('ActiveVersionId'));
            String apiName = row.get('ApiName') == null ? null : String.valueOf(row.get('ApiName'));
            if (String.isBlank(activeVersionId) || String.isBlank(apiName)) continue;

            Map<String, Object> shapedRecord = new Map<String, Object>{
                'Id' => activeVersionId,
                'Status' => 'Active',
                'FlowDefinitionView' => new Map<String, Object>{
                    'ApiName' => apiName,
                    'Label' => row.get('Label') == null ? null : String.valueOf(row.get('Label')),
                    'NamespacePrefix' => row.get('NamespacePrefix') == null ? null : String.valueOf(row.get('NamespacePrefix'))
                }
            };
            shaped.records.add(shapedRecord);
        }

        return shaped;
    }

    /**
     * Fallback for orgs where FlowVersionView filters exclude managed-installed flows.
     * Uses FlowDefinition active versions and shapes records like FlowVersionView.
     */
    private static ToolingQueryResponse queryFlowDefinitionOnly(Integer maxRows) {
        ToolingQueryResponse defResult = queryToolingRecords(
            'SELECT Id, DeveloperName, NamespacePrefix, ActiveVersionId FROM FlowDefinition WHERE ActiveVersionId != null',
            maxRows
        );

        ToolingQueryResponse shaped = new ToolingQueryResponse();
        shaped.done = defResult.done;
        shaped.totalSize = defResult.totalSize;
        shaped.limitReached = defResult.limitReached;

        for (Object rec : defResult.records) {
            Map<String, Object> row = asMap(rec);
            if (row == null) continue;

            String activeVersionId = row.get('ActiveVersionId') == null ? null : String.valueOf(row.get('ActiveVersionId'));
            String developerName = row.get('DeveloperName') == null ? null : String.valueOf(row.get('DeveloperName'));
            if (String.isBlank(activeVersionId) || String.isBlank(developerName)) continue;

            Map<String, Object> shapedRecord = new Map<String, Object>{
                'Id' => activeVersionId,
                'Status' => 'Active',
                'FlowDefinitionView' => new Map<String, Object>{
                    'ApiName' => developerName,
                    'Label' => developerName,
                    'NamespacePrefix' => row.get('NamespacePrefix') == null ? null : String.valueOf(row.get('NamespacePrefix'))
                }
            };
            shaped.records.add(shapedRecord);
        }

        return shaped;
    }

    /**
     * Last-resort fallback: query Flow sObject directly.
     * Used when both FlowVersionView and FlowDefinitionView are unsupported.
     * Returns records shaped like FlowVersionView with FlowDefinitionView nested map.
     * Uses MasterLabel as both ApiName and Label since DeveloperName is not
     * reliably available on the Flow sObject.
     */
    private static ToolingQueryResponse queryFlowSObjectOnly(Integer maxRows) {
        // FullName/Metadata fields cannot be queried when results contain more
        // than one row (Tooling API limitation), so use MasterLabel as ApiName.
        ToolingQueryResponse flowResult = queryToolingRecords(
            'SELECT Id, MasterLabel, ProcessType, Status FROM Flow WHERE Status = \'Active\'',
            maxRows
        );

        ToolingQueryResponse shaped = new ToolingQueryResponse();
        shaped.done = flowResult.done;
        shaped.totalSize = flowResult.totalSize;
        shaped.limitReached = flowResult.limitReached;

        for (Object rec : flowResult.records) {
            Map<String, Object> row = asMap(rec);
            if (row == null) continue;
            String flowId = row.get('Id') == null ? null : String.valueOf(row.get('Id'));
            String masterLabel = row.get('MasterLabel') == null ? null : String.valueOf(row.get('MasterLabel'));
            if (String.isBlank(flowId)) continue;

            Map<String, Object> shapedRecord = new Map<String, Object>{
                'Id' => flowId,
                'FlowDefinitionView' => new Map<String, Object>{
                    'ApiName' => masterLabel,
                    'Label' => masterLabel
                }
            };

            // Preserve extra fields callers may need
            if (row.get('ProcessType') != null) {
                shapedRecord.put('ProcessType', row.get('ProcessType'));
            }
            if (row.get('Status') != null) {
                shapedRecord.put('Status', row.get('Status'));
            }

            shaped.records.add(shapedRecord);
        }

        return shaped;
    }

    /**
     * Check if an exception is a query-related error that should trigger a fallback.
     */
    private static Boolean isQueryError(ToolingApiClientException ex) {
        String msg = ex == null || ex.getMessage() == null ? '' : ex.getMessage().toLowerCase();
        return msg.contains('invalid') || msg.contains('400') || msg.contains('not found') || msg.contains('not supported');
    }

    /**
     * Query MetadataComponentDependency with server-side RefMetadataComponentName
     * filtering when available, falling back to client-side filtering.
     *
     * @param selectFields  SELECT clause fields
     * @param refType       RefMetadataComponentType value
     * @param componentName RefMetadataComponentName to filter on
     * @param maxRows       Maximum rows to return
     */
    /**
     * Query MetadataComponentDependency with multi-level fallback:
     *   1. Server-side filter on both RefMetadataComponentType + RefMetadataComponentName
     *   2. Server-side RefMetadataComponentType only + client-side name filter
     *   3. Server-side RefMetadataComponentName only (when type value is unsupported)
     *   4. No ref-field filters + full client-side filtering (last resort)
     */
    public static ToolingQueryResponse queryDependenciesWithNameFallback(
        String selectFields,
        String refType,
        String componentName,
        Integer maxRows
    ) {
        String escapedRefType = String.escapeSingleQuotes(refType);
        String escapedName = String.escapeSingleQuotes(componentName);

        // Level 1: server-side filter on both type + name
        try {
            String soql =
                'SELECT ' + selectFields +
                ' FROM MetadataComponentDependency' +
                ' WHERE RefMetadataComponentType = \'' + escapedRefType + '\'' +
                ' AND RefMetadataComponentName = \'' + escapedName + '\'';

            return queryToolingRecords(soql, maxRows);
        } catch (ToolingApiClientException ex) {
            if (!isQueryError(ex)) {
                throw ex;
            }
        }

        // Level 2: type filter only + client-side name filter
        try {
            String soql =
                'SELECT ' + selectFields +
                ' FROM MetadataComponentDependency' +
                ' WHERE RefMetadataComponentType = \'' + escapedRefType + '\'';

            ToolingQueryResponse result = queryToolingRecords(soql, maxRows);
            return filterByRefName(result, componentName);
        } catch (ToolingApiClientException ex) {
            if (!isQueryError(ex)) {
                throw ex;
            }
        }

        // Level 3: name filter only (when RefMetadataComponentType value is unsupported)
        try {
            String soql =
                'SELECT ' + selectFields +
                ' FROM MetadataComponentDependency' +
                ' WHERE RefMetadataComponentName = \'' + escapedName + '\'';

            return queryToolingRecords(soql, maxRows);
        } catch (ToolingApiClientException ex) {
            if (!isQueryError(ex)) {
                throw ex;
            }
        }

        // Level 4: no ref-field filters + full client-side filtering (last resort)
        ToolingQueryResponse result = queryToolingRecords(
            'SELECT ' + selectFields +
            ' FROM MetadataComponentDependency',
            maxRows
        );
        return filterByRefName(result, componentName);
    }

    /**
     * Client-side filter: keep only records matching RefMetadataComponentName.
     */
    private static ToolingQueryResponse filterByRefName(ToolingQueryResponse result, String componentName) {
        List<Object> filtered = new List<Object>();
        for (Object recordObj : result.records) {
            Map<String, Object> row = asMap(recordObj);
            if (row == null) continue;
            String refName = row.get('RefMetadataComponentName') == null ? null : String.valueOf(row.get('RefMetadataComponentName'));
            if (refName != null && refName.equalsIgnoreCase(componentName)) {
                filtered.add(recordObj);
            }
        }
        result.records = filtered;
        return result;
    }

    private static String parseErrorBodyMessage(String responseBody) {
        if (String.isBlank(responseBody)) {
            return null;
        }

        try {
            Object payload = JSON.deserializeUntyped(responseBody);

            Map<String, Object> mapPayload = asMap(payload);
            if (mapPayload != null) {
                if (mapPayload.containsKey('message') && mapPayload.get('message') != null) {
                    return String.valueOf(mapPayload.get('message'));
                }

                List<Object> errors = asList(mapPayload.get('errors'));
                if (errors != null && !errors.isEmpty()) {
                    Map<String, Object> firstError = asMap(errors[0]);
                    if (firstError != null && firstError.get('message') != null) {
                        return String.valueOf(firstError.get('message'));
                    }
                }
            }

            List<Object> listPayload = asList(payload);
            if (listPayload != null && !listPayload.isEmpty()) {
                Map<String, Object> first = asMap(listPayload[0]);
                if (first != null && first.get('message') != null) {
                    return String.valueOf(first.get('message'));
                }
            }
        } catch (Exception ex) {
            return null;
        }

        return null;
    }
}
