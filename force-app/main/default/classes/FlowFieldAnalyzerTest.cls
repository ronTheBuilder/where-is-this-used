@IsTest
private with sharing class FlowFieldAnalyzerTest {
    @IsTest
    static void analyzeFlow_extractsReadsWritesAndSubflows() {
        Map<String, Object> metadata = (Map<String, Object>) JSON.deserializeUntyped(
            '{' +
                '"decisions":[{"rules":[{"conditionLogic":"AND","conditions":[{"leftValueReference":"$Record.Industry","operator":"EqualTo","rightValue":{"stringValue":"Tech"}}]}]}],' +
                '"assignments":[{"assignmentItems":[{"assignToReference":"$Record.Region__c","value":{"elementReference":"$Record.BillingCountry"}}]}],' +
                '"recordUpdates":[{"inputAssignments":[{"field":"Opportunity.Type","value":{"elementReference":"$Record.Industry"}}]}],' +
                '"recordCreates":[{"inputAssignments":[{"field":"Case.Origin","value":{"stringValue":"Web"}}]}],' +
                '"recordLookups":[{"filters":[{"field":"Account.Industry","operator":"EqualTo","value":{"elementReference":"$Record.Industry"}}]}],' +
                '"formulas":[{"name":"f1","expression":"IF($Record.Industry=\"Tech\", Account.Region__c, Account.SLA__c)"}],' +
                '"subflows":[{"flowName":"Subflow_A"},{"flowName":"Subflow_B"}]' +
            '}'
        );

        FlowFieldAnalyzer.FlowFieldAnalysis result = FlowFieldAnalyzer.analyzeFlow(metadata);

        System.assert(result.fieldsRead.contains('$Record.Industry'));
        System.assert(result.fieldsRead.contains('Account.Industry'));
        System.assert(result.fieldsRead.contains('Account.Region__c'));
        System.assert(result.fieldsWritten.contains('$Record.Region__c'));
        System.assert(result.fieldsWritten.contains('Opportunity.Type'));
        System.assert(result.fieldsWritten.contains('Case.Origin'));
        System.assert(result.subflowsCalled.contains('Subflow_A'));
        System.assert(result.subflowsCalled.contains('Subflow_B'));
    }

    @IsTest
    static void analyzeFlow_handlesNullMetadata() {
        FlowFieldAnalyzer.FlowFieldAnalysis result = FlowFieldAnalyzer.analyzeFlow(null);
        System.assertEquals(0, result.fieldsRead.size());
        System.assertEquals(0, result.fieldsWritten.size());
        System.assertEquals(0, result.subflowsCalled.size());
    }
}
