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
            throw new AuraHandledException('Object name is required.');
        }

        Map<String, Schema.SObjectType> described = Schema.getGlobalDescribe();
        if (!described.containsKey(objectName)) {
            throw new AuraHandledException('Object not found: ' + objectName);
        }

        Schema.DescribeSObjectResult objectDescribe = described.get(objectName).getDescribe();
        if (!objectDescribe.isAccessible()) {
            throw new AuraHandledException('You do not have access to object: ' + objectName);
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
            throw new AuraHandledException(ex.getMessage());
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to load flows: ' + ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<DependencyService.MetadataOption> getApexClasses() {
        try {
            return DependencyService.getApexClasses();
        } catch (DependencyService.DependencyServiceException ex) {
            throw new AuraHandledException(ex.getMessage());
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to load Apex classes: ' + ex.getMessage());
        }
    }

}
