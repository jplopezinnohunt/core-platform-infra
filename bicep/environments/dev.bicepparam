using '../main.bicep'

param environmentName = 'dev'
param location = 'eastus'

// ============================================
// ACTUALIZAR ANTES DE DEPLOYMENT
// ============================================

// SQL Server Admin Password
// Nota: Se usa Azure AD Authentication después, pero SQL Server requiere un admin password inicial
param sqlAdminPassword = 'PLACEHOLDER-UPDATE-BEFORE-DEPLOY'

// SAP Connection Parameters - ACTUALIZAR CON VALORES REALES
param sapHostname = 'sap-dev.company.com'              // ← Tu SAP hostname
param sapSystemNumber = '00'                            // ← Tu system number  
param sapClient = '350'                                 // ← Tu client
param sapSystemAccountUsername = 'JP_LOPEZ'      // ← Usuario SAP
param sapSystemAccountPassword = 'PLACEHOLDER-UPDATE-BEFORE-DEPLOY'  // ← Password SAP
