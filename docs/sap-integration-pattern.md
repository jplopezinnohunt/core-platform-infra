# SAP Integration Pattern - Event-Driven Architecture

## Document Purpose

This document defines the **SAP Integration Pattern** for the Vendor MDM Portal platform. It serves as the architectural reference for integrating Azure-based applications with SAP ECC 6.0 using an event-driven, serverless approach.

**Use this document to**:
- Understand the event-driven integration architecture
- Learn the authentication flows (hybrid approach)
- Reference implementation patterns for future SAP integrations
- Guide development teams on SAP connectivity best practices

---

## Architecture Overview

### Design Principles

1. **Event-Driven**: Asynchronous, decoupled communication between portal and SAP
2. **Serverless**: Azure Functions for scalability and cost efficiency
3. **Resilient**: Service Bus queuing ensures zero data loss
4. **Real-Time**: SignalR provides instant user feedback
5. **Secure**: Hybrid authentication (identity propagation for approvers, system connection for vendors)
6. **Auditable**: Full traceability at both application and SAP levels

### High-Level Architecture

```
┌─────────────────┐
│  Vendor Portal  │ (React SPA)
│   (Azure SWA)   │
└────────┬────────┘
         │ HTTP POST
         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Azure Functions                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  Function A  │  │  Function B  │  │  Function C  │     │
│  │  Ingestion   │  │   Worker     │  │   Feedback   │     │
│  │ (HTTP Trig)  │  │ (SB Trigger) │  │ (EH Trigger) │     │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘     │
└─────────┼──────────────────┼──────────────────┼────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
    ┌──────────┐      ┌──────────┐      ┌──────────┐
    │ Service  │      │   SAP    │      │  SignalR │
    │   Bus    │      │ ECC 6.0  │      │ Service  │
    │  Queue   │      │  (BAPI)  │      │          │
    └──────────┘      └────┬─────┘      └────┬─────┘
                           │                  │
                           ▼                  │
                    ┌──────────┐              │
                    │  Event   │──────────────┘
                    │  Hubs    │
                    └──────────┘
```

---

## Event-Driven Flow

### End-to-End Message Flow

#### 1. **Command Phase (Inbound to SAP)**

```
User Action → HTTP Request → Function A (Ingestion)
```

**Function A - Ingestion**:
- **Trigger**: HTTP POST `/api/sap/vendor/create`
- **Input**: Vendor data + user context (role, identity)
- **Process**:
  1. Validate payload schema
  2. Detect user role (Approver vs Vendor)
  3. Enrich with metadata (correlation ID, timestamp)
  4. Publish message to Service Bus queue
- **Output**: `202 Accepted` with correlation ID
- **Response Time**: < 100ms (async)

**Service Bus Queue**:
- **Queue Name**: `sap-vendor-create`
- **Purpose**: Command buffer (decouples web app from SAP)
- **Properties**:
  - Max delivery count: 5 (automatic retry)
  - Lock duration: 5 minutes (SAP BAPI timeout)
  - Duplicate detection: 10 minutes (idempotency)
  - Message TTL: 7 days
- **Benefit**: Zero data loss if SAP is temporarily unavailable

#### 2. **Processing Phase (SAP Execution)**

```
Service Bus → Function B (Worker) → SAP BAPI
```

**Function B - Worker**:
- **Trigger**: Service Bus Queue `sap-vendor-create`
- **Process**:
  1. Deserialize message
  2. **Detect user role**:
     - Role = "Approver" → Identity propagation (SNC)
     - Role = "Vendor" → System connection
  3. Transform payload to SAP BAPI format
  4. Establish RFC connection (role-based authentication)
  5. Execute BAPI (e.g., `BAPI_VENDOR_CREATE`)
  6. Handle SAP response (success/failure)
  7. **For vendors**: Store mapping (portal user ID ↔ SAP vendor number) in Cosmos DB
  8. Publish status event to Event Hubs
