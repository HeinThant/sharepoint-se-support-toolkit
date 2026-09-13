@{
    RootModule = 'SharePointSE.Support.psm1'
    ModuleVersion = '0.1.0'
    GUID = 'e1808cee-60d1-4f02-bde4-c395299b24d4'
    Author = 'HeinThant'
    Description = 'Read-only SharePoint Server Subscription Edition support diagnostics.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Get-SESnapshot', 'Import-SESnapshot', 'Get-SEFinding', 'Export-SEReport', 'Find-SECorrelation')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{ PSData = @{ Tags = @('SharePoint', 'Diagnostics', 'Support'); ProjectUri = 'https://github.com/HeinThant/sharepoint-se-support-toolkit' } }
}
