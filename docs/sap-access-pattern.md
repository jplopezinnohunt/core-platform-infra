# SAP Access Pattern: Azure as Cloud Connector

## Overview

This document describes how Azure services in the **core platform** act as a **proxy/cloud connector** to enable SAP access from various environments, including local development machines without VPN access.

## Problem Statement

### Development Environment Constraints

- **Corporate Network**: SAP systems reside in the corporate network, accessible only via VPN
- **Work Laptop**: Has VPN client installed → Can access SAP directly
- **Personal/Home Machine**: Cannot install VPN client → Cannot access SAP directly
- **CI/CD Pipelines**: No VPN access → Cannot test SAP integration

### Traditional Solution: SAP Cloud Connector

SAP Cloud Connector is typically used for **reverse proxy** scenarios:
```
SAP BTP (Cloud) → Cloud Connector (on-premise) → SAP System (on-premise)
```

This enables SAP cloud services to access on-premise systems, but doesn't solve the local development problem.

## Our Solution: Azure as Forward Proxy

Azure services with corporate network connectivity act as a **forward proxy**, enabling external clients to access SAP through Azure:

```
Developer Machine (no VPN) → Azure Services (with VPN/ExpressRoute) → SAP System
```

This pattern provides:
- ✅ Local development without VPN
- ✅ Consistent API surface across environments
- ✅ Centralized security and monitoring
- ✅ Reusable infrastructure for multiple applications

---

## Architecture

### High-Level Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Development Scenarios                     │
└─────────────────────────────────────────────────────────────┘

┌──────────────────┐         ┌──────────────────┐
│  Local Machine   │         │  Work Laptop     │
│  (no VPN)        │         │  (with VPN)      │
└────────┬─────────┘         └────────┬─────────┘
         │ HTTPS                      │ RFC/SNC (direct)
         │                            │
         ↓                            ↓
┌─────────────────────────────────────────────────────────────┐
│                      Azure Platform                          │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Core APIs (App Service)                               │ │
│  │  - Vendor MDM API                                      │ │
│  │  - SAP Integration Endpoints                           │ │
│  │  - Managed Identity Authentication                     │ │
│  └──────────────────────────┬─────────────────────────────┘ │
│                             │                                │
│  ┌──────────────────────────┴─────────────────────────────┐ │
│  │  Core Artifact Processors (Azure Functions)            │ │
│  │  - SAP Vendor Ingestion Function                       │ │
│  │  - SAP Vendor Worker Function                          │ │
│  │  - SAP HTTP Webhook Function                           │ │
│  └──────────────────────────┬─────────────────────────────┘ │
│                             │                                │
│  ┌──────────────────────────┴─────────────────────────────┐ │
│  │  Azure VNet Integration                                │ │
│  │  - Private Endpoints                                   │ │
│  │  - VPN Gateway / ExpressRoute                          │ │
│  └──────────────────────────┬─────────────────────────────┘ │
└─────────────────────────────┼─────────────────────────────┘
                              │ RFC/SNC over private network
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                    Corporate Network                         │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  SAP System                                            │ │
│  │  - Hostname: sap.corporate.local                       │ │
│  │  - System Number: 00                                   │ │
│  │  - Client: 800                                         │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Network Connectivity Options

Azure can connect to corporate SAP systems via:

1. **Site-to-Site VPN**: Encrypted tunnel between Azure VNet and corporate network
2. **Azure ExpressRoute**: Dedicated private connection (higher bandwidth, lower latency)
3. **VNet Peering**: If SAP is already in another Azure VNet
4. **Private Endpoint**: For Azure-hosted SAP systems

> [!IMPORTANT]
> Network connectivity between Azure and SAP must be established by the infrastructure/networking team before SAP integration can work.

---

## Access Patterns by Environment

### 1. Local Development (Frontend)

**Scenario**: Developer working on `vendor-portal-swa` React application

```
Local React App → Azure API (Dev) → SAP
```

**Configuration**:
```bash
# .env.local
VITE_API_URL=https://vendormdm-api-dev.azurewebsites.net
```

**Workflow**:
1. Run frontend locally: `npm run dev`
2. Frontend calls Azure-hosted API
3. Azure API connects to SAP using credentials from Key Vault
4. Developer sees real SAP data in local UI

**Advantages**:
- No VPN required
- Real SAP integration testing
- Fast development cycle

---

### 2. Local Development (Backend with Mocks)

**Scenario**: Developer working on `core-apis` with mock SAP data

```
Local API → SapMockService (in-memory)
```

**Configuration**:
```json
// appsettings.Development.json
{
  "SapConnection": {
    "UseMock": true
  }
}
```

