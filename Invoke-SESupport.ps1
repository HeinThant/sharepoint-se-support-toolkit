#requires -Version 5.1
[CmdletBinding(DefaultParameterSetName = 'Live')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Demo')][switch]$Demo,
    [Parameter(Mandatory, ParameterSetName = 'Snapshot')][string]$SnapshotPath,
    [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
try {
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $PSScriptRoot 'reports' }
    Import-Module (Join-Path $PSScriptRoot 'src/SharePointSE.Support/SharePointSE.Support.psd1') -Force
    $snapshot = switch ($PSCmdlet.ParameterSetName) {
        'Demo' { Import-SESnapshot (Join-Path $PSScriptRoot 'examples/demo-snapshot.json') }
        'Snapshot' { Import-SESnapshot $SnapshotPath }
        'Live' { Get-SESnapshot }
    }
    $result = Export-SEReport -Snapshot $snapshot -OutputDirectory $OutputDirectory
    $result | Format-List | Out-Host
    if ($result.Status -eq 'Incomplete') { exit 2 }
    if ($result.FindingCount -gt 0) { exit 1 }
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 2
}