- **Error Handling**:
  - Transient errors → Automatic retry (Service Bus)
  - Permanent errors → Dead letter queue + Application Insights log
  - Identity propagation failure → Fallback to system account + warning

#### 3. **Event Phase (Outbound from SAP)**

```
SAP Response → Event Hubs → Function C (Feedback)
```

**Event Hubs**:
- **Event Hub Name**: `sap-status-events`
- **Purpose**: High-throughput event streaming
- **Properties**:
  - Partition count: 4 (parallel processing)
  - Retention: 1 day (ephemeral status events)
  - Consumer group: `signalr-notifications`
- **Event Schema**:
  ```json
  {
    "correlationId": "abc-123",
    "status": "success|failure",
    "vendorNumber": "1000123",
    "sapVendorNumber": "1000123",
    "errors": [],
    "timestamp": "2025-12-09T19:00:00Z"
  }
  ```

#### 4. **Notification Phase (Real-Time Feedback)**

```
Event Hubs → Function C → SignalR → User Browser
```

**Function C - Feedback**:
- **Trigger**: Event Hub `sap-status-events`
- **Process**:
  1. Deserialize SAP status event
  2. Retrieve user connection ID (from correlation ID)
  3. Send SignalR message to user's browser
  4. Update vendor record in Cosmos DB (SAP vendor number)
- **SignalR Message**:
  ```json
  {
    "correlationId": "abc-123",
    "status": "success",
    "vendorNumber": "1000123",
    "message": "Vendor created in SAP successfully"
  }
  ```
- **User Experience**: Real-time toast notification (< 2 seconds)

---

## Authentication Patterns

### Hybrid Authentication Strategy

The integration uses **role-based authentication** to optimize cost and user experience:

#### Pattern 1: Internal Approver Flow

**User Type**: Employees managing vendor master data

**Authentication Flow**:
```
1. User logs in → Azure AD SSO
2. Portal captures Azure AD user ID
3. API request includes: role="Approver" + azureAdUserId
4. Function B detects role="Approver"
5. Retrieves Azure AD token
6. Exchanges token for X.509 certificate
7. Establishes SNC connection to SAP
8. BAPI executes as individual user (e.g., JDOE)
```

**SAP Configuration**:
- **SNC Enabled**: Yes
- **User Mapping**: CERTRULE or EXTID_DN
- **Certificate Mapping**: CN=john.doe@company.com → SAP User JDOE
- **Audit Trail**: SAP logs action as JDOE (individual accountability)

**Benefits**:
- ✅ SOX compliant (individual user tracking)
- ✅ Phishing-resistant MFA
- ✅ Regulatory compliance

**Cost**: $60/month (10 Azure AD Premium P1 licenses)

---

#### Pattern 2: External Vendor Flow

**User Type**: External vendors submitting their own data

**Authentication Flow**:
```
1. Vendor receives invitation link
2. Registers in portal (no Azure AD)
3. Portal assigns portal user ID
4. API request includes: role="Vendor" + invitationToken
5. Function B detects role="Vendor"
6. Retrieves system account credentials from Key Vault
7. Establishes basic auth connection to SAP
8. BAPI executes as system account
9. Stores mapping: portal user ID ↔ SAP vendor number (Cosmos DB)
```

**SAP Configuration**:
- **SNC Enabled**: No (for this connection)
- **User**: System account (e.g., SAPVENDORPORTAL)
- **Audit Trail**: SAP logs action as SAPVENDORPORTAL

**Application Audit**:
- **Cosmos DB Collection**: `VendorMappings`
- **Schema**: `{ portalUserId, sapVendorNumber, createdDate, lastUpdated }`
- **Purpose**: Track which vendor user corresponds to which SAP vendor
- **Traceability**: Portal logs all vendor actions with portal user ID

**Benefits**:
- ✅ Simple vendor experience (no complex authentication)
- ✅ Scalable (unlimited vendors, no licensing cost)
- ✅ Application-level audit trail
- ✅ Vendor self-service (vendors can update their own data)