**Workflow**:
1. Run API locally: `dotnet run`
2. API uses `SapMockService` instead of real SAP connection
3. Mock returns predefined vendor data
4. No network connectivity required

**Advantages**:
- Works offline
- Fast and predictable
- No VPN or Azure required
- Ideal for unit testing

---

### 3. Local Development (Backend with Real SAP)

**Scenario**: Developer needs to test against real SAP from local API

#### Option A: Via Work Laptop with VPN

```
Local API (on work laptop) → VPN → SAP
```

**Configuration**:
```json
// appsettings.Development.json (using user-secrets)
{
  "SapConnection": {
    "UseMock": false,
    "AppServerHost": "sap.corporate.local",
    "SystemNumber": "00",
    "Client": "800",
    "User": "DEV_USER",
    "Password": "***"  // From dotnet user-secrets
  }
}
```

**Workflow**:
1. Connect to corporate VPN
2. Run API locally: `dotnet run`
3. API connects directly to SAP
4. Test integration locally

#### Option B: Via Azure as Proxy

```
Local API → Azure Function (Proxy) → SAP
```

**Configuration**:
```json
// appsettings.Development.json
{
  "SapConnection": {
    "Mode": "AzureProxy",
    "ProxyUrl": "https://vendormdm-sap-proxy-dev.azurewebsites.net/api/sap"
  }
}
```

**Implementation** (optional Azure Function):
```csharp
[Function("SapProxy")]
public async Task<HttpResponseData> RunProxy(
    [HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequestData req)
{
    // Receives SAP operation request from local machine
    var operation = await req.ReadFromJsonAsync<SapOperation>();
    
    // Executes operation against SAP (Azure has network access)
    var result = await _sapService.ExecuteAsync(operation);
    
    // Returns result to local machine
    return await req.CreateJsonResponseAsync(result);
}
```

---

### 4. Azure Functions Development

**Scenario**: Developer testing SAP Azure Functions

```
Local Machine (HTTP client) → Azure Function (deployed) → SAP
```

**Workflow**:
1. Deploy function to Azure: `func azure functionapp publish vendormdm-functions-dev`
2. Call function via HTTP:
   ```bash
   curl -X POST https://vendormdm-functions-dev.azurewebsites.net/api/SapVendorIngestion \
     -H "Content-Type: application/json" \
     -H "x-functions-key: YOUR_FUNCTION_KEY" \
     -d '{"vendorId": "V123456"}'
   ```
3. Monitor execution in Application Insights
4. Review logs and results

**Advantages**:
- Tests real Azure environment
- Validates Managed Identity authentication
- Tests network connectivity
- No local SAP configuration needed

---

### 5. Production

**Scenario**: Production application running in Azure

```
User Browser → Azure Static Web App → Azure API → SAP
                                         ↓
                                    Azure Functions → SAP
```

**Flow**:
1. User interacts with React app (Azure Static Web App)
2. App calls API endpoints (Azure App Service)
3. API performs synchronous SAP operations
4. API publishes events to Service Bus for async operations
5. Azure Functions process events and call SAP
6. Results stored in database and returned to user

**Security**:
- All SAP credentials in Azure Key Vault
- Managed Identity for authentication
- Private network connectivity to SAP
- No credentials in code or configuration files

---

## Development Workflow Recommendations

### Daily Development (90% of time)

```
Frontend (local) → API (local) → SapMockService
```

- Fast iteration
- No dependencies
- Predictable data
- Works offline

### Integration Testing (when needed)

```
Frontend (local) → API (Azure Dev) → SAP
```

- Real SAP data
- Test actual integration
- Validate business logic
- No VPN required on local machine

### Pre-Release Testing

```
Frontend (Azure Dev) → API (Azure Dev) → SAP
```

- Full Azure environment
- End-to-end testing
- Performance validation
- Security validation

### Production

```
Frontend (Azure Prod) → API (Azure Prod) → SAP
```

- Production SAP system
- Real users
- Full monitoring
- High availability

---

## Security Considerations

### Credential Management

| Environment | Storage | Access Method |
|-------------|---------|---------------|
| **Local (Mock)** | Not needed | N/A |
| **Local (VPN)** | `dotnet user-secrets` | Direct file access |
| **Azure Dev** | Azure Key Vault | Managed Identity |
| **Azure Prod** | Azure Key Vault | Managed Identity |

### Network Security

- **Azure → SAP**: Private network (VPN/ExpressRoute), no public internet
- **Local → Azure**: HTTPS with Azure AD authentication
- **Firewall Rules**: Azure App Service IPs whitelisted in SAP firewall

