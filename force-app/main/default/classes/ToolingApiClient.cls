public with sharing class ToolingApiClient {
    public static final String NAMED_CREDENTIAL = 'callout:WITU_ToolingAPI';
    public static final String TOOLING_BASE_PATH = '/services/data/v66.0/tooling';

    private static final String CUSTOM_PERMISSION = 'WITU_Access';
    private static final Integer MAX_COMPONENT_NAME_LENGTH = 255;
    private static final Integer HTTP_TIMEOUT_MS = 120000;
    private static final Integer MAX_RETRY_ATTEMPTS = 3;
    private static final Pattern VALID_COMPONENT_NAME = Pattern.compile('^[a-zA-Z][a-zA-Z0-9_.]*$');

    @TestVisible
    private static Boolean bypassAccessCheckForTests = false;

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
        if (path.startsWith('/')) {
            return NAMED_CREDENTIAL + path;
        }
        return NAMED_CREDENTIAL + '/' + path;
    }

    public static void checkCalloutBudget() {
        Integer remaining = Limits.getLimitCallouts() - Limits.getCallouts();
        if (remaining <= 0) {
            throw new ToolingApiClientException('Callout limit reached for this transaction.');
        }
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
            return 'Authentication failed. Please verify your Named Credential (WITU_ToolingAPI) is configured correctly.';
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
     * Query FlowVersionView with FlowDefinitionView relationship fields.
     * Falls back to a separate FlowDefinitionView lookup if the relationship
     * traversal is not supported on the current org.
     *
     * @param additionalFields Extra fields beyond Id (e.g. 'ProcessType, TriggerObjectOrEvent, TriggerType, Status, VersionNumber'). May be null.
     * @param whereClause      WHERE clause without the WHERE keyword (e.g. 'Status = \'Active\'')
     * @param maxRows          Maximum rows to return
     */
    public static ToolingQueryResponse queryFlowVersionsWithFallback(String additionalFields, String whereClause, Integer maxRows) {
        String relFields = 'Id, FlowDefinitionView.ApiName, FlowDefinitionView.Label';
        if (String.isNotBlank(additionalFields)) {
            relFields += ', ' + additionalFields;
        }

        String soql = 'SELECT ' + relFields + ' FROM FlowVersionView WHERE ' + whereClause;
        try {
            return queryToolingRecords(soql, maxRows);
        } catch (ToolingApiClientException ex) {
            // Only fall back if the error is query-related (400 / invalid)
            if (!ex.getMessage().contains('invalid') && !ex.getMessage().contains('400') && !ex.getMessage().contains('not found')) {
                throw ex;
            }
        }

        // Fallback: query without relationship fields, enrich with FlowDefinitionView
        String fallbackFields = 'Id';
        if (String.isNotBlank(additionalFields)) {
            fallbackFields += ', ' + additionalFields;
        }

        String fallbackSoql = 'SELECT ' + fallbackFields + ' FROM FlowVersionView WHERE ' + whereClause;
        ToolingQueryResponse result = queryToolingRecords(fallbackSoql, maxRows);

        // Build lookup from FlowDefinitionView: ActiveVersionId -> {ApiName, Label}
        ToolingQueryResponse defResult = queryToolingRecords(
            'SELECT ApiName, Label, ActiveVersionId FROM FlowDefinitionView WHERE IsActive = true',
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
                'Label' => row.get('Label') == null ? null : String.valueOf(row.get('Label'))
            });
        }

        // Enrich FlowVersionView records with FlowDefinitionView data
        for (Object rec : result.records) {
            Map<String, Object> row = asMap(rec);
            if (row == null) continue;
            String versionId = row.get('Id') == null ? null : String.valueOf(row.get('Id'));
            if (String.isBlank(versionId) || !defLookup.containsKey(versionId)) continue;
            Map<String, String> def = defLookup.get(versionId);
            row.put('FlowDefinitionView', new Map<String, Object>{
                'ApiName' => def.get('ApiName'),
                'Label' => def.get('Label')
            });
        }

        return result;
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
    public static ToolingQueryResponse queryDependenciesWithNameFallback(
        String selectFields,
        String refType,
        String componentName,
        Integer maxRows
    ) {
        String escapedRefType = String.escapeSingleQuotes(refType);
        String escapedName = String.escapeSingleQuotes(componentName);

        // Try server-side filter first
        try {
            String soql =
                'SELECT ' + selectFields +
                ' FROM MetadataComponentDependency' +
                ' WHERE RefMetadataComponentType = \'' + escapedRefType + '\'' +
                ' AND RefMetadataComponentName = \'' + escapedName + '\'';

            return queryToolingRecords(soql, maxRows);
        } catch (ToolingApiClientException ex) {
            if (!ex.getMessage().contains('invalid') && !ex.getMessage().contains('400')) {
                throw ex;
            }
        }

        // Fallback: client-side filtering
        String soql =
            'SELECT ' + selectFields +
            ' FROM MetadataComponentDependency' +
            ' WHERE RefMetadataComponentType = \'' + escapedRefType + '\'';

        ToolingQueryResponse result = queryToolingRecords(soql, maxRows);

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
