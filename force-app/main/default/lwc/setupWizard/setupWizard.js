import { LightningElement, track } from 'lwc';
import getAuthMode from '@salesforce/apex/SetupController.getAuthMode';
import setAuthMode from '@salesforce/apex/SetupController.setAuthMode';
import testConnectionApex from '@salesforce/apex/SetupController.testConnection';
import getOrgDomainUrl from '@salesforce/apex/SetupController.getOrgDomainUrl';
import getUsers from '@salesforce/apex/SetupController.getUsers';
import assignPermissionSet from '@salesforce/apex/SetupController.assignPermissionSet';
import getPermissionSetAssignments from '@salesforce/apex/SetupController.getPermissionSetAssignments';
import removePermissionSetAssignment from '@salesforce/apex/SetupController.removePermissionSetAssignment';
import createNamedCredentialSetup from '@salesforce/apex/SetupController.createNamedCredentialSetup';

export default class SetupWizard extends LightningElement {
    @track activeSection = 'mode';
    @track authMode = 'session';
    @track orgDomainUrl = '';

    // Mode selection
    @track modeSaving = false;
    @track modeError = '';
    @track isModeComplete = false;

    // Session setup
    @track isTestingSession = false;
    @track isSessionSetupComplete = false;
    @track sessionSetupError = '';

    // Connection test
    @track connectionStatus = 'pending';
    @track connectionError = '';

    // User search & assignment
    @track userSearchTerm = '';
    @track userResults = [];
    @track selectedPermSet = 'Where_Is_This_Used_User';
    @track isSearchingUsers = false;
    @track isAssigning = false;
    @track assignSuccess = false;
    @track assignError = '';

    // Assignments list
    @track assignments = [];
    @track isLoadingAssignments = false;

    _searchTimeout;

    connectedCallback() {
        this.loadAuthMode();
        this.loadOrgDomain();
    }

    async loadAuthMode() {
        try {
            this.authMode = await getAuthMode();
            this.isModeComplete = true;
        } catch (error) {
            this.authMode = 'session';
        }
    }

    async loadOrgDomain() {
        try {
            this.orgDomainUrl = await getOrgDomainUrl();
        } catch (error) {
            // Non-critical
        }
    }

    // --- Navigation ---

    handleNavClick(event) {
        event.preventDefault();
        const section = event.currentTarget.dataset.section;
        this.activeSection = section;
        if (section === 'permissions') {
            this.loadAssignments();
        }
    }

    get isSessionMode() {
        return this.authMode === 'session';
    }

    get modeNavClass() {
        return 'slds-nav-vertical__item' + (this.activeSection === 'mode' ? ' slds-is-active' : '');
    }

    get sessionNavClass() {
        return 'slds-nav-vertical__item' + (this.activeSection === 'session' ? ' slds-is-active' : '');
    }

    get ncNavClass() {
        return 'slds-nav-vertical__item' + (this.activeSection === 'namedCredential' ? ' slds-is-active' : '');
    }

    get permNavClass() {
        return 'slds-nav-vertical__item' + (this.activeSection === 'permissions' ? ' slds-is-active' : '');
    }

    get testNavClass() {
        return 'slds-nav-vertical__item' + (this.activeSection === 'test' ? ' slds-is-active' : '');
    }

    get isModeSection() {
        return this.activeSection === 'mode';
    }

    get isSessionSection() {
        return this.activeSection === 'session';
    }

    get isNcSection() {
        return this.activeSection === 'namedCredential';
    }

    get isPermSection() {
        return this.activeSection === 'permissions';
    }

    get isTestSection() {
        return this.activeSection === 'test';
    }

    // --- Connection Mode ---

    get sessionCardClass() {
        return 'mode-card' + (this.authMode === 'session' ? ' selected' : '');
    }

    get ncCardClass() {
        return 'mode-card' + (this.authMode === 'namedCredential' ? ' selected' : '');
    }

    async handleModeSelect(event) {
        const mode = event.currentTarget.dataset.mode;
        if (mode === this.authMode) return;

        this.modeSaving = true;
        this.modeError = '';
        try {
            await setAuthMode({ mode });
            this.authMode = mode;
            this.isModeComplete = true;
            // Reset connection test when mode changes
            this.connectionStatus = 'pending';
            this.connectionError = '';
            this.isSessionSetupComplete = false;
        } catch (error) {
            this.modeError = error?.body?.message || 'Failed to save auth mode.';
        } finally {
            this.modeSaving = false;
        }
    }

    // --- Session Setup ---

    handleCopyDomain() {
        if (this.orgDomainUrl && navigator.clipboard) {
            navigator.clipboard.writeText(this.orgDomainUrl);
        }
    }

    async handleTestSession() {
        this.isTestingSession = true;
        this.sessionSetupError = '';
        this.isSessionSetupComplete = false;

        try {
            const result = await testConnectionApex();
            if (result) {
                this.isSessionSetupComplete = true;
            } else {
                this.sessionSetupError = 'Connection test returned false. Verify the Remote Site Setting is configured.';
            }
        } catch (error) {
            this.sessionSetupError = error?.body?.message || 'Failed to connect. Make sure the Remote Site Setting has been added.';
        } finally {
            this.isTestingSession = false;
        }
    }

    // --- Named Credential ---

    @track authProviderName = '';
    @track isCreatingNc = false;
    @track ncCreateSuccess = false;
    @track ncCreateSuccessMessage = '';
    @track ncCreateError = '';