### Authentication Flow

```
1. Azure Service starts
2. Managed Identity authenticates to Azure AD
3. Azure AD grants access to Key Vault
4. Service retrieves SAP credentials from Key Vault
5. Service connects to SAP using credentials
6. SAP validates user credentials
7. Connection established
```

---

## Monitoring and Debugging

### Application Insights Queries

**SAP Connection Failures**:
```kusto
traces
| where message contains "SAP" and severityLevel >= 3
| project timestamp, message, customDimensions
| order by timestamp desc
```

**SAP Operation Performance**:
```kusto
dependencies
| where type == "SAP"
| summarize avg(duration), count() by name
| order by avg_duration desc
```

### Common Issues

| Issue | Symptom | Solution |
|-------|---------|----------|
| **Network connectivity** | Timeout errors | Verify VNet integration, check firewall rules |
| **Invalid credentials** | Authentication errors | Verify Key Vault secrets, check SAP user permissions |
| **Missing Managed Identity** | Access denied to Key Vault | Enable system-assigned identity on App Service |
| **SNC certificate expired** | SNC handshake failure | Update certificate in Key Vault |

---

## Infrastructure Requirements

### Azure Resources (from `core-platform-infra`)

1. **Key Vault**: Stores SAP credentials and SNC certificates
2. **VNet**: Provides private network for SAP connectivity
3. **VPN Gateway / ExpressRoute**: Connects Azure to corporate network
4. **App Service**: Hosts core-apis with VNet integration
5. **Function App**: Hosts artifact processors with VNet integration
6. **Application Insights**: Monitors SAP operations

### SAP System Requirements

1. **Network Access**: SAP system must be reachable from Azure VNet
2. **User Account**: Dedicated service account for Azure integration
3. **Permissions**: RFC access, BAPI execution permissions
4. **Firewall Rules**: Azure IP ranges whitelisted
5. **SNC Configuration** (if using SNC): Certificate exchange completed

---

## Comparison: Cloud Connector vs Azure Proxy

| Aspect | SAP Cloud Connector | Azure as Proxy |
|--------|---------------------|----------------|
| **Direction** | Reverse (Cloud → On-Prem) | Forward (Client → SAP) |
| **Use Case** | SAP BTP accessing on-prem | Local dev accessing SAP |
| **Installation** | On-premise server required | Uses existing Azure infra |
| **Maintenance** | Additional component to manage | Part of platform |
| **Security** | Separate security layer | Integrated with Azure AD |
| **Monitoring** | Separate monitoring | Application Insights |
| **Cost** | Infrastructure + maintenance | Included in Azure services |

**Key Difference**: Cloud Connector enables SAP cloud services to call on-premise systems. Our Azure proxy enables external developers to call SAP through Azure.

---

## Next Steps

### For Infrastructure Team

1. ✅ Establish network connectivity (VPN/ExpressRoute) between Azure and corporate network
2. ✅ Configure VNet integration for App Service and Function Apps
3. ✅ Whitelist Azure IP ranges in SAP firewall
4. ✅ Provision Key Vault and configure access policies

### For Development Team

1. ✅ Deploy `core-platform-infra` with SAP configuration
2. ✅ Deploy `core-apis` with SAP integration
3. ✅ Test SAP connectivity from Azure
4. ✅ Configure local development environments to use Azure APIs
5. ✅ Document any environment-specific configuration

### For SAP Basis Team

1. ✅ Create service account for Azure integration
2. ✅ Grant necessary RFC and BAPI permissions
3. ✅ Configure SNC if required
4. ✅ Provide connection parameters (host, system number, client)
5. ✅ Coordinate testing and validation

---

## Related Documentation

- [SAP Integration Pattern](./sap-integration-pattern.md) - Overall SAP integration architecture
- [SAP Local Development](./sap-local-development.md) - Local development setup and testing
- [SAP Secrets Management](./sap-secrets-management.md) - Credential storage and rotation
- [Adding New Application](./adding-new-application.md) - How new apps leverage SAP access

---

## Conclusion

By using Azure services as a forward proxy/cloud connector, we enable:

- **Flexible Development**: Work from any machine, with or without VPN
- **Consistent Experience**: Same API surface across all environments
- **Centralized Security**: Credentials managed in Key Vault, Managed Identity authentication
- **Scalability**: Azure handles load and availability
- **Monitoring**: Full observability through Application Insights

This pattern transforms Azure from just a hosting platform into an **integration hub** that bridges the gap between modern cloud development and legacy on-premise SAP systems.
