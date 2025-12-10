# SAP Integration - Secrets Management Guide

## Overview

This guide explains how to manage SAP credentials securely for both **local development** and **Azure deployment**.

---

## Azure Deployment (Production)

### How It Works

In Azure, SAP credentials are stored in **Azure Key Vault** and accessed by the Function App using **Managed Identity** (no passwords in code or config).

### Setup Steps

#### 1. Deploy Infrastructure

The Bicep deployment automatically:
- Creates Key Vault secrets for SAP credentials
- Grants Function App Managed Identity access to Key Vault
- Configures Function App environment variables

```bash
cd core-platform-infra/bicep

# Update parameters first
# Edit environments/dev.bicepparam with actual SAP credentials

# Deploy
az deployment group create \
  --resource-group rg-platform-dev \
  --template-file main.bicep \
  --parameters environments/dev.bicepparam
```

#### 2. Verify Key Vault Secrets

After deployment, verify secrets were created:

```bash
# List secrets
az keyvault secret list \
  --vault-name vendormdm-kv-dev \
  --query "[?starts_with(name, 'SAP-')].name" \
  --output table

# Expected secrets:
# - SAP-Hostname
# - SAP-SystemNumber
# - SAP-Client
# - SAP-SystemAccount-Username
# - SAP-SystemAccount-Password
```

#### 3. Function App Configuration

The Function App automatically gets these environment variables from Bicep deployment:

```
KeyVaultUri=https://vendormdm-kv-dev.vault.azure.net/
EventHubNamespace=evh-sap-events-dev.servicebus.windows.net
```

The Function App uses **Managed Identity** to read secrets from Key Vault at runtime.

---

## Local Development

### Option 1: Use Azure Key Vault (Recommended)

**Prerequisites**:
- Azure CLI installed and logged in (`az login`)
- Access to the dev Key Vault

**Setup**:

1. **Login to Azure**:
   ```bash
   az login
   ```

2. **Update `local.settings.json`**:
   ```json
   {
     "Values": {
       "KeyVaultUri": "https://vendormdm-kv-dev.vault.azure.net/"
     }
   }
   ```

3. **Run Functions locally**:
   ```bash
   cd core-artifact-processors/src/VendorMdm.Artifacts
   func start
   ```

The Function App will use your Azure CLI credentials (via `DefaultAzureCredential`) to read secrets from Key Vault.

**Pros**:
- ✅ Same secrets as Azure (no drift)
- ✅ No passwords in local files
- ✅ Easy to switch between environments

**Cons**:
- ⚠️ Requires Azure CLI login
- ⚠️ Requires network access to Azure

---

### Option 2: Use Local Environment Variables (Alternative)

For offline development or when Key Vault is not accessible.

**Setup**:

1. **Update `local.settings.json`**:
   ```json
   {
     "Values": {
       "KeyVaultUri": "",
       "SAP-Hostname": "sap-dev.company.com",
       "SAP-SystemNumber": "00",
       "SAP-Client": "100",
       "SAP-SystemAccount-Username": "SAPVENDORPORTAL",
       "SAP-SystemAccount-Password": "YOUR_PASSWORD_HERE"
     }
   }
   ```

2. **Update Worker Function** to read from environment variables when Key Vault is not available:

   The `SapVendorWorkerFunction.cs` already has fallback logic:
   ```csharp
   if (_keyVaultClient == null)
   {
       // Fallback to environment variables
       hostname = Environment.GetEnvironmentVariable("SAP-Hostname");
       username = Environment.GetEnvironmentVariable("SAP-SystemAccount-Username");
       password = Environment.GetEnvironmentVariable("SAP-SystemAccount-Password");
   }
   ```

**Pros**:
- ✅ Works offline
- ✅ No Azure dependencies

**Cons**:
- ❌ Passwords in local files (add to .gitignore!)
- ❌ Manual sync with Azure secrets

---

### Option 3: Use .NET User Secrets (Most Secure for Local)

**Prerequisites**:
- .NET SDK installed

**Setup**:

1. **Initialize user secrets**:
   ```bash
   cd core-artifact-processors/src/VendorMdm.Artifacts
   dotnet user-secrets init
   ```

2. **Set SAP secrets**:
   ```bash
   dotnet user-secrets set "SAP-Hostname" "sap-dev.company.com"
   dotnet user-secrets set "SAP-SystemNumber" "00"
   dotnet user-secrets set "SAP-Client" "100"
   dotnet user-secrets set "SAP-SystemAccount-Username" "SAPVENDORPORTAL"
   dotnet user-secrets set "SAP-SystemAccount-Password" "YOUR_PASSWORD_HERE"
   ```

3. **List secrets** (verify):
   ```bash
   dotnet user-secrets list
   ```

