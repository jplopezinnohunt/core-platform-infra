# Core Platform Infrastructure

This repository contains the shared cloud infrastructure for the **Platform**. It uses Azure Bicep to provision and manage resources that are used across multiple applications:

- **Data**: Azure Cosmos DB, Azure SQL Database
- **Messaging**: Azure Service Bus
- **Compute**: Azure Functions (Infrastructure only), Azure Static Web Apps (Infrastructure only)
- **Security**: Key Vault, Managed Identities
- **Monitoring**: Application Insights

## Platform Architecture

This is a **Core Platform** repository - it provides reusable infrastructure for multiple applications built on the platform.

## Repository Structure

```
.
├── .github/workflows/    # CI/CD pipelines
├── bicep/               # Infrastructure as Code
│   ├── main.bicep       # Main orchestration
│   ├── modules/         # Reusable modules
│   └── environments/    # Environment-specific parameters
└── scripts/             # Utility scripts
```

## Deployment

Deployments are managed via GitHub Actions.

### Manual Deployment
```bash
az deployment group create \
  --resource-group <rg-name> \
  --template-file bicep/main.bicep \
  --parameters bicep/environments/dev.bicepparam \
  --parameters sqlAdminPassword='<secure-password>'
```

**Note**: SQL admin password must be passed as a secure parameter.

## Platform Documentation

- **[Adding a New Application](docs/adding-new-application.md)** - Complete guide for building new apps on this platform
- **[SAP Integration Pattern](docs/sap-integration-pattern.md)** - Event-driven architecture for SAP ECC integration
- **[SAP Implementation Plan](docs/sap-implementation-plan.md)** - Detailed implementation plan with phases and costs
- **[SAP Secrets Management](docs/sap-secrets-management.md)** - Guide for managing SAP credentials (Azure + Local)
- **[SAP Local Development](docs/sap-local-development.md)** - How to develop and test SAP integration locally
- **[SNC Security Evaluation](docs/snc-security-evaluation.md)** - Security options and hybrid authentication approach
- **[ABAP Test Program](docs/abap-test-program.abap)** - SAP connectivity test program (Z_TEST_AZURE_PUSH)

## Platform Architecture

This infrastructure supports multiple applications through a shared platform approach:

- **Core Platform**: Shared infrastructure and services (this repository)
- **Applications**: Domain-specific apps that leverage the platform (e.g., `vendor-portal-swa`)

All applications share the same Key Vault, databases, messaging, and platform services.

