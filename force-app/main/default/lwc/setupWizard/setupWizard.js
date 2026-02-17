import { LightningElement, track } from 'lwc';
import testConnection from '@salesforce/apex/DependencyController.testConnection';

export default class SetupWizard extends LightningElement {
    @track connectionStatus = 'pending'; // pending | testing | success | error
    @track connectionError = '';

    get steps() {
        return [
            {
                number: 1,
                isTestStep: false,
                sectionName: 'step-1',
                title: 'Create External Client App',
                description: 'Go to Setup → Apps → External Client App Manager → New External Client App. Enable OAuth with scopes "Manage user data via APIs (api)" and "Perform requests at any time (refresh_token, offline_access)". Use a placeholder Callback URL for now — you\'ll update it after Step 2. Copy the Consumer Key and Consumer Secret from the Settings tab.'
            },
            {
                number: 2,
                isTestStep: false,
                sectionName: 'step-2',
                title: 'Create Auth. Provider',
                description: 'Go to Setup → Identity → Auth. Providers → New. Provider Type: Salesforce. Paste Consumer Key and Consumer Secret from Step 1. Default Scopes: full refresh_token. After saving, copy the Callback URL from the Salesforce Configuration section and update your External Client App with it.'
            },
            {
                number: 3,
                isTestStep: false,
                sectionName: 'step-3',
                title: 'Create External Credential',
                description: 'Go to Setup → Security → Named Credentials → External Credentials tab → New. OAuth 2.0, Browser Flow, select your Auth Provider. Create a Principal (Named Principal), then click Authenticate and log in with your admin credentials.'
            },
            {
                number: 4,
                isTestStep: false,
                sectionName: 'step-4',
                title: 'Create Named Credential',
                description: 'Go to Setup → Security → Named Credentials → Named Credentials tab → New. Label: WITU_ToolingAPI (Name auto-populates). URL: your org\'s My Domain (e.g. https://yourorg.my.salesforce.com). External Credential: select the one from Step 3. Leave "Generate Authorization Header" checked.'
            },
            {
                number: 5,
                isTestStep: false,
                sectionName: 'step-5',
                title: 'Grant Permission Set Access',
                description: 'Edit the Where Is This Used? User (or Admin) permission set. Under External Credential Principal Access, enable your External Credential Principal. Assign the permission set to all users who will run the app.'
            },
            {
                number: 6,
                isTestStep: true,
                sectionName: 'step-6',
                title: 'Test Connection',
                description: 'Click the button below to verify the connection to the Tooling API.'
            }
        ];
    }

    get isTestPending() {
        return this.connectionStatus === 'pending';
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

    get testButtonLabel() {
        if (this.isTesting) return 'Testing...';
        if (this.isConnected) return 'Connected ✓';
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
            const result = await testConnection();
            this.connectionStatus = result ? 'success' : 'error';
            if (!result) {
                this.connectionError = 'Connection test returned false. Please verify your Named Credential setup.';
            }
        } catch (error) {
            this.connectionStatus = 'error';
            this.connectionError = error?.body?.message || error?.message || 'Unknown error during connection test.';
        }
    }
}