**Cost**: $0 (no Azure AD Premium needed)

---

### Authentication Decision Logic

**Function B (Worker) - Pseudo-Code**:

```csharp
public async Task ProcessVendorMessage(VendorMessage message)
{
    RfcConnection sapConnection;
    
    // Role-based authentication
    if (message.UserContext?.Role == "Approver" && 
        message.UserContext?.AzureAdUserId != null)
    {
        // Internal approver - use identity propagation
        var certificate = await GetUserCertificateAsync(
            message.UserContext.AzureAdUserId
        );
        sapConnection = CreateSncConnection(certificate);
        
        // SAP audit: Logged as individual user (e.g., JDOE)
    }
    else if (message.UserContext?.Role == "Vendor")
    {
        // External vendor - use system connection
        var credentials = await keyVaultClient.GetSecretAsync(
            "SAP-SystemAccount-Username",
            "SAP-SystemAccount-Password"
        );
        sapConnection = CreateBasicAuthConnection(credentials);
        
        // SAP audit: Logged as system account
        // Portal audit: Tracked in Cosmos DB
    }
    
    // Execute BAPI
    var result = await ExecuteBapiAsync(sapConnection, message.VendorData);
    
    // For vendors: Store mapping
    if (message.UserContext?.Role == "Vendor" && result.Success)
    {
        await StoreVendorMappingAsync(
            message.UserContext.UserId,
            result.SapVendorNumber
        );
    }
    
    // Publish status event
    await PublishStatusEventAsync(result);
}
```

---

## Infrastructure Components

### Azure Resources

#### 1. Service Bus Namespace
- **Name**: `mdmportal-sb-{env}`
- **SKU**: Standard
- **Queues**:
  - `sap-vendor-create` (vendor creation commands)
  - `sap-vendor-update` (vendor update commands)
  - `sap-vendor-delete` (vendor deletion commands)

#### 2. Event Hubs Namespace
- **Name**: `evh-sap-events-{env}`
- **SKU**: Standard
- **Event Hubs**:
  - `sap-status-events` (SAP response events)
- **Consumer Groups**:
  - `signalr-notifications` (for Function C)

#### 3. SignalR Service
- **Name**: `signalr-mdm-{env}`
- **SKU**: Standard
- **Mode**: Serverless
- **Hubs**: `SapNotificationHub`

#### 4. Function App
- **Name**: `func-platform-{env}`
- **Runtime**: .NET 8
- **Plan**: Consumption (serverless)
- **Functions**:
  - `SapVendorIngestionFunction` (HTTP trigger)
  - `SapVendorWorkerFunction` (Service Bus trigger)
  - `SapStatusFeedbackFunction` (Event Hub trigger)

#### 5. Key Vault
- **Name**: `kv-platform-{env}`
- **Secrets**:
  - `SAP-Hostname`
  - `SAP-SystemNumber`
  - `SAP-Client`
  - `SAP-SystemAccount-Username`
  - `SAP-SystemAccount-Password`
  - `SAP-SNC-PSE` (for approver identity propagation)

#### 6. Cosmos DB
- **Account**: `cosmos-platform-{env}`
- **Database**: `VendorPortal`
- **Containers**:
  - `VendorMappings` (partition key: `/portalUserId`)
    - Schema: `{ portalUserId, sapVendorNumber, createdDate, lastUpdated }`

#### 7. VNet (Optional - for private SAP connectivity)
- **Name**: `vnet-platform-{env}`
- **Subnets**:
  - `snet-functions` (Function App VNet integration)
  - `snet-gateway` (VPN Gateway to SAP)

---

## SAP Components

### ABAP Programs

#### 1. Z_TEST_AZURE_PUSH (Test Program)

**Purpose**: Validate SAP → Azure connectivity

**Transaction**: SE38

