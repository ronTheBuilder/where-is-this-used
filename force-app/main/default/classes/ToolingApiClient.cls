public with sharing class ToolingApiClient {
    public static final String NAMED_CREDENTIAL = 'callout:WITU_ToolingAPI';
    public static final String TOOLING_BASE_PATH = '/services/data/v65.0/tooling';

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
            if ((status == 429 || status == 503) && attempt < MAX_RETRY_ATTEMPTS) {
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
