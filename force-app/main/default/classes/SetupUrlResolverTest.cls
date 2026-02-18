@IsTest
private with sharing class SetupUrlResolverTest {

    @IsTest
    static void resolve_apexClassWithId() {
        String url = SetupUrlResolver.resolve('ApexClass', '01p4x000001234AAA', 'AccountService');
        System.assertEquals('/lightning/setup/ApexClasses/page?address=/01p4x000001234AAA', url);
    }

    @IsTest
    static void resolve_flowWithId() {
        String url = SetupUrlResolver.resolve('Flow', '3014x000000ABCABC', 'Route_By_Industry');
        System.assertEquals('/builder_platform_interaction/flowBuilder.app?flowId=3014x000000ABCABC', url);
    }

    @IsTest
    static void resolve_validationRuleWithId() {
        String url = SetupUrlResolver.resolve('ValidationRule', '03d4x000000XYZXYZ', 'Account.Require_Industry');
        System.assertEquals('/lightning/setup/ObjectManager/Account/ValidationRules/03d4x000000XYZXYZ/view', url);
    }

    @IsTest
    static void resolve_customFieldWithId() {
        String url = SetupUrlResolver.resolve('CustomField', '00N4x000000ABCABC', 'Account.MyField__c');
        System.assertEquals('/lightning/setup/ObjectManager/Account/FieldsAndRelationships/00N4x000000ABCABC/view', url);
    }

    @IsTest
    static void resolve_fallsBackToListPage() {
        String url = SetupUrlResolver.resolve('ApexClass', null, 'AccountService');
        System.assertEquals('/lightning/setup/ApexClasses/home', url);
    }

    @IsTest
    static void resolve_unknownTypeFallsBackToSetup() {
        String url = SetupUrlResolver.resolve('SomeUnknownType', null, 'Foo');
        System.assertEquals('/lightning/setup/home', url);
    }

    @IsTest
    static void resolve_blankTypeReturnsHome() {
        String url = SetupUrlResolver.resolve(null, null, null);
        System.assertEquals('/lightning/setup/home', url);
    }

    @IsTest
    static void resolve_recordTypeWithId() {
        String url = SetupUrlResolver.resolve('RecordType', '0124x000000ABCABC', 'Account.Enterprise');
        System.assertEquals('/lightning/setup/ObjectManager/Account/RecordTypes/0124x000000ABCABC/view', url);
    }

    @IsTest
    static void extractObjectName_validName() {
        System.assertEquals('Account', SetupUrlResolver.extractObjectName('Account.Industry'));
        System.assertEquals(null, SetupUrlResolver.extractObjectName('AccountService'));
        System.assertEquals(null, SetupUrlResolver.extractObjectName(null));
    }
}
