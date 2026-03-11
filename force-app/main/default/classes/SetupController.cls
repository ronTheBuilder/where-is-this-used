public with sharing class SetupController {

    @AuraEnabled
    public static String getAuthMode() {
        ToolingApiClient.enforceAccess();
        WITU_Settings__c settings = WITU_Settings__c.getInstance();
        if (settings != null && settings.Use_Named_Credential__c == true) {
            return 'namedCredential';
        }
        return 'session';
    }

    @AuraEnabled
    public static void setAuthMode(String mode) {
        ToolingApiClient.enforceAccess();
        WITU_Settings__c settings = WITU_Settings__c.getOrgDefaults();
        settings.Use_Named_Credential__c = (mode == 'namedCredential');
        upsert settings;
    }

    @AuraEnabled
    public static Boolean testConnection() {
        return DependencyService.testConnection();
    }

    @AuraEnabled
    public static String getOrgDomainUrl() {
        ToolingApiClient.enforceAccess();
        return URL.getOrgDomainUrl().toExternalForm();
    }

    @AuraEnabled
    public static List<UserInfo> getUsers(String searchTerm) {
        ToolingApiClient.enforceAccess();
        String likeClause = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        List<User> users = [
            SELECT Id, Name, Username, Email, IsActive
            FROM User
            WHERE IsActive = true
            AND (Name LIKE :likeClause OR Username LIKE :likeClause OR Email LIKE :likeClause)
            ORDER BY Name
            LIMIT 50
        ];
        List<UserInfo> results = new List<UserInfo>();
        for (User u : users) {
            results.add(new UserInfo(u));
        }
        return results;
    }

    @AuraEnabled
    public static void assignPermissionSet(List<Id> userIds, String permSetName) {
        ToolingApiClient.enforceAccess();
        if (userIds == null || userIds.isEmpty()) {
            throw new AuraHandledException('No users specified.');
        }
        if (String.isBlank(permSetName)) {
            throw new AuraHandledException('Permission set name is required.');
        }

        List<PermissionSet> psList = [SELECT Id FROM PermissionSet WHERE Name = :permSetName LIMIT 1];
        if (psList.isEmpty()) {
            throw new AuraHandledException('Permission set "' + permSetName + '" not found.');
        }
        Id psId = psList[0].Id;

        Set<Id> alreadyAssigned = new Set<Id>();
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId FROM PermissionSetAssignment
            WHERE PermissionSetId = :psId AND AssigneeId IN :userIds
        ]) {
            alreadyAssigned.add(psa.AssigneeId);
        }

        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (Id userId : userIds) {
            if (!alreadyAssigned.contains(userId)) {
                assignments.add(new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = psId));
            }
        }
        if (!assignments.isEmpty()) {
            insert assignments;
        }
    }

    @AuraEnabled
    public static List<PermissionAssignmentInfo> getPermissionSetAssignments() {
        ToolingApiClient.enforceAccess();
        List<PermissionSetAssignment> psas = [
            SELECT Id, Assignee.Name, Assignee.Username, PermissionSet.Name, PermissionSet.Label
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name IN ('Where_Is_This_Used_User', 'Where_Is_This_Used_Admin')
            ORDER BY Assignee.Name
        ];
        List<PermissionAssignmentInfo> results = new List<PermissionAssignmentInfo>();
        for (PermissionSetAssignment psa : psas) {
            results.add(new PermissionAssignmentInfo(psa));
        }
        return results;
    }

    @AuraEnabled
    public static Map<String, String> createNamedCredentialSetup(String authProviderName) {
        ToolingApiClient.enforceAccess();
        if (String.isBlank(authProviderName)) {
            throw new AuraHandledException('Auth Provider developer name is required.');
        }

        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        String sessionId = ToolingApiClient.getSessionId();
        Map<String, String> result = new Map<String, String>();

        // Step 1: Create External Credential via Tooling API
        Map<String, Object> ecMetadata = new Map<String, Object>{
            'label' => 'WITU Tooling Credential',
            'authenticationProtocol' => 'Oauth',
            'externalCredentialParameters' => new List<Object>{
                new Map<String, Object>{
                    'parameterName' => 'AuthProvider',
                    'parameterType' => 'AuthProvider',
                    'authProvider' => authProviderName
                }
            }
        };
        Map<String, Object> ecBody = new Map<String, Object>{
            'FullName' => 'WITU_Tooling_Credential',
            'Metadata' => ecMetadata
        };

        HttpResponse ecResp = sendSetupRequest(
            'POST',
            baseUrl + ToolingApiClient.TOOLING_BASE_PATH + '/sobjects/ExternalCredential',
            JSON.serialize(ecBody),
            sessionId
        );

        if (ecResp.getStatusCode() >= 200 && ecResp.getStatusCode() < 300) {
            result.put('externalCredential', 'created');
        } else {
            String ecError = parseSetupError(ecResp.getBody());
            if (ecError.containsIgnoreCase('already exists') || ecError.containsIgnoreCase('duplicate')) {
                result.put('externalCredential', 'exists');
            } else {
                throw new AuraHandledException('Failed to create External Credential: ' + ecError);
            }
        }

        // Step 2: Create Named Credential via Tooling API
        Map<String, Object> ncMetadata = new Map<String, Object>{
            'label' => 'WITU ToolingAPI',
            'namedCredentialType' => 'SecuredEndpoint',
            'namedCredentialParameters' => new List<Object>{
                new Map<String, Object>{
                    'parameterType' => 'Authentication',
                    'parameterName' => 'Authentication',
                    'externalCredential' => 'WITU_Tooling_Credential'
                },
                new Map<String, Object>{
                    'parameterType' => 'Url',
                    'parameterName' => 'Url',
                    'parameterValue' => baseUrl
                }
            }
        };
        Map<String, Object> ncBody = new Map<String, Object>{
            'FullName' => 'WITU_ToolingAPI',
            'Metadata' => ncMetadata
        };

        HttpResponse ncResp = sendSetupRequest(
            'POST',
            baseUrl + ToolingApiClient.TOOLING_BASE_PATH + '/sobjects/NamedCredential',
            JSON.serialize(ncBody),
            sessionId
        );

        if (ncResp.getStatusCode() >= 200 && ncResp.getStatusCode() < 300) {
            result.put('namedCredential', 'created');
        } else {
            String ncError = parseSetupError(ncResp.getBody());
            if (ncError.containsIgnoreCase('already exists') || ncError.containsIgnoreCase('duplicate')) {
                result.put('namedCredential', 'exists');
            } else {
                throw new AuraHandledException('Failed to create Named Credential: ' + ncError);
            }
        }

        return result;
    }

    private static HttpResponse sendSetupRequest(String method, String endpoint, String body, String sessionId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod(method);
        req.setHeader('Authorization', 'Bearer ' + sessionId);
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(30000);
        if (body != null) {
            req.setBody(body);
        }
        return new Http().send(req);
    }

    private static String parseSetupError(String responseBody) {
        if (String.isBlank(responseBody)) {
            return 'Unknown error';
        }
        try {
            Object parsed = JSON.deserializeUntyped(responseBody);
            if (parsed instanceof List<Object>) {
                List<Object> errors = (List<Object>) parsed;
                if (!errors.isEmpty()) {
                    Map<String, Object> first = (Map<String, Object>) errors[0];
                    if (first.containsKey('message')) {
                        return String.valueOf(first.get('message'));
                    }
                }
            } else if (parsed instanceof Map<String, Object>) {
                Map<String, Object> errorMap = (Map<String, Object>) parsed;
                if (errorMap.containsKey('message')) {
                    return String.valueOf(errorMap.get('message'));
                }
            }
        } catch (Exception ex) {
            // Fall through
        }
        return responseBody;
    }

    @AuraEnabled
    public static void removePermissionSetAssignment(Id assignmentId) {
        ToolingApiClient.enforceAccess();
        if (assignmentId == null) {
            throw new AuraHandledException('Assignment ID is required.');
        }
        List<PermissionSetAssignment> toDelete = [
            SELECT Id FROM PermissionSetAssignment
            WHERE Id = :assignmentId
            AND PermissionSet.Name IN ('Where_Is_This_Used_User', 'Where_Is_This_Used_Admin')
            LIMIT 1
        ];
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
    }

    public class UserInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String username;
        @AuraEnabled public String email;

        public UserInfo(User u) {
            this.id = u.Id;
            this.name = u.Name;
            this.username = u.Username;
            this.email = u.Email;
        }
    }

    public class PermissionAssignmentInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String userName;
        @AuraEnabled public String userUsername;
        @AuraEnabled public String permissionSetName;
        @AuraEnabled public String permissionSetLabel;

        public PermissionAssignmentInfo(PermissionSetAssignment psa) {
            this.id = psa.Id;
            this.userName = psa.Assignee.Name;
            this.userUsername = psa.Assignee.Username;
            this.permissionSetName = psa.PermissionSet.Name;
            this.permissionSetLabel = psa.PermissionSet.Label;
        }
    }
}
