# Where Is This Used? (WITU)

> A Salesforce native dependency analysis tool that shows you where your metadata is referenced — fields, flows, Apex classes, custom labels, and more.

[![Salesforce API](https://img.shields.io/badge/Salesforce-API%20v66.0-blue)](https://developer.salesforce.com/)
[![License: PolyForm Noncommercial](https://img.shields.io/badge/License-PolyForm%20NC%201.0-orange)](LICENSE)

## What It Does

WITU queries the Salesforce Tooling API to find dependencies between metadata components. Select a field, flow, Apex class, or custom label, and instantly see everything that references it.

### Supported Metadata Types

| Type | Search | Found In Results |
|------|--------|-----------------|
| **Standard Fields** | ✅ | ✅ |
| **Custom Fields** | ✅ | ✅ |
| **Flows** (incl. managed packages) | ✅ | ✅ |
| **Apex Classes** (incl. managed packages) | ✅ | ✅ |
| **Custom Labels** (incl. managed packages) | ✅ | ✅ |
| **Validation Rules** | ✅ | ✅ |
| **Record Types** | ✅ | ✅ |
| **Platform Events** | ✅ | ✅ |
| **Custom Metadata Types** | ✅ | ✅ |
| **Page Layouts** | — | ✅ (supplementary scan) |
| **Lightning Record Pages** | — | ✅ (supplementary scan) |

### Features

- 🔍 **Multi-level Tooling API fallback** — works across different org types and API versions
- 🏷️ **Managed package support** — search dependencies in installed packages (namespace-aware)
- 🎛️ **Smart object filter** — hide system objects (ChangeEvent, History, Share, etc.) with one toggle
- ⚡ **Active/all flow filter** — toggle between active-only and all flows with status labels
- 📄 **Page Layout scanning** — finds field references on Page Layouts (not tracked by MetadataComponentDependency)
- ⚡ **Lightning Record Page scanning** — finds field references on FlexiPages
- 🏗️ **Blast Radius analysis** — visualize the impact of changing a field or component
- 🗺️ **Data Journey mapping** — trace how data flows through your org
- 🔄 **Process Flow mapping** — see record-triggered flow execution order
- 📦 **Export** — download results for documentation

## Installation

### Prerequisites

- Salesforce org (Enterprise, Performance, Unlimited, or Developer edition)
- **Named Credential** called `WITU_ToolingAPI` pointing to your org's Tooling API
- System Administrator or user with the **Where Is This Used? User** permission set

### Deploy to Your Org

```bash
# Clone the repo
git clone https://github.com/ronTheBuilder/where-is-this-used.git
cd where-is-this-used

# Deploy to your org
sf project deploy start --source-dir force-app --target-org your-org-alias

# Assign permission set
sf org assign permset --name Where_Is_This_Used_User --target-org your-org-alias
```

### Named Credential Setup

WITU uses a Named Credential to make Tooling API callouts. Create one with:

1. Go to **Setup → Named Credentials → New**
2. **Label:** `WITU ToolingAPI`
3. **Name:** `WITU_ToolingAPI`
4. **URL:** `https://your-instance.my.salesforce.com` (your org's URL)
5. **Identity Type:** Named Principal or Per User
6. **Authentication Protocol:** OAuth 2.0

> The Named Credential approach is more secure than using `UserInfo.getSessionId()` and works in Lightning components.

### Permission Sets

| Permission Set | Description |
|---|---|
| `Where_Is_This_Used_User` | Basic access — search dependencies |
| `Where_Is_This_Used_Admin` | Full access — all features including blast radius and data journey |

## Architecture

```
┌─────────────────────────────────────────────────┐
│                    LWC Layer                     │
│  dependencyFinder → metadataPicker              │
│  dependencyResults → exportMenu                 │
│  blastRadiusGraph │ dataJourneyView             │
│  processFlowMap   │ setupWizard                 │
└──────────────┬──────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────┐
│               Controller Layer                   │
│  DependencyController │ MetadataPickerController │
│  BlastRadiusController│ DataJourneyController    │
│  ProcessFlowController                           │
└──────────────┬──────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────┐
│                Service Layer                     │
│  DependencyService │ BlastRadiusService          │
│  DataJourneyService│ ProcessFlowService          │
│  FlowFieldAnalyzer │ SetupUrlResolver            │
└──────────────┬──────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────┐
│              ToolingApiClient                    │
│  Named Credential → Tooling API REST            │
│  Multi-level query fallback                      │
│  Layout & FlexiPage metadata scanning            │
└─────────────────────────────────────────────────┘
```

## Known Limitations

These are **Salesforce platform limitations** — the Tooling API's `MetadataComponentDependency` object (still in Beta) does not track all dependency types:

| Not Tracked | Workaround |
|---|---|
| Reports / Dashboards | None — Salesforce doesn't expose these dependencies |
| List Views | None |
| Profiles / Permission Sets | None |
| Workflow Field Updates | None |
| Approval Processes | None |
| Criteria-Based Sharing Rules | None |
| Quick Action Layouts | None |
| Page Layouts → Fields | ✅ WITU scans layout metadata directly |
| Lightning Record Pages → Fields | ✅ WITU scans FlexiPage metadata directly |

## Contributing

Contributions welcome! This is a noncommercial open source project. See [LICENSE](LICENSE) for terms.

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-improvement`)
3. Commit your changes
4. Push and open a Pull Request

## License

This project is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE).

**You are free to:**
- Use, modify, and distribute this software for any **noncommercial** purpose
- Use it in your Salesforce org for internal business operations
- Fork and contribute improvements

**You may not:**
- Sell this software or include it in a commercial product
- Offer it as a paid service (SaaS, consulting add-on, etc.)

> Required Notice: Copyright Simon Buurman / Tytovate (https://github.com/ronTheBuilder/where-is-this-used)
