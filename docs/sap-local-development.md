# SAP Integration - Local Development & Testing Guide

## Overview

This guide explains how to develop and test SAP integration **locally without requiring actual SAP connectivity**. This enables developers to work independently and test the integration flow end-to-end.

---

## Local Development Strategies

### Strategy 1: Mock SAP Responses (Recommended for Development)

**Use Case**: Develop and test integration logic without SAP access

**How It Works**: The `SapVendorWorkerFunction` already includes mock BAPI execution that simulates SAP responses.

#### Current Mock Implementation

The Worker Function has a mock BAPI executor:

```csharp
private async Task<BapiResult> ExecuteBapiAsync(ISapConnection connection, SapVendorMessage message)
{
    // Mock implementation - simulates SAP BAPI execution
    await Task.Delay(1000); // Simulate BAPI execution time

    var mockVendorNumber = $"1{DateTime.UtcNow:yyyyMMddHHmmss}";
    
    _logger.LogInformation("BAPI executed successfully. Vendor number: {VendorNumber}", mockVendorNumber);

    return new BapiResult
    {
        Success = true,
        SapVendorNumber = mockVendorNumber,
        Errors = new List<string>()
    };
}
```

#### Testing Locally

1. **Start the Function App**:
   ```bash
   cd core-artifact-processors/src/VendorMdm.Artifacts
   func start
   ```

2. **Send a test request** (using curl, Postman, or REST Client):
   ```bash
   curl -X POST http://localhost:7071/api/sap/vendor/create \
     -H "Content-Type: application/json" \
     -d '{
       "vendor": {
         "name": "Test Vendor Inc",
         "taxId": "12-3456789",
         "street": "123 Main St",
         "city": "New York",
         "postalCode": "10001",
         "country": "US",
         "email": "contact@testvendor.com"
       },
       "userContext": {
         "role": "Vendor",
         "userId": "vendor-user-123",
         "email": "vendor@test.com",
         "invitationToken": "inv-token-abc"
       }
     }'
   ```

3. **Expected Response**:
   ```json
   {
     "correlationId": "abc-123-def-456",
     "status": "queued",
     "message": "Vendor creation request submitted to SAP",
     "estimatedProcessingTime": "2-5 seconds"
   }
   ```

4. **Check Function Logs**:
   - You'll see the message flow through Service Bus
   - Mock BAPI execution
   - Generated vendor number (e.g., `120251209194530`)

**Pros**:
- ✅ No SAP required
- ✅ Fast development cycle
- ✅ Predictable responses
- ✅ Test error scenarios easily

**Cons**:
- ⚠️ Doesn't validate actual SAP connectivity
- ⚠️ Mock responses may differ from real SAP

---

### Strategy 2: SAP Sandbox Environment

**Use Case**: Integration testing with real SAP behavior

**Requirements**:
- Access to SAP sandbox/dev system
- VPN connection to SAP network
- SAP .NET Connector (NCo) installed

#### Setup

1. **Install SAP .NET Connector**:
   ```bash
   # Download from SAP Service Marketplace
   # https://support.sap.com/nco
   
   # Add NuGet package reference
   dotnet add package SAPNCo --version 3.0.x
   ```

2. **Update Worker Function** (replace mock with real NCo):
   ```csharp
   private async Task<BapiResult> ExecuteBapiAsync(ISapConnection connection, SapVendorMessage message)
   {
       var repository = connection.Repository;
       var function = repository.CreateFunction("BAPI_VENDOR_CREATE");
       
       // Set BAPI parameters
       function.SetValue("VENDORNAME", message.Vendor.Name);
       function.SetValue("TAXID", message.Vendor.TaxId);
       // ... set other fields
       
       function.Invoke(connection);
       
       // Check return status
       var returnTable = function.GetTable("RETURN");
       if (returnTable[0].GetString("TYPE") == "E")
       {
           return new BapiResult 
           { 
               Success = false, 
               Errors = new List<string> { returnTable[0].GetString("MESSAGE") }
           };
       }
       
       var vendorNumber = function.GetValue("VENDORNUMBER");
       return new BapiResult 
       { 
           Success = true, 
           SapVendorNumber = vendorNumber 
       };
   }
   ```

