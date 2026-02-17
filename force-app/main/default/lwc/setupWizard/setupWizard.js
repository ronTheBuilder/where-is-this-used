import { LightningElement, track } from 'lwc';
import testConnection from '@salesforce/apex/DependencyController.testConnection';

export default class SetupWizard extends LightningElement {
    @track connectionStatus = 'pending'; // pending | testing | success | error
    @track connectionError = '';

    get steps() {
        return [
            {
                number: 1,
                sectionName: 'step-1',
                title: 'Create Connected App',
                description: 'Go to Setup → App Manager → New Connected App. Enable OAuth with callback URL https://login.salesforce.com/services/oauth2/callback. Add scopes: "Full access (full)" and "Perform requests at any time (refresh_token)". Copy the Consumer Key and Consumer Secret.'
            },
            {
                number: 2,
                sectionName: 'step-2',
                title: 'Create Auth. Provider',
                description: 'Go to Setup → Auth. Providers → New. Provider Type: Salesforce. Name: WITU Auth Provider. Paste Consumer Key and Consumer Secret. Default Scopes: full refresh_token.'
            },
            {
                number: 3,
                sectionName: 'step-3',
                title: 'Create Named Credential',
                description: 'Go to Setup → Named Credentials → New Legacy. Label: WITU_ToolingAPI. URL: https://[your-domain].my.salesforce.com. Identity Type: Named Principal. Authentication Protocol: OAuth 2.0. Authentication Provider: WITU Auth Provider. Check "Start Authentication Flow on Save".'
            },
            {
                number: 4,
                sectionName: 'step-4',
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