**Functionality**:
- Creates HTTP client using `CL_HTTP_CLIENT`
- POSTs test JSON payload to Azure Function webhook
- Displays response status and body
- Logs errors for troubleshooting

**Usage**: Run before implementing full integration to verify:
- SSL certificate imported correctly (STRUST)
- Network connectivity to Azure
- Firewall rules allow outbound HTTPS

**Code**: See [`abap-test-program.abap`](file:///Users/jplopez/.gemini/antigravity/brain/dd8862d3-81e9-4e67-9b3c-2988c3412dc6/abap-test-program.abap)

---

#### 2. Z_BAPI_VENDOR_AZURE_WRAPPER (Optional - for SAP-initiated events)

**Purpose**: Wrapper around BAPI_VENDOR_CREATE to send status to Azure

**Flow**:
1. Execute standard BAPI_VENDOR_CREATE
2. Check return status (SUCCESS/ERROR)
3. POST status to Azure Event Hubs or webhook
4. Return vendor number or errors to caller

**Note**: This is optional. In the designed architecture, Function B calls the BAPI directly and publishes events from Azure side.

---

### SAP Configuration

#### For All Users (Basic Connectivity)

**1. SSL Certificate (STRUST)**:
- **Transaction**: `STRUST`
- **Identity**: SSL Client (Standard)
- **Certificate**: DigiCert Global Root G2
- **Download**: https://www.digicert.com/kb/digicert-root-certificates.htm
- **Steps**:
  1. Import certificate
  2. Save and activate
  3. Restart ICM (SMICM → Administration → ICM → Restart)

**2. System Account**:
- **User**: `SAPVENDORPORTAL` (or similar)
- **Type**: System/Service account
- **Permissions**: Execute BAPI_VENDOR_CREATE, BAPI_VENDOR_CHANGE, etc.
- **Password**: Stored in Azure Key Vault

---

#### For Internal Approvers Only (SNC + Identity Propagation)

**1. Enable SNC (Profile Parameters)**:
```abap
snc/enable = 1
snc/gssapi_lib = /usr/sap/SYS/exe/run/sapcrypto.so
snc/identity/as = p:CN=SAP_ECC_PRD, O=COMPANY, C=US
snc/accept_insecure_cpic = 0
snc/accept_insecure_gui = 0
snc/accept_insecure_rfc = 0
```

**2. Import Certificates (STRUST)**:
- **Transaction**: `STRUST`
- **Identity**: SNC SAPCryptolib
- **Certificates**:
  - Azure root CA (DigiCert Global Root G2)
  - Azure Function client certificates (for 10 approvers)

**3. Configure User Mapping (CERTRULE or EXTID_DN)**:

**Option A: CERTRULE (Rule-Based)**:
```abap
Transaction: CERTRULE
Rule: Map CN=<email> to SAP User ID
Example: CN=john.doe@company.com → JDOE
```

**Option B: EXTID_DN (Explicit Mapping)**:
```abap
Transaction: SU01
For each approver:
  User: JDOE
  External ID: CN=john.doe@company.com, O=COMPANY, C=US
```

**4. Create RFC Destination (SM59)**:
```abap
Transaction: SM59
Connection Type: T (TCP/IP)
Activation Type: Registered Server Program
SNC: Enabled
SNC Name: p:CN=AZURE_FUNCTION, O=COMPANY, C=US
Quality of Protection: Privacy (encryption + integrity)
```

---

## Implementation Steps

### Phase 1: Basic Authentication (Weeks 1-3)

**Goal**: Prove end-to-end connectivity with minimal SAP configuration

#### Infrastructure Deployment

```bash
# 1. Deploy Azure infrastructure
cd core-platform-infra
az deployment group create \
  --resource-group rg-platform-dev \
  --template-file bicep/main.bicep \
  --parameters bicep/environments/dev.bicepparam

# 2. Store SAP credentials in Key Vault
az keyvault secret set \
  --vault-name kv-platform-dev \
  --name SAP-Hostname \
  --value "sap-dev.company.com"

az keyvault secret set \
  --vault-name kv-platform-dev \
  --name SAP-SystemAccount-Username \
  --value "SAPVENDORPORTAL"

az keyvault secret set \
  --vault-name kv-platform-dev \
  --name SAP-SystemAccount-Password \
  --value "<secure-password>"
```

#### SAP Configuration

1. **Import SSL Certificate** (STRUST)
2. **Create System Account** (SU01)
3. **Test Connectivity** (Z_TEST_AZURE_PUSH)

#### Function Deployment

```bash
# Deploy Azure Functions
cd core-artifact-processors/src/VendorMdm.Artifacts
dotnet publish -c Release -o ./publish
func azure functionapp publish func-platform-dev
```

#### Testing

1. Submit test vendor via portal UI
2. Verify message in Service Bus queue
3. Verify BAPI execution in SAP (SM37)
4. Verify vendor created with correct data
5. Check Application Insights for telemetry

**Success Criteria**:
- ✅ Vendor created in SAP
- ✅ No errors in Application Insights
- ✅ System account used for all users

---

### Phase 2: Event Hubs & SignalR (Weeks 4-6)

**Goal**: Add real-time feedback to UI

#### Infrastructure Updates

- Deploy Event Hubs namespace
- Deploy SignalR Service
- Update Function C to use Event Hub trigger

#### Frontend Integration

```bash
# Install SignalR client
cd vendor-portal-swa
npm install @microsoft/signalr
```

**React Component**:
```typescript
import * as signalR from '@microsoft/signalr';

const connection = new signalR.HubConnectionBuilder()
  .withUrl('/api/signalr')
  .build();

connection.on('SapStatusUpdate', (event) => {
  // Show toast notification
  toast.success(`Vendor ${event.vendorNumber} created!`);
});

await connection.start();
```

#### Testing

1. Submit vendor form
2. Verify real-time notification appears (< 2 seconds)
3. Load test with 100 concurrent submissions
4. Verify all notifications delivered

**Success Criteria**:
- ✅ SignalR notifications delivered in < 2 seconds
- ✅ No message loss under load
- ✅ Event Hubs processing all events

---

### Phase 3: Identity Propagation for Approvers (Months 3-4)

**Goal**: Individual accountability for internal approvers

#### Azure AD Configuration

1. **Enable Certificate-Based Authentication**:
   - Azure Portal → Azure AD → Security → Authentication methods
   - Enable certificate-based authentication

2. **Create App Registration**:
   - Name: `SAP-Integration-Service`
   - Permissions: User.Read, User.ReadBasic.All
   - Certificate: Upload client certificate

#### SAP Configuration

1. **Enable SNC** (profile parameters)
2. **Import Certificates** (STRUST)
3. **Configure User Mappings** (CERTRULE or EXTID_DN for 10 approvers)
4. **Create RFC Destination** (SM59 with SNC enabled)

#### Function Updates

Update `SapVendorWorkerFunction`:
- Add role detection logic
- Implement certificate retrieval for approvers
- Implement SNC connection for approvers
- Keep system connection for vendors

#### Cosmos DB Setup

Create `VendorMappings` container:
```json
{
  "id": "unique-id",
  "portalUserId": "vendor-user-123",
  "sapVendorNumber": "1000123",
  "createdDate": "2025-12-09T19:00:00Z",
  "lastUpdated": "2025-12-09T19:00:00Z"
}
```

#### Testing

1. **Approver Test**:
   - Internal user logs in with Azure AD
   - Creates vendor
   - Verify SAP audit log shows individual user (JDOE)
   
2. **Vendor Test**:
   - External vendor uses invitation link
   - Submits vendor data
   - Verify SAP audit log shows system account
   - Verify mapping stored in Cosmos DB

**Success Criteria**:
- ✅ Approver actions logged as individual users in SAP
- ✅ Vendor actions logged as system account in SAP
- ✅ Vendor mappings stored correctly in Cosmos DB
- ✅ No identity propagation failures

---

## Monitoring & Observability

### Application Insights

**Key Metrics**:
- Request duration (Function A)
- Queue depth (Service Bus)
- BAPI execution time (Function B)
- Event Hub throughput
- SignalR delivery time

**Custom Events**:
```csharp
telemetryClient.TrackEvent("VendorCreated", new Dictionary<string, string>
{
    { "VendorNumber", vendorNumber },
    { "UserRole", userRole },
    { "AuthMethod", authMethod },
    { "Duration", duration.ToString() }
});
```

**Alerts**:
- Dead letter queue depth > 10
- Function B failure rate > 5%
- Average BAPI execution time > 10 seconds
- SignalR delivery time > 5 seconds

---

### SAP Monitoring

**Transactions**:
- **SM37**: Background jobs (BAPI execution)
- **SM21**: System log (errors)
- **SM50**: Process overview (active connections)
- **ST22**: ABAP dumps (runtime errors)

**Audit Logs**:
- **SM20**: Security audit log (user actions)
- **STAD**: Statistics (RFC calls)

---

## Error Handling & Resilience

### Retry Strategy

**Service Bus (Automatic)**:
- Max delivery count: 5
- Exponential backoff: 1s, 2s, 4s, 8s, 16s
- Dead letter after 5 failures

**Function B (Custom)**:
```csharp
var retryPolicy = Policy
    .Handle<SapException>()
    .WaitAndRetryAsync(3, 
        retryAttempt => TimeSpan.FromSeconds(Math.Pow(2, retryAttempt)),
        onRetry: (exception, timeSpan, retryCount, context) =>
        {
            logger.LogWarning($"Retry {retryCount} after {timeSpan}");
        });

await retryPolicy.ExecuteAsync(async () => 
{
    await ExecuteBapiAsync(connection, vendorData);
});
```

### Dead Letter Queue Handling

**Monitor**:
```bash
# Check dead letter queue depth
az servicebus queue show \
  --resource-group rg-platform-dev \
  --namespace-name mdmportal-sb-dev \
  --name sap-vendor-create \
  --query "countDetails.deadLetterMessageCount"
```

**Process**:
1. Alert triggers when DLQ depth > 10
2. Operations team investigates root cause
3. Fix issue (e.g., SAP connectivity, data validation)
4. Resubmit messages from DLQ

---

## Security Considerations

### Data Protection

**In Transit**:
- ✅ HTTPS for all HTTP communication
- ✅ SNC encryption for approver → SAP (Phase 3)
- ✅ TLS 1.2+ for Service Bus, Event Hubs

**At Rest**:
- ✅ Key Vault for credentials (encrypted)
- ✅ Cosmos DB encryption enabled
- ✅ Service Bus messages encrypted

### Authentication & Authorization

**Portal → Azure Functions**:
- Azure AD authentication
- Function-level authorization (check user role)

**Azure Functions → SAP**:
- **Approvers**: X.509 certificate (SNC)
- **Vendors**: System account (basic auth)

**Azure Functions → Azure Resources**:
- Managed Identity (no credentials in code)

### Secrets Management

**Never Store in Code**:
- ❌ Connection strings
- ❌ Passwords
- ❌ API keys

**Always Use Key Vault**:
- ✅ SAP credentials
- ✅ Certificates
- ✅ Connection strings

---

## Performance Optimization

### Throughput Targets

| Component | Target | Current |
|-----------|--------|---------|
| Function A (Ingestion) | < 100ms | TBD |
| Service Bus (Queue) | 1000 msg/sec | TBD |
| Function B (Worker) | < 5 seconds | TBD |
| SAP BAPI | < 3 seconds | TBD |
| Event Hubs | 10,000 events/sec | TBD |
| SignalR (Delivery) | < 2 seconds | TBD |

### Scaling Strategy

**Function App**:
- Consumption plan (auto-scale)
- Max instances: 200
- Scale trigger: Queue depth > 100

**Event Hubs**:
- Partition count: 4
- Auto-inflate: Enabled
- Max throughput units: 10

**Service Bus**:
- Standard tier (no auto-scale)
- Monitor queue depth
- Upgrade to Premium if needed

---

## Cost Analysis

### Monthly Costs (Dev Environment)

| Component | Cost |
|-----------|------|
| Function App (Consumption) | ~$20 |
| Service Bus (Standard) | ~$10 |
| Event Hubs (Standard, 1 TU) | ~$25 |
| SignalR (Standard, 1 unit) | ~$50 |
| Cosmos DB (400 RU/s) | ~$25 |
| Key Vault | ~$5 |
| Azure AD Premium P1 (10 users) | $60 |
| **Total** | **~$195/month** |

### Annual Cost

- **Dev**: $2,340/year
- **Prod**: ~$3,500/year (higher throughput)
- **Total**: ~$5,840/year

**ROI**: Compared to implementing full SNC for all users ($37,220/year), the hybrid approach saves **$31,380/year (85% reduction)**.

---

## Troubleshooting Guide

### Common Issues

#### 1. SSL Handshake Error (SAP → Azure)

**Symptom**: Z_TEST_AZURE_PUSH returns SSL error

**Cause**: Certificate not imported in STRUST

**Solution**:
1. Download DigiCert Global Root G2
2. Import in STRUST (SSL Client Standard)
3. Save and activate
4. Restart ICM (SMICM)

---

#### 2. Message Stuck in Queue

**Symptom**: Service Bus queue depth increasing

**Cause**: Function B not triggering

**Solution**:
1. Check Function App status (Azure Portal)
2. Verify Service Bus connection string
3. Check Application Insights for errors
4. Restart Function App if needed

---

#### 3. BAPI Execution Failure

**Symptom**: Vendor not created in SAP

**Cause**: Invalid data or missing permissions

**Solution**:
1. Check SAP SM37 for background job errors
2. Review BAPI return messages
3. Verify system account has BAPI permissions
4. Check data transformation logic

---

#### 4. SignalR Not Delivering

**Symptom**: No real-time notification in UI

**Cause**: SignalR connection not established

**Solution**:
1. Check browser console for errors
2. Verify SignalR connection string
3. Check CORS configuration
4. Test SignalR connection manually

---

## Future Enhancements

### Potential Improvements

1. **Batch Processing**: Support bulk vendor creation
2. **Change Data Capture**: Real-time sync from SAP to portal
3. **Approval Workflow**: Multi-level approval before SAP creation
4. **Data Validation**: Pre-validate against SAP business rules
5. **Conflict Resolution**: Handle concurrent updates gracefully

---

## References

### Documentation

- [Implementation Plan](file:///Users/jplopez/.gemini/antigravity/brain/dd8862d3-81e9-4e67-9b3c-2988c3412dc6/implementation_plan.md)
- [SNC Security Evaluation](file:///Users/jplopez/.gemini/antigravity/brain/dd8862d3-81e9-4e67-9b3c-2988c3412dc6/snc-security-evaluation.md)
- [ABAP Test Program](file:///Users/jplopez/.gemini/antigravity/brain/dd8862d3-81e9-4e67-9b3c-2988c3412dc6/abap-test-program.abap)

### External Resources

- [Azure Service Bus Documentation](https://docs.microsoft.com/azure/service-bus-messaging/)
- [Azure Event Hubs Documentation](https://docs.microsoft.com/azure/event-hubs/)
- [Azure SignalR Service Documentation](https://docs.microsoft.com/azure/azure-signalr/)
- [SAP .NET Connector Documentation](https://support.sap.com/nco)
- [SAP SNC Configuration Guide](https://help.sap.com/snc)

---

## Document Version

- **Version**: 1.0
- **Date**: 2025-12-09
- **Author**: Platform Architecture Team
- **Status**: Approved for Implementation
