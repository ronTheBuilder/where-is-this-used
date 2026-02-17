# Salesforce Tooling API Self-Callout Setup Guide

## Context

This guide sets up a callout from a Salesforce org to its own Tooling API. The Tooling API treats even same-org calls as external incoming requests, so you need proper OAuth authentication. This uses the modern **External Client App** approach (not Connected Apps, which are being phased out as of Spring '26).

## What You're Creating

You need 4 components, created in this order:

1. **External Client App** — the OAuth application (replaces Connected App)
2. **Auth. Provider** — tells Salesforce how to authenticate using the External Client App
3. **External Credential** — stores the authenticated session/token
4. **Named Credential** — the endpoint URL your Apex code references

Plus permission set configuration and your Apex callout code.

---

## Step 1: Create the External Client App

1. Go to **Setup → Apps → External Client App Manager**
2. Click **New External Client App**
3. Fill in:
   - **External Client App Name**: e.g. `Tooling API Self Callout`
   - **Contact Email**: your email
   - **Distribution State**: `Local`
4. Expand **API (Enable OAuth Settings)** and check **Enable OAuth**
5. For **Callback URL**: enter a placeholder for now (e.g. `https://login.salesforce.com/services/authcallback/placeholder`) — you'll update this after Step 2
6. Select these **OAuth Scopes**:
   - `Manage user data via APIs (api)`
   - `Perform requests at any time (refresh_token, offline_access)`
7. Optionally uncheck **Require Proof Key for Code Exchange (PKCE)** to simplify the flow (or leave it checked for more security — just be consistent with the Auth. Provider setting)
8. Click **Create**
9. Go to the app's **Settings** tab → click **Consumer Key and Secret**
10. **Copy the Consumer Key and Consumer Secret** — you need these in Step 2

---

## Step 2: Create the Auth. Provider

1. Go to **Setup → Identity → Auth. Providers**
2. Click **New**
3. Fill in:
   - **Provider Type**: `Salesforce`
   - **Name**: e.g. `Tooling_API_Auth`
   - **URL Suffix**: e.g. `ToolingAPIAuth`
   - **Consumer Key**: paste from Step 1
   - **Consumer Secret**: paste from Step 1
   - **Default Scopes**: `full refresh_token`
4. Leave Authorize Endpoint URL and Token Endpoint URL at their defaults (`https://login.salesforce.com/services/oauth2/authorize` and `https://login.salesforce.com/services/oauth2/token`)
5. If your External Client App has PKCE enabled, check **Use Proof Key for Code Exchange (PKCE) Extension** here too
6. Click **Save**
7. After saving, scroll down to the **Salesforce Configuration** section at the bottom of the page
8. **Copy the Callback URL** shown there
9. Go back to your External Client App from Step 1 and **update the Callback URL** with the real one you just copied

---

## Step 3: Create the External Credential

1. Go to **Setup → Security → Named Credentials**
2. Switch to the **External Credentials** tab
3. Click **New**
4. Fill in:
   - **Label**: e.g. `Tooling API Credential`
   - **Name**: auto-populates
   - **Authentication Protocol**: `OAuth 2.0`
   - **Authentication Flow Type**: `Browser Flow`
   - **Auth Provider**: select the Auth. Provider you created in Step 2
   - **Scope**: leave blank (already defined on the Auth. Provider)
5. Click **Save**
6. On the detail page, scroll down to the **Principals** section
7. Click **New** to create a principal:
   - **Parameter Name**: e.g. `Tooling_API_Principal`
   - **Sequence Number**: `1`
   - **Identity Type**: `Named Principal`
8. Click **Save**
9. On the principal row, click the **Actions** dropdown → **Authenticate**
10. You will be redirected to a Salesforce login page — **log in with your admin credentials**
11. After successful login, the status should show **"Authenticated as [your username]"**

---

## Step 4: Create the Named Credential

1. Go to **Setup → Security → Named Credentials**
2. Stay on the **Named Credentials** tab
3. Click **New**
4. Fill in:
   - **Label**: e.g. `Tooling API`
   - **Name**: auto-populates (e.g. `Tooling_API`) — **for Where Is This Used?, use `WITU_ToolingAPI`** so it matches the app's expected Named Credential name
   - **URL**: your org's My Domain URL, e.g. `https://yourorg.my.salesforce.com`
   - **External Credential**: select the External Credential from Step 3
   - **Generate Authorization Header**: leave checked
5. Click **Save**

---

## Step 5: Grant Permission Set Access

Users (or the running user context) need access to the External Credential Principal.

1. Go to **Setup → Permission Sets**
2. Create a new Permission Set or edit an existing one (e.g. **Where Is This Used? User** or **Where Is This Used? Admin**)
3. In the Permission Set, go to **External Credential Principal Access** (under the Apps section)
4. Click **Edit**
5. Move your External Credential Principal (e.g. `Tooling API Credential - Tooling_API_Principal`) to the **Enabled** list
6. Click **Save**
7. **Assign this Permission Set** to all users who will execute the callout (including integration users, the running user for scheduled jobs, etc.)

---

## Step 6: Apex Callout Code

Use the Named Credential name with the `callout:` prefix. Where Is This Used? expects the Named Credential name **`WITU_ToolingAPI`**.

```apex
public class ToolingAPIService {

    public static String queryTooling(String query) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:WITU_ToolingAPI/services/data/v62.0/tooling/query/?q='
            + EncodingUtil.urlEncode(query, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            return res.getBody();
        } else {
            throw new CalloutException('Tooling API error: ' + res.getStatusCode() + ' ' + res.getBody());
        }
    }
}
```

### Example: Query all Validation Rules

```apex
String result = ToolingAPIService.queryTooling(
    'SELECT Id, ValidationName, EntityDefinition.QualifiedApiName FROM ValidationRule'
);
System.debug(result);
```

### Example: Query all Flows

```apex
String result = ToolingAPIService.queryTooling(
    'SELECT Id, MasterLabel, ProcessType, Status FROM Flow WHERE Status = \'Active\''
);
System.debug(result);
```

---

## Why This Approach (Instead of UserInfo.getSessionId())

Using `UserInfo.getSessionId()` fails silently in many contexts:

- Record-triggered Flows
- Scheduled Apex
- Queueable Apex
- @future methods
- Platform Events

The Named Credential approach works in **all execution contexts** because it manages its own OAuth token independently of the user's session. It also keeps credentials out of your code entirely.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Authentication fails at Step 3 (Authenticate principal) | Check that the Callback URL in the External Client App matches the one generated by the Auth. Provider |
| `401 Unauthorized` on callout | Verify the Permission Set with External Credential Principal Access is assigned to the running user |
| `PKCE error` during authentication | Make sure PKCE is either enabled on BOTH the External Client App and Auth. Provider, or disabled on both |
| Named Credential not showing External Credential | Ensure the External Credential exists and has at least one Principal |
| Callout works in Execute Anonymous but fails in triggers | This is the main reason to use Named Credentials — confirm the Permission Set is assigned to the context user (e.g., the automated process user) |