3. **Configure SAP credentials** (user secrets):
   ```bash
   dotnet user-secrets set "SAP-Hostname" "sap-sandbox.company.com"
   dotnet user-secrets set "SAP-SystemNumber" "00"
   dotnet user-secrets set "SAP-Client" "100"
   dotnet user-secrets set "SAP-SystemAccount-Username" "DEVUSER"
   dotnet user-secrets set "SAP-SystemAccount-Password" "password"
   ```

4. **Test with real SAP**:
   ```bash
   func start
   # Send request (same as Strategy 1)
   ```

**Pros**:
- ✅ Real SAP validation
- ✅ Actual BAPI responses
- ✅ Test real error scenarios

**Cons**:
- ❌ Requires SAP access
- ❌ Requires VPN connection
- ❌ Slower development cycle

---

### Strategy 3: Docker SAP Mock Server (Advanced)

**Use Case**: Team-wide SAP simulation without sandbox access

**How It Works**: Run a mock SAP RFC server in Docker that responds to BAPI calls

#### Setup

1. **Create Mock SAP Server** (Python + Flask):

   `sap-mock-server/app.py`:
   ```python
   from flask import Flask, request, jsonify
   import datetime
   
   app = Flask(__name__)
   
   @app.route('/bapi/vendor/create', methods=['POST'])
   def create_vendor():
       data = request.json
       
       # Simulate BAPI_VENDOR_CREATE
       vendor_number = f"1{datetime.datetime.now().strftime('%Y%m%d%H%M%S')}"
       
       return jsonify({
           'success': True,
           'vendorNumber': vendor_number,
           'messages': []
       })
   
   @app.route('/bapi/vendor/update', methods=['POST'])
   def update_vendor():
       data = request.json
       
       return jsonify({
           'success': True,
           'messages': []
       })
   
   if __name__ == '__main__':
       app.run(host='0.0.0.0', port=8000)
   ```

2. **Dockerfile**:
   ```dockerfile
   FROM python:3.9-slim
   WORKDIR /app
   COPY requirements.txt .
   RUN pip install -r requirements.txt
   COPY app.py .
   EXPOSE 8000
   CMD ["python", "app.py"]
   ```

3. **Run Mock Server**:
   ```bash
   docker build -t sap-mock-server .
   docker run -p 8000:8000 sap-mock-server
   ```

4. **Update Worker Function** to call mock server:
   ```csharp
   private async Task<BapiResult> ExecuteBapiAsync(ISapConnection connection, SapVendorMessage message)
   {
       // Call mock SAP server instead of real SAP
       var httpClient = new HttpClient();
       var response = await httpClient.PostAsJsonAsync(
           "http://localhost:8000/bapi/vendor/create",
           message.Vendor
       );
       
       var result = await response.Content.ReadFromJsonAsync<BapiResult>();
       return result;
   }
   ```

**Pros**:
- ✅ Shared mock server for team
- ✅ Configurable responses
- ✅ Can simulate error scenarios
- ✅ No SAP license required

**Cons**:
- ⚠️ Requires Docker setup
- ⚠️ Maintenance overhead

---

### Strategy 4: Hybrid Local/Azure ⭐ (RECOMMENDED)

**Use Case**: Develop locally but use Azure services (Service Bus, Key Vault, SAP connectivity)

**How It Works**: 
- Your Function App runs **locally** on your machine
- Connects to **Azure Service Bus** (dev environment)
- Reads credentials from **Azure Key Vault** (dev environment)
- Calls **SAP through Azure VPN/ExpressRoute** (if configured)

**This is the BEST approach for realistic testing without deploying to Azure!**

#### Setup

1. **Login to Azure**:
   ```bash
   az login
   az account set --subscription "Your-Subscription-Name"
   ```

