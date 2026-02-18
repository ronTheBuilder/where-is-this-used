public with sharing class MetadataPickerController {
    public class FieldOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String metadataType;

        public FieldOption(String label, String value, String metadataType) {
            this.label = label;
            this.value = value;
            this.metadataType = metadataType;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<DependencyService.MetadataOption> getObjects() {
        Map<String, Schema.SObjectType> described = Schema.getGlobalDescribe();
        List<DependencyService.MetadataOption> results = new List<DependencyService.MetadataOption>();

        List<String> objectNames = new List<String>(described.keySet());
        objectNames.sort();
        for (String objectApiName : objectNames) {
            Schema.DescribeSObjectResult objectDescribe = described.get(objectApiName).getDescribe();
            if (objectDescribe.isAccessible() && !objectDescribe.isCustomSetting()) {
                results.add(new DependencyService.MetadataOption(objectDescribe.getLabel(), objectApiName));
            }
        }
        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getFields(String objectName) {
        if (String.isBlank(objectName)) {
            AuraHandledException ahe = new AuraHandledException('Object name is required.');

            ahe.setMessage('Object name is required.');

            throw ahe;
        }

        Map<String, Schema.SObjectType> described = Schema.getGlobalDescribe();
        if (!described.containsKey(objectName)) {
            AuraHandledException ahe = new AuraHandledException('Object not found: ' + objectName);

            ahe.setMessage('Object not found: ' + objectName);

            throw ahe;
        }

        Schema.DescribeSObjectResult objectDescribe = described.get(objectName).getDescribe();
        if (!objectDescribe.isAccessible()) {
            AuraHandledException ahe = new AuraHandledException('You do not have access to object: ' + objectName);

            ahe.setMessage('You do not have access to object: ' + objectName);

            throw ahe;
        }

        List<FieldOption> options = new List<FieldOption>();
        Map<String, Schema.SObjectField> fieldsMap = objectDescribe.fields.getMap();

        List<String> fieldNames = new List<String>(fieldsMap.keySet());
        fieldNames.sort();
        for (String fieldApiName : fieldNames) {
            Schema.DescribeFieldResult fieldDescribe = fieldsMap.get(fieldApiName).getDescribe();
            if (!fieldDescribe.isAccessible()) {
                continue;
            }

            String metadataType = fieldApiName.endsWith('__c') ? 'Custom Field' : 'Standard Field';
            options.add(new FieldOption(fieldDescribe.getLabel(), fieldApiName, metadataType));
        }

        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<DependencyService.MetadataOption> getFlows() {
        try {
            return DependencyService.getActiveFlows();
        } catch (DependencyService.DependencyServiceException ex) {
            AuraHandledException ahe = new AuraHandledException(ex.getMessage());

            ahe.setMessage(ex.getMessage());

            throw ahe;
        } catch (Exception ex) {
            AuraHandledException ahe = new AuraHandledException('Unable to load flows: ' + ex.getMessage());

            ahe.setMessage('Unable to load flows: ' + ex.getMessage());

            throw ahe;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<DependencyService.MetadataOption> getApexClasses() {
        try {
            return DependencyService.getApexClasses();
        } catch (DependencyService.DependencyServiceException ex) {
            AuraHandledException ahe = new AuraHandledException(ex.getMessage());

            ahe.setMessage(ex.getMessage());

            throw ahe;
        } catch (Exception ex) {
            AuraHandledException ahe = new AuraHandledException('Unable to load Apex classes: ' + ex.getMessage());

            ahe.setMessage('Unable to load Apex classes: ' + ex.getMessage());

            throw ahe;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<DependencyService.MetadataOption> getRecordTypes(String objectName) {
        try {
            return DependencyService.getRecordTypes(objectName);
        } catch (Exception ex) {
            AuraHandledException ahe = new AuraHandledException('Unable to load record types: ' + ex.getMessage());

            ahe.setMessage('Unable to load record types: ' + ex.getMessage());

            throw ahe;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<DependencyService.MetadataOption> getCustomLabels() {
        try {
            return DependencyService.getCustomLabels();
        } catch (Exception ex) {
            AuraHandledException ahe = new AuraHandledException('Unable to load custom labels: ' + ex.getMessage());

            ahe.setMessage('Unable to load custom labels: ' + ex.getMessage());

            throw ahe;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<DependencyService.MetadataOption> getValidationRules(String objectName) {
        try {
            return DependencyService.getValidationRules(objectName);
        } catch (Exception ex) {
            AuraHandledException ahe = new AuraHandledException('Unable to load validation rules: ' + ex.getMessage());

            ahe.setMessage('Unable to load validation rules: ' + ex.getMessage());

            throw ahe;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<DependencyService.MetadataOption> getPlatformEvents() {
        try {
            return DependencyService.getPlatformEvents();
        } catch (Exception ex) {
            AuraHandledException ahe = new AuraHandledException('Unable to load platform events: ' + ex.getMessage());

            ahe.setMessage('Unable to load platform events: ' + ex.getMessage());

            throw ahe;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<DependencyService.MetadataOption> getCustomMetadataTypes() {
        try {
            return DependencyService.getCustomMetadataTypes();
        } catch (Exception ex) {
            AuraHandledException ahe = new AuraHandledException('Unable to load custom metadata types: ' + ex.getMessage());

            ahe.setMessage('Unable to load custom metadata types: ' + ex.getMessage());

            throw ahe;
        }
    }

}