4. **Update `local.settings.json`** (remove Key Vault URI):
   ```json
   {
     "Values": {
       "KeyVaultUri": ""
     }
   }
   ```

5. **Run Functions**:
   ```bash
   func start
   ```

**Pros**:
- ✅ Secrets stored outside project directory
- ✅ Never committed to Git
- ✅ Per-user configuration

**Cons**:
- ⚠️ Only works on local machine
- ⚠️ Requires manual setup per developer

**Location**: User secrets are stored in:
- **Windows**: `%APPDATA%\Microsoft\UserSecrets\<user_secrets_id>\secrets.json`
- **macOS/Linux**: `~/.microsoft/usersecrets/<user_secrets_id>/secrets.json`

---

## Security Best Practices

### ✅ DO

1. **Use Key Vault in Azure** (Managed Identity)
2. **Use User Secrets for local development**
3. **Add `local.settings.json` to `.gitignore`**
4. **Rotate SAP passwords regularly**
5. **Use least-privilege SAP accounts** (only BAPI permissions needed)

### ❌ DON'T

1. **Never commit passwords to Git**
2. **Never hardcode credentials in code**
3. **Never share `local.settings.json` with passwords**
4. **Never use production SAP credentials locally**

---

## Troubleshooting

### Issue: "Key Vault access denied"

**Cause**: Function App Managed Identity doesn't have access to Key Vault

**Solution**:
```bash
# Re-deploy Key Vault RBAC
az deployment group create \
  --resource-group rg-platform-dev \
  --template-file bicep/modules/keyvault-rbac.bicep \
  --parameters keyVaultName=vendormdm-kv-dev \
               functionAppPrincipalId=<FUNCTION_APP_PRINCIPAL_ID>
```

---

### Issue: "DefaultAzureCredential failed" (local)

**Cause**: Not logged in to Azure CLI

**Solution**:
```bash
az login
az account show  # Verify correct subscription
```

---

### Issue: "SAP connection failed"

**Cause**: Incorrect SAP credentials or network issue

**Solution**:
1. Verify SAP credentials in Key Vault:
   ```bash
   az keyvault secret show --vault-name vendormdm-kv-dev --name SAP-Hostname
   ```

2. Test SAP connectivity from Azure:
   - Use Z_TEST_AZURE_PUSH ABAP program
   - Check VNet/VPN connectivity

3. Check Function App logs:
   ```bash
   az functionapp logs tail \
     --name func-platform-dev \
     --resource-group rg-platform-dev
   ```

---

## Environment Variables Reference

### Required for All Environments

| Variable | Description | Example |
|----------|-------------|---------|
| `KeyVaultUri` | Key Vault endpoint | `https://vendormdm-kv-dev.vault.azure.net/` |
| `ServiceBusConnection` | Service Bus connection string | `Endpoint=sb://...` |

### Required in Key Vault (Azure)

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `SAP-Hostname` | SAP server hostname or IP | `sap-dev.company.com` |
| `SAP-SystemNumber` | SAP system number | `00` |
| `SAP-Client` | SAP client number | `100` |
| `SAP-SystemAccount-Username` | SAP system account username | `SAPVENDORPORTAL` |
| `SAP-SystemAccount-Password` | SAP system account password | `<secure-password>` |

### Optional (Phase 2+)

| Variable | Description | Example |
|----------|-------------|---------|
| `EventHubNamespace` | Event Hubs namespace | `evh-sap-events-dev.servicebus.windows.net` |
| `SAP-SNC-PSE` | SNC Personal Security Environment (Phase 3) | `<base64-encoded-pse>` |

---

## Quick Start Checklist

### For Azure Deployment

- [ ] Update `dev.bicepparam` with SAP credentials
- [ ] Deploy infrastructure (`az deployment group create...`)
- [ ] Verify Key Vault secrets created
- [ ] Verify Function App has Managed Identity access
- [ ] Test SAP connectivity with Z_TEST_AZURE_PUSH

### For Local Development

- [ ] Choose secrets management option (Key Vault, User Secrets, or Env Vars)
- [ ] Configure `local.settings.json`
- [ ] Login to Azure CLI (if using Key Vault)
- [ ] Set user secrets (if using User Secrets)
- [ ] Run `func start` and test locally

---

## Additional Resources

- [Azure Key Vault Documentation](https://docs.microsoft.com/azure/key-vault/)
- [Managed Identity Documentation](https://docs.microsoft.com/azure/active-directory/managed-identities-azure-resources/)
- [.NET User Secrets Documentation](https://docs.microsoft.com/aspnet/core/security/app-secrets)
- [DefaultAzureCredential Documentation](https://docs.microsoft.com/dotnet/api/azure.identity.defaultazurecredential)