2. **Get Service Bus Connection String**:
   ```bash
   az servicebus namespace authorization-rule keys list \
     --resource-group rg-platform-dev \
     --namespace-name mdmportal-sb-dev \
     --name RootManageSharedAccessKey \
     --query primaryConnectionString \
     --output tsv
   ```

3. **Update `local.settings.json`** to point to Azure services:
   ```json
   {
     "IsEncrypted": false,
     "Values": {
       "AzureWebJobsStorage": "UseDevelopmentStorage=true",
       "FUNCTIONS_WORKER_RUNTIME": "dotnet-isolated",
       
       "ServiceBusConnection": "Endpoint=sb://mdmportal-sb-dev.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=<YOUR_KEY>",
       "KeyVaultUri": "https://vendormdm-kv-dev.vault.azure.net/",
       "EventHubNamespace": "evh-sap-events-dev.servicebus.windows.net"
     }
   }
   ```

4. **Run Functions locally**:
   ```bash
   cd core-artifact-processors/src/VendorMdm.Artifacts
   func start
   ```

5. **Send request**:
   ```bash
   curl -X POST http://localhost:7071/api/sap/vendor/create \
     -H "Content-Type: application/json" \
     -d '{ "vendor": {...}, "userContext": {...} }'
   ```

#### What Happens (Hybrid Flow)

```
┌─────────────────┐
│  Your Machine   │
│  (localhost)    │
│                 │
│  func start ────┼──┐
└─────────────────┘  │
                     │ HTTP POST
                     ▼
              ┌──────────────┐
              │  Function A  │ (local)
              │  Ingestion   │
              └──────┬───────┘
                     │ Publishes message
                     ▼
              ┌──────────────────┐
              │  Azure Service   │ ☁️
              │  Bus (dev)       │
              └──────┬───────────┘
                     │ Triggers
                     ▼
              ┌──────────────┐
              │  Function B  │ (local)
              │  Worker      │
              └──────┬───────┘
                     │ Reads secrets
                     ▼
              ┌──────────────────┐
              │  Azure Key       │ ☁️
              │  Vault (dev)     │
              └──────┬───────────┘
                     │ Gets SAP credentials
                     ▼
              ┌──────────────────┐
              │  SAP ECC 6.0     │ 🏢
              │  (via Azure VPN) │
              └──────────────────┘
```

#### Pros

- ✅ **Realistic testing** - Uses actual Azure services
- ✅ **Real SAP connectivity** - If Azure has VPN to SAP
- ✅ **No deployment needed** - Develop and test locally
- ✅ **Shared dev environment** - Team uses same Service Bus/Key Vault
- ✅ **Fast iteration** - Change code, restart, test immediately
- ✅ **Real credentials** - From Key Vault (no local secrets)
- ✅ **Certificates configured in Azure** - SNC setup done once in Azure

#### Cons

- ⚠️ Requires Azure CLI login
- ⚠️ Requires network access to Azure
- ⚠️ Shares dev Service Bus with team (coordinate testing)

#### When to Use This

**Perfect for**:
- Integration testing before deployment
- Testing SAP connectivity (if Azure has VPN)
- Debugging issues that only happen with real Azure services
- Testing with real Key Vault secrets
- **Testing SNC/certificate authentication** (certificates are in Azure Key Vault)

**Example Workflow**:
1. Develop locally with mock SAP (Strategy 1)
2. Test with Azure services + real SAP (Strategy 4) ⭐
3. Deploy to Azure for final validation

---

### Strategy Comparison

| Strategy | SAP Access | Azure Services | Speed | Realism | Certificates |
|----------|-----------|----------------|-------|---------|--------------|
| 1. Mock SAP | ❌ None | ❌ Local only | ⚡ Fast | ⭐ Low | N/A |
| 2. SAP Sandbox | ✅ Direct | ❌ Local only | 🐌 Slow | ⭐⭐⭐ Medium | ❌ Local setup |
| 3. Docker Mock | ❌ None | ❌ Local only | ⚡ Fast | ⭐⭐ Low-Med | N/A |
| **4. Hybrid** | ✅ **Via Azure** | ✅ **Azure dev** | ⚡ **Fast** | ⭐⭐⭐⭐ **High** | ✅ **Azure KV** |

