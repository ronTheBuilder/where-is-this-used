public with sharing class SetupUrlResolver {

    /**
     * Resolve the Setup URL for a specific metadata component.
     * Returns an ID-specific URL when possible, otherwise falls back to the list page.
     */
    public static String resolve(String metadataComponentType, String metadataComponentId, String metadataComponentName) {
        if (String.isBlank(metadataComponentType)) {
            return '/lightning/setup/home';
        }

        String objectName = extractObjectName(metadataComponentName);

        // Try ID-specific URL first
        if (String.isNotBlank(metadataComponentId)) {
            String idUrl = resolveWithId(metadataComponentType, metadataComponentId, objectName);
            if (idUrl != null) {
                return idUrl;
            }
        }

        // Fallback to list page
        return resolveListPage(metadataComponentType, objectName);
    }

    @TestVisible
    private static String extractObjectName(String componentName) {
        if (String.isBlank(componentName) || !componentName.contains('.')) {
            return null;
        }
        return componentName.substringBefore('.');
    }

    private static String resolveWithId(String componentType, String componentId, String objectName) {
        switch on componentType {
            when 'ApexClass' {
                return '/lightning/setup/ApexClasses/page?address=/' + componentId;
            }
            when 'ApexTrigger' {
                return '/lightning/setup/ApexTriggers/page?address=/' + componentId;
            }
            when 'Flow', 'FlowDefinition' {
                return '/builder_platform_interaction/flowBuilder.app?flowId=' + componentId;
            }
            when 'ValidationRule' {
                if (String.isNotBlank(objectName)) {
                    return '/lightning/setup/ObjectManager/' + objectName + '/ValidationRules/' + componentId + '/view';
                }
            }
            when 'Layout' {
                if (String.isNotBlank(objectName)) {
                    return '/lightning/setup/ObjectManager/' + objectName + '/PageLayouts/' + componentId + '/view';
                }
            }
            when 'LightningComponentBundle' {
                return '/lightning/setup/LightningComponentBundles/page?address=/' + componentId;
            }
            when 'CustomField' {
                if (String.isNotBlank(objectName)) {
                    return '/lightning/setup/ObjectManager/' + objectName + '/FieldsAndRelationships/' + componentId + '/view';
                }
            }
            when 'CustomObject', 'StandardEntity' {
                if (String.isNotBlank(objectName)) {
                    return '/lightning/setup/ObjectManager/' + objectName + '/Details/view';
                }
            }
            when 'RecordType' {
                if (String.isNotBlank(objectName)) {
                    return '/lightning/setup/ObjectManager/' + objectName + '/RecordTypes/' + componentId + '/view';
                }
            }
            when 'PermissionSet' {
                return '/lightning/setup/PermSets/page?address=/' + componentId;
            }
            when 'Profile' {
                return '/lightning/setup/Profiles/page?address=/' + componentId;
            }
            when 'Report' {
                return '/lightning/o/Report/' + componentId + '/view';
            }
            when 'Dashboard' {
                return '/lightning/o/Dashboard/' + componentId + '/view';
            }
            when 'Page' {
                return '/lightning/setup/ApexPages/page?address=/' + componentId;
            }
            when 'QuickAction' {
                if (String.isNotBlank(objectName)) {
                    return '/lightning/setup/ObjectManager/' + objectName + '/ButtonsLinksActions/view';
                }
            }
        }
        return null;
    }

    private static String resolveListPage(String componentType, String objectName) {
        Map<String, String> listPages = new Map<String, String>{
            'ApexClass' => '/lightning/setup/ApexClasses/home',
            'ApexTrigger' => '/lightning/setup/ApexTriggers/home',
            'Flow' => '/lightning/setup/Flows/home',
            'FlowDefinition' => '/lightning/setup/Flows/home',
            'LightningComponentBundle' => '/lightning/setup/LightningComponentBundles/home',
            'AuraDefinitionBundle' => '/lightning/setup/AuraDefinitionBundles/home',
            'FlexiPage' => '/lightning/setup/FlexiPageList/home',
            'CustomLabel' => '/lightning/setup/ExternalStrings/home',
            'PermissionSet' => '/lightning/setup/PermSets/home',
            'Profile' => '/lightning/setup/Profiles/home',
            'EmailTemplate' => '/lightning/setup/CommunicationTemplatesEmail/home',
            'Report' => '/lightning/o/Report/home',
            'Dashboard' => '/lightning/o/Dashboard/home',
            'Page' => '/lightning/setup/ApexPages/home',
            'CustomTab' => '/lightning/setup/CustomTabs/home',
            'StaticResource' => '/lightning/setup/StaticResources/home'
        };

        if (listPages.containsKey(componentType)) {
            return listPages.get(componentType);
        }

        // Object-specific types fall back to ObjectManager
        Set<String> objectTypes = new Set<String>{
            'ValidationRule', 'Layout', 'CustomField', 'CustomObject',
            'StandardEntity', 'RecordType', 'QuickAction', 'WorkflowRule'
        };
        if (objectTypes.contains(componentType)) {
            if (String.isNotBlank(objectName)) {
                return '/lightning/setup/ObjectManager/' + objectName + '/Details/view';
            }
            return '/lightning/setup/ObjectManager/home';
        }

        return '/lightning/setup/home';
    }
}
