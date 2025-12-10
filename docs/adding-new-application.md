# Adding a New Application to the Platform

This guide explains how to add a new application that leverages the core platform infrastructure and services.

## Overview

The platform architecture separates **Core Platform** (reusable foundation) from **Application Layer** (domain-specific apps). This enables you to build multiple applications on the same shared infrastructure.

---

## Prerequisites

Before adding a new application, ensure the core platform is deployed:

1. ✅ `core-platform-infra` - Infrastructure deployed
2. ✅ `core-apis` - Platform APIs running
3. ✅ `core-artifact-processors` - Background processors running

---

## Step-by-Step Guide

### 1. Create Application Repository

Create a new repository for your application:

```bash
# Example: Customer Portal application
mkdir customer-portal-swa
cd customer-portal-swa
git init
```

**Naming Convention**: `{app-name}-{type}`
- Frontend: `customer-portal-swa`, `analytics-dashboard-swa`
- Backend APIs: `customer-apis`, `analytics-apis`
- Processors: `customer-processors`, `analytics-processors`

---

### 2. Configure Application to Use Core Platform

#### Frontend Application (Static Web App)

**package.json** - Add core platform API endpoint:
```json
{
  "name": "customer-portal-swa",
  "scripts": {
    "dev": "vite",
    "build": "vite build"
  }
}
```

**.env.example** - Reference core platform services:
```bash
# Core Platform API
VITE_API_URL=https://core-apis.azurewebsites.net

# Application-specific config
VITE_APP_NAME=Customer Portal
```

**src/config.ts** - Configure API client:
```typescript
export const config = {
  apiUrl: import.meta.env.VITE_API_URL,
  // Use core platform endpoints
  endpoints: {
    attachments: '/api/attachments',
    auth: '/api/auth',
    // Your app-specific endpoints
    customers: '/api/customers'
  }
}
```

#### Backend API (if needed)

If your application needs domain-specific APIs:

**appsettings.json** - Reference core platform resources:
```json
{
  "ConnectionStrings": {
    "Sql": "Server=...",  // From core-platform-infra
    "Cosmos": "...",      // From core-platform-infra
    "ServiceBus": "..."   // From core-platform-infra
  },
  "KeyVault": {
    "VaultUrl": "https://vendormdm-kv-{env}.vault.azure.net/"
  }
}
```

---

### 3. Leverage Core Platform Services

Your application can use these core platform services:

#### Attachment Service
```typescript
// Upload file using core platform
const uploadFile = async (file: File) => {
  const formData = new FormData();
  formData.append('file', file);
  
  const response = await fetch(`${config.apiUrl}/api/attachments`, {
    method: 'POST',
    body: formData
  });
  
  return response.json();
}
```

#### Email Notifications
```csharp
// Publish email event to Service Bus (handled by core-artifact-processors)
await serviceBusClient.SendMessageAsync(new ServiceBusMessage {
    Subject = "invitation-emails",
    Body = BinaryData.FromObjectAsJson(new {
        To = "customer@example.com",
        Subject = "Welcome",
        Body = "Welcome to our platform"
    })
});
```

#### Authentication
```typescript
// Use core platform auth
import { useAuth } from '@/hooks/useAuth';

const MyComponent = () => {
  const { user, login, logout } = useAuth();
  // Core platform handles auth
}
```

---

### 4. Infrastructure Configuration

Your application uses the **existing** core platform infrastructure. No new infrastructure deployment needed!

#### Static Web App Configuration

**staticwebapp.config.json**:
```json
{
  "routes": [
    {
      "route": "/api/*",
      "rewrite": "https://core-apis.azurewebsites.net/api/*"
    }
  ],
  "navigationFallback": {
    "rewrite": "/index.html"
  }
}
```

---

### 5. CI/CD Setup

Use shared workflows from `github-policies`:

**.github/workflows/deploy.yml**:
```yaml
name: Deploy Customer Portal

on:
  push:
    branches: [main]

jobs:
  build-and-deploy:
    uses: org/github-policies/.github/workflows/swa-deploy.yml@main
    with:
      app-name: customer-portal-swa
      environment: production
    secrets:
      AZURE_CREDENTIALS: ${{ secrets.AZURE_CREDENTIALS }}
```