    get ncActiveSections() {
        return ['nc-step-1', 'nc-step-2', 'nc-step-3', 'nc-step-4'];
    }

    get ncCreateButtonLabel() {
        return this.isCreatingNc ? 'Creating...' : 'Create Named Credential';
    }

    get ncCreateDisabled() {
        return !this.authProviderName || this.isCreatingNc;
    }

    handleAuthProviderNameChange(event) {
        this.authProviderName = event.target.value;
        this.ncCreateSuccess = false;
        this.ncCreateError = '';
    }

    async handleCreateNamedCredential() {
        this.isCreatingNc = true;
        this.ncCreateSuccess = false;
        this.ncCreateError = '';

        try {
            const result = await createNamedCredentialSetup({ authProviderName: this.authProviderName });
            this.ncCreateSuccess = true;
            const ecStatus = result.externalCredential === 'created' ? 'created' : 'already exists';
            const ncStatus = result.namedCredential === 'created' ? 'created' : 'already exists';
            this.ncCreateSuccessMessage = `External Credential: ${ecStatus}. Named Credential: ${ncStatus}. Proceed to Step 4 to authenticate.`;
        } catch (error) {
            this.ncCreateError = error?.body?.message || 'Failed to create Named Credential setup.';
        } finally {
            this.isCreatingNc = false;
        }
    }

    // --- Test Connection ---

    get currentAuthModeLabel() {
        return this.authMode === 'session' ? 'Session Auth' : 'Named Credential';
    }

    get isTesting() {
        return this.connectionStatus === 'testing';
    }

    get isConnected() {
        return this.connectionStatus === 'success';
    }

    get isConnectionError() {
        return this.connectionStatus === 'error';
    }

    get isTestComplete() {
        return this.connectionStatus === 'success';
    }

    get testButtonLabel() {
        if (this.isTesting) return 'Testing...';
        if (this.isConnected) return 'Connected';
        return 'Test Connection';
    }

    get testButtonVariant() {
        if (this.isConnected) return 'success';
        if (this.isConnectionError) return 'destructive';
        return 'brand';
    }

    async handleTestConnection() {
        this.connectionStatus = 'testing';
        this.connectionError = '';

        try {
            const result = await testConnectionApex();
            this.connectionStatus = result ? 'success' : 'error';
            if (!result) {
                this.connectionError = 'Connection test returned false. Please verify your setup.';
            }
        } catch (error) {
            this.connectionStatus = 'error';
            this.connectionError = error?.body?.message || error?.message || 'Unknown error during connection test.';
        }
    }

    // --- Permissions ---

    get permSetOptions() {
        return [
            { label: 'Where Is This Used? User', value: 'Where_Is_This_Used_User' },
            { label: 'Where Is This Used? Admin', value: 'Where_Is_This_Used_Admin' }
        ];
    }

    handlePermSetChange(event) {
        this.selectedPermSet = event.detail.value;
    }

    handleUserSearch(event) {
        this.userSearchTerm = event.target.value;
        this.assignSuccess = false;
        this.assignError = '';

        if (this._searchTimeout) {
            clearTimeout(this._searchTimeout);
        }

        if (this.userSearchTerm.length < 2) {
            this.userResults = [];
            return;
        }

        this._searchTimeout = setTimeout(() => {
            this.searchUsers();
        }, 300);
    }

    async searchUsers() {
        this.isSearchingUsers = true;
        try {
            const results = await getUsers({ searchTerm: this.userSearchTerm });
            this.userResults = results.map(u => ({ ...u, selected: false }));
        } catch (error) {
            this.userResults = [];
        } finally {
            this.isSearchingUsers = false;
        }
    }

    get hasUserResults() {
        return this.userResults.length > 0;
    }

    get selectedUserIds() {
        return this.userResults.filter(u => u.selected).map(u => u.id);
    }

    get allUsersSelected() {
        return this.userResults.length > 0 && this.userResults.every(u => u.selected);
    }

    get assignDisabled() {
        return this.selectedUserIds.length === 0 || this.isAssigning;
    }

    handleUserSelect(event) {
        const userId = event.target.dataset.id;
        this.userResults = this.userResults.map(u =>
            u.id === userId ? { ...u, selected: event.target.checked } : u
        );
    }

    handleSelectAll(event) {
        const checked = event.target.checked;
        this.userResults = this.userResults.map(u => ({ ...u, selected: checked }));
    }

    async handleAssign() {
        this.isAssigning = true;
        this.assignSuccess = false;
        this.assignError = '';

        try {
            await assignPermissionSet({
                userIds: this.selectedUserIds,
                permSetName: this.selectedPermSet
            });
            this.assignSuccess = true;
            this.userResults = this.userResults.map(u => ({ ...u, selected: false }));
            this.loadAssignments();
        } catch (error) {
            this.assignError = error?.body?.message || 'Failed to assign permission set.';
        } finally {
            this.isAssigning = false;
        }
    }

    // --- Assignments ---

    get hasAssignments() {
        return this.assignments.length > 0;
    }

    async loadAssignments() {
        this.isLoadingAssignments = true;
        try {
            this.assignments = await getPermissionSetAssignments();
        } catch (error) {
            this.assignments = [];
        } finally {
            this.isLoadingAssignments = false;
        }
    }

    async handleRemoveAssignment(event) {
        const assignmentId = event.currentTarget.dataset.id;
        try {
            await removePermissionSetAssignment({ assignmentId });
            this.loadAssignments();
        } catch (error) {
            this.assignError = error?.body?.message || 'Failed to remove assignment.';
        }
    }
}
