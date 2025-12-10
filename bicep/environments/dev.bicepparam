using '../main.bicep'

param environmentName = 'dev'


// ============================================
// ACTUALIZAR ANTES DE DEPLOYMENT
// ============================================

// SQL parameters removed - SQL Server already exists, not deploying via Bicep


// SAP Connection Parameters - ACTUALIZAR CON VALORES REALES
param sapHostname = 'sap-dev.company.com'              // ← Tu SAP hostname
param sapSystemNumber = '00'                            // ← Tu system number  
param sapClient = '350'                                 // ← Tu client
param sapSystemAccountUsername = 'JP_LOPEZ'      // ← Usuario SAP
param sapSystemAccountPassword = 'PLACEHOLDER-UPDATE-BEFORE-DEPLOY'  // ← Password SAP