---

### 6. Deployment

Deploy your application to the existing platform:

```bash
# Frontend (Static Web App)
az staticwebapp create \
  --name customer-portal-swa \
  --resource-group rg-platform-prod \
  --location eastus

# Link to core platform APIs (already deployed)
# Configure API endpoint in app settings
az staticwebapp appsettings set \
  --name customer-portal-swa \
  --setting-names VITE_API_URL=https://core-apis.azurewebsites.net
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                  Core Platform (Shared)                  │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  ┌──────────────────┐  ┌──────────────────┐            │
│  │ core-platform-   │  │    core-apis     │            │
│  │     infra        │  │                  │            │
│  │                  │  │ • Attachments    │            │
│  │ • Key Vault      │→ │ • Auth           │            │
│  │ • SQL Database   │  │ • Common APIs    │            │
│  │ • Cosmos DB      │  └──────────────────┘            │
│  │ • Service Bus    │                                   │
│  └──────────────────┘  ┌──────────────────┐            │
│                        │ core-artifact-   │            │
│                        │   processors     │            │
│                        │                  │            │
│                        │ • Email Service  │            │
│                        │ • Notifications  │            │
│                        └──────────────────┘            │
└─────────────────────────────────────────────────────────┘
                           ↑
                           │ Uses platform services
                           │
┌──────────────────────────┴──────────────────────────────┐
│                  Application Layer                       │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  ┌──────────────────┐  ┌──────────────────┐            │
│  │ vendor-portal-   │  │ customer-portal- │            │
│  │      swa         │  │      swa         │  (New App) │
│  │                  │  │                  │            │
│  │ Vendor MDM UI    │  │ Customer UI      │            │
│  └──────────────────┘  └──────────────────┘            │
│                                                           │
│  ┌──────────────────┐                                   │
│  │ analytics-       │                                   │
│  │ dashboard-swa    │  (Future App)                     │
│  │                  │                                   │
│  │ Analytics UI     │                                   │
│  └──────────────────┘                                   │
└─────────────────────────────────────────────────────────┘
```

---

## Example: Customer Portal Application

### Repository Structure

```
customer-portal-swa/
├── .github/
│   └── workflows/
│       └── deploy.yml          # Uses github-policies workflows
├── src/
│   ├── components/
│   ├── pages/
│   ├── services/
│   │   └── api.ts             # Calls core-apis endpoints
│   └── config.ts              # Platform configuration
├── .env.example               # Core platform API URLs
├── package.json
├── staticwebapp.config.json   # Route to core-apis
└── README.md
```

### Key Files

**src/services/api.ts**:
```typescript
import { config } from '@/config';

export const api = {
  // Use core platform attachment service
  uploadFile: async (file: File) => {
    const formData = new FormData();
    formData.append('file', file);
    return fetch(`${config.apiUrl}/api/attachments`, {
      method: 'POST',
      body: formData
    });
  },
  
  // Your app-specific endpoints
  getCustomers: async () => {
    return fetch(`${config.apiUrl}/api/customers`);
  }
}
```

---

## Benefits of This Architecture

✅ **No Infrastructure Duplication**: All apps share the same Key Vault, databases, and messaging  
✅ **Reusable Services**: Attachments, auth, email handled by core platform  
✅ **Independent Deployment**: Each app deploys independently  
✅ **Consistent Standards**: Shared CI/CD workflows from `github-policies`  
✅ **Cost Efficient**: Single infrastructure supports multiple applications  

---

## Checklist for New Application

- [ ] Create new repository with appropriate naming
- [ ] Configure to use core platform API endpoints
- [ ] Reference core platform services (attachments, auth, email)
- [ ] Set up CI/CD using `github-policies` workflows
- [ ] Deploy to Azure (Static Web App or App Service)
- [ ] Configure environment variables to point to core platform
- [ ] Test integration with core platform services
- [ ] Document app-specific features

---

## Support

For questions or issues:
- Review `core-apis` documentation for available endpoints
- Check `core-artifact-processors` for available background services
- Refer to `github-policies` for CI/CD workflow templates
- Contact platform team for infrastructure access

---

**Last Updated**: December 9, 2025