**Recommendation**: Use **Strategy 4 (Hybrid)** for most development work!

**Key Benefit**: Los certificados para SNC están configurados en Azure Key Vault, entonces cuando llamas desde local, usas la misma configuración de certificados que en producción.

---

## Testing Different Scenarios

### Test Case 1: Successful Vendor Creation

**Request**:
```json
{
  "vendor": {
    "name": "ACME Corporation",
    "taxId": "12-3456789",
    "city": "New York"
  },
  "userContext": {
    "role": "Vendor",
    "userId": "vendor-123"
  }
}
```

**Expected Mock Response**:
- Status: `success`
- Vendor Number: `120251209194530`
- Processing time: ~1 second

---

### Test Case 2: Validation Error

**Modify Mock to Return Error**:
```csharp
// In ExecuteBapiAsync
if (string.IsNullOrEmpty(message.Vendor.TaxId))
{
    return new BapiResult
    {
        Success = false,
        Errors = new List<string> { "Tax ID is required" }
    };
}
```

**Request** (missing TaxId):
```json
{
  "vendor": {
    "name": "Test Vendor"
  },
  "userContext": {
    "role": "Vendor",
    "userId": "vendor-123"
  }
}
```

**Expected Response**:
- Status: `failure`
- Errors: `["Tax ID is required"]`

---

### Test Case 3: Approver vs Vendor Authentication

**Approver Request**:
```json
{
  "vendor": { "name": "Vendor Inc", "taxId": "123" },
  "userContext": {
    "role": "Approver",
    "userId": "approver-123",
    "azureAdUserId": "guid-abc-def",
    "email": "approver@company.com"
  }
}
```

**Check Logs**:
- Should see: `"Authentication method selected: IdentityPropagation for role Approver"`

**Vendor Request**:
```json
{
  "vendor": { "name": "Vendor Inc", "taxId": "123" },
  "userContext": {
    "role": "Vendor",
    "userId": "vendor-123",
    "invitationToken": "inv-token-abc"
  }
}
```

**Check Logs**:
- Should see: `"Authentication method selected: SystemAccount for role Vendor"`

---

## Local Testing Checklist

### Phase 1 Testing (Mock SAP)

- [ ] Start Function App locally (`func start`)
- [ ] Send vendor create request
- [ ] Verify 202 Accepted response
- [ ] Check Service Bus queue (Azure Portal or Service Bus Explorer)
- [ ] Verify Worker Function processes message
- [ ] Check mock vendor number generated
- [ ] Verify logs show correct authentication method
- [ ] Test webhook endpoint (`/api/sap/webhook/test`)

### Phase 2 Testing (Event Hubs + SignalR)

- [ ] Configure Event Hubs connection
- [ ] Send vendor create request
- [ ] Verify status event published to Event Hubs
- [ ] Verify SignalR notification sent
- [ ] Check frontend receives real-time update

### Phase 3 Testing (Identity Propagation)

- [ ] Test approver request (with Azure AD user ID)
- [ ] Verify SNC connection attempted
- [ ] Test vendor request (with invitation token)
- [ ] Verify system account used
- [ ] Check vendor mapping stored in Cosmos DB

---

## Debugging Tips

### View Service Bus Messages

**Using Azure Portal**:
1. Go to Service Bus namespace
2. Select queue `sap-vendor-create`
3. Click "Service Bus Explorer"
4. View messages (without removing from queue)

**Using Azure CLI**:
```bash
az servicebus queue show \
  --resource-group rg-platform-dev \
  --namespace-name mdmportal-sb-dev \
  --name sap-vendor-create \
  --query "countDetails"
```

---

### View Function Logs

**Local**:
```bash
# Logs appear in terminal where func start is running
# Filter for SAP-related logs:
func start | grep -i "sap"
```

