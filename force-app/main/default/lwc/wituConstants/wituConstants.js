/**
 * Shared color, icon, and label constants across WITU visualization components.
 * Consolidates TYPE_COLORS (blastRadiusGraph), NODE_COLORS (dataJourneyView),
 * TYPE_ICONS (blastRadiusGraph + dependencyResults), and ICON_BY_TYPE (processFlowMap).
 */

// Metadata type colors — used by Blast Radius, Dependency Results
export const METADATA_TYPE_COLORS = {
    Flow: '#1B96FF',
    FlowDefinition: '#1B96FF',
    ApexClass: '#9050E9',
    ApexTrigger: '#BA01FF',
    ValidationRule: '#FE5C4C',
    Layout: '#04844B',
    LightningComponentBundle: '#0D9DDA',
    AuraDefinitionBundle: '#0D9DDA',
    Page: '#706E6B',
    EmailTemplate: '#706E6B',
    CustomField: '#706E6B'
};

// Data Journey node-type colors
export const NODE_TYPE_COLORS = {
    field: '#1B96FF',
    flow: '#9050E9',
    apex: '#04844B',
    validationRule: '#FE5C4C',
    formula: '#0D9DDA',
    workflowUpdate: '#FE9339'
};

// Special node colors
export const ROOT_COLOR = '#FF538A';
export const CYCLE_COLOR = '#FE9339';
export const DEFAULT_COLOR = '#5F6A7D';

// Blast Radius text icons (used inside SVG nodes)
export const TYPE_TEXT_ICONS = {
    Flow: '\u26A1',
    FlowDefinition: '\u26A1',
    ApexClass: '<>',
    ApexTrigger: '<>',
    ValidationRule: '\u2713',
    Layout: '\u25A4',
    LightningComponentBundle: '\u25C7',
    AuraDefinitionBundle: '\u25C7'
};

// SLDS icon names — used by Dependency Results and Process Flow Map
export const TYPE_SLDS_ICONS = {
    ApexClass: 'custom:custom24',
    ApexTrigger: 'custom:custom24',
    Flow: 'standard:flow',
    FlowDefinition: 'standard:flow',
    ValidationRule: 'standard:record',
    Layout: 'standard:record_lookup',
    LightningComponentBundle: 'standard:lightning_component',
    AuraDefinitionBundle: 'standard:lightning_component',
    Page: 'standard:visualforce_page',
    EmailTemplate: 'standard:email',
    CustomField: 'standard:custom_notification'
};

// Process Flow Map step icons
export const PROCESS_STEP_ICONS = {
    BeforeTrigger: 'custom:custom24',
    AfterTrigger: 'custom:custom24',
    ValidationRule: 'utility:warning',
    Flow_BeforeSave: 'standard:flow',
    Flow_AfterSave: 'standard:flow',
    Flow_Async: 'utility:clock',
    WorkflowRule: 'utility:workflow',
    WorkflowFieldUpdate: 'utility:change_record_type',
    AssignmentRule: 'utility:user_role',
    AutoResponseRule: 'utility:email',
    EntitlementRule: 'utility:task'
};

// Human-readable labels for metadata types
export const TYPE_LABELS = {
    FlowDefinition: 'Flow',
    ApexClass: 'Apex Class',
    ApexTrigger: 'Apex Trigger',
    ValidationRule: 'Validation Rule',
    LightningComponentBundle: 'LWC',
    AuraDefinitionBundle: 'Aura',
    Layout: 'Layout',
    Page: 'Visualforce Page',
    EmailTemplate: 'Email Template',
    CustomField: 'Custom Field'
};

// Data Journey node-type labels
export const NODE_TYPE_LABELS = {
    field: 'Field',
    flow: 'Flow',
    apex: 'Apex',
    validationRule: 'Validation Rule',
    formula: 'Formula',
    workflowUpdate: 'Workflow Field Update'
};

// Data Journey relationship labels
export const RELATIONSHIP_LABELS = {
    writes_to: 'writes to',
    read_by: 'reads from',
    triggers: 'triggers',
    feeds_into: 'feeds into'
};