**Azure**:
```bash
az functionapp logs tail \
  --name func-platform-dev \
  --resource-group rg-platform-dev
```

---

### Test Webhook Endpoint

```bash
# Test connectivity
curl http://localhost:7071/api/sap/webhook/test

# Expected response:
{
  "message": "SAP webhook is reachable",
  "timestamp": "2025-12-09T19:00:00Z",
  "environment": "Development"
}
```

---

## Recommended Development Workflow

### Day-to-Day Development (No SAP)

1. **Use mock BAPI responses**
2. **Test with Postman/curl**
3. **Verify Service Bus flow**
4. **Check logs for correct behavior**

### Integration Testing (Weekly)

1. **Connect to SAP sandbox**
2. **Run end-to-end tests**
3. **Validate actual BAPI responses**
4. **Test error scenarios**

### Pre-Production Testing

1. **Deploy to dev environment**
2. **Test with real SAP dev system**
3. **Verify Event Hubs + SignalR**
4. **Test identity propagation (approvers)**
5. **Load test with 100+ requests**

---

## Mock Data Examples

### Sample Vendor Data

```json
{
  "vendor": {
    "name": "Global Supplies Inc",
    "taxId": "12-3456789",
    "street": "123 Business Ave",
    "city": "New York",
    "postalCode": "10001",
    "country": "US",
    "email": "contact@globalsupplies.com",
    "phone": "+1-555-0100",
    "bankAccount": "123456789",
    "bankName": "Chase Bank",
    "currency": "USD",
    "paymentTerms": "NET30"
  },
  "userContext": {
    "role": "Vendor",
    "userId": "vendor-user-001",
    "email": "vendor@globalsupplies.com",
    "invitationToken": "inv-abc-123-def-456"
  }
}
```

### Sample Error Responses

```json
{
  "correlationId": "abc-123",
  "status": "failure",
  "errors": [
    "Tax ID format invalid",
    "Country code must be 2 characters"
  ],
  "timestamp": "2025-12-09T19:00:00Z"
}
```

---

## Environment Variables for Local Testing

### Minimal Configuration (Mock SAP)

```json
{
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "dotnet-isolated",
    "ServiceBusConnection": "Endpoint=sb://mdmportal-sb-dev.servicebus.windows.net/...",
    "KeyVaultUri": ""
  }
}
```

### Full Configuration (Real SAP Sandbox)

```json
{
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "dotnet-isolated",
    "ServiceBusConnection": "Endpoint=sb://...",
    "KeyVaultUri": "https://vendormdm-kv-dev.vault.azure.net/",
    "SAP-Hostname": "sap-sandbox.company.com",
    "SAP-SystemNumber": "00",
    "SAP-Client": "100",
    "SAP-SystemAccount-Username": "DEVUSER",
    "SAP-SystemAccount-Password": "password"
  }
}
```

---

## Troubleshooting

### Issue: "Service Bus connection failed"

**Solution**: Use Azure Service Bus Explorer or Azurite for local testing

```bash
# Install Azurite (local Azure emulator)
npm install -g azurite

# Start Azurite
azurite-blob --silent --location c:\azurite --debug c:\azurite\debug.log
```

---

### Issue: "Key Vault access denied" (local)

**Solution**: Login to Azure CLI

```bash
az login
az account show  # Verify correct subscription
```

---

### Issue: "Mock responses not realistic enough"

**Solution**: Capture real SAP responses and use them as mock data

1. Test with real SAP sandbox
2. Log actual BAPI responses
3. Update mock to return similar structure
4. Use for local development

---

## Next Steps

1. **Start with Strategy 1** (Mock SAP) for initial development
2. **Test locally** with Postman/curl
3. **Verify Service Bus flow** works end-to-end
4. **Move to Strategy 2** (SAP Sandbox) for integration testing
5. **Deploy to Azure** and test with real SAP dev system

**Remember**: The goal is to develop **independently** without blocking on SAP availability!
