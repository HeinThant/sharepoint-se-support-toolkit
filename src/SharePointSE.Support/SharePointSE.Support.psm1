Set-StrictMode -Version Latest

function Assert-SESnapshot {
    param([Parameter(Mandatory)]$Snapshot)
    foreach ($name in @('SchemaVersion', 'CapturedAtUtc', 'Source', 'Farm', 'Servers', 'Databases', 'CollectionErrors')) {
        if ($null -eq $Snapshot.PSObject.Properties[$name]) { throw "Snapshot is missing '$name'." }
    }
    if ($Snapshot.SchemaVersion -ne '1.0') { throw 'Unsupported snapshot schema; expected 1.0.' }
    if ($Snapshot.Source -notin @('Live', 'Demo')) { throw 'Snapshot Source must be Live or Demo.' }
    $date = [datetimeoffset]::MinValue
    if ($Snapshot.CapturedAtUtc -is [datetime]) { $Snapshot.CapturedAtUtc = $Snapshot.CapturedAtUtc.ToUniversalTime().ToString('o') }
    if (-not [datetimeoffset]::TryParse([string]$Snapshot.CapturedAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$date)) { throw 'Invalid capture timestamp.' }
    foreach ($name in @('Servers', 'Databases', 'CollectionErrors')) {
        if ($Snapshot.$name -isnot [array]) { throw "Snapshot '$name' must be an array." }
    }
    if ($null -ne $Snapshot.Farm) {
        foreach ($name in @('BuildVersion', 'NeedsUpgrade')) {
            if ($null -eq $Snapshot.Farm.PSObject.Properties[$name]) { throw "Farm is missing '$name'." }
        }
        if ($Snapshot.Farm.NeedsUpgrade -isnot [bool]) { throw 'Farm NeedsUpgrade must be boolean.' }
        $version = $null
        if (-not [version]::TryParse([string]$Snapshot.Farm.BuildVersion, [ref]$version)) { throw 'Invalid farm build version.' }
    }
    foreach ($group in @('Servers', 'Databases')) {
        foreach ($item in $Snapshot.$group) {
            foreach ($name in @('Name', 'Status', 'NeedsUpgrade')) {
                if ($null -eq $item -or $null -eq $item.PSObject.Properties[$name]) { throw "$group item is missing '$name'." }
            }
            if ([string]::IsNullOrWhiteSpace([string]$item.Name)) { throw "$group item has an empty name." }
            if ($item.NeedsUpgrade -isnot [bool]) { throw "$group NeedsUpgrade must be boolean." }
        }
    }
    foreach ($item in $Snapshot.CollectionErrors) {
        foreach ($name in @('Collector', 'Message')) {
            if ($null -eq $item -or $null -eq $item.PSObject.Properties[$name]) { throw "Collection error is missing '$name'." }
        }
    }
}

function Get-SESnapshot {
    <# .SYNOPSIS
    Collects farm metadata using the current SharePoint Management Shell identity.
    #>
    [CmdletBinding()]
    param()
    if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) {
        throw 'Live collection requires Windows PowerShell 5.1 in the SharePoint Management Shell. Use -Demo elsewhere.'
    }
    foreach ($command in @('Get-SPFarm', 'Get-SPServer', 'Get-SPContentDatabase')) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            throw "Missing $command. Open SharePoint Management Shell on a farm server with authorized shell access."
        }
    }
    $errors = New-Object 'System.Collections.Generic.List[object]'
    $farm = $null
    $servers = @()
    $databases = @()
    try {
        $raw = Get-SPFarm -ErrorAction Stop
        $farm = [pscustomobject]@{ BuildVersion = [string]$raw.BuildVersion; NeedsUpgrade = $raw.NeedsUpgrade }
    } catch { $errors.Add([pscustomobject]@{ Collector = 'Farm'; Message = $_.Exception.Message }) }
    try {
        $servers = @(Get-SPServer -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{ Name = [string]$_.Address; Role = [string]$_.Role; Status = [string]$_.Status; NeedsUpgrade = $_.NeedsUpgrade }
        })
    } catch { $errors.Add([pscustomobject]@{ Collector = 'Servers'; Message = $_.Exception.Message }) }
    try {
        $databases = @(Get-SPContentDatabase -NoStatusFilter -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{ Name = [string]$_.Name; Status = [string]$_.Status; NeedsUpgrade = $_.NeedsUpgrade }
        })
    } catch { $errors.Add([pscustomobject]@{ Collector = 'Databases'; Message = $_.Exception.Message }) }
    $snapshot = [pscustomobject]@{
        SchemaVersion = '1.0'; CapturedAtUtc = [datetime]::UtcNow.ToString('o'); Source = 'Live'
        Farm = $farm; Servers = $servers; Databases = $databases; CollectionErrors = @($errors.ToArray())
    }
    Assert-SESnapshot $snapshot
    return $snapshot
}

function Import-SESnapshot {
    <# .SYNOPSIS
    Imports and validates a previously collected JSON snapshot.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.PSIsContainer -or $file.Length -gt 10MB) { throw 'Snapshot must be a JSON file of at most 10 MB.' }
    $snapshot = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    Assert-SESnapshot $snapshot
    return $snapshot
}

function Get-SEFinding {
    <# .SYNOPSIS
    Evaluates deterministic rules; missing inventory never produces a clean result.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Snapshot)
    Assert-SESnapshot $Snapshot
    foreach ($errorItem in $Snapshot.CollectionErrors) {
        [pscustomobject]@{ Id = 'COLLECTION_FAILED'; Severity = 'Unknown'; Target = [string]$errorItem.Collector; Summary = [string]$errorItem.Message; Action = 'Resolve shell permissions or collection failure and collect again.' }
    }
    if ($null -eq $Snapshot.Farm) {
        [pscustomobject]@{ Id = 'FARM_MISSING'; Severity = 'Unknown'; Target = 'Farm'; Summary = 'Farm metadata was not collected.'; Action = 'Check the SharePoint Management Shell and farm access.' }
    } elseif ($Snapshot.Farm.NeedsUpgrade) {
        [pscustomobject]@{ Id = 'FARM_UPGRADE'; Severity = 'Warning'; Target = 'Farm'; Summary = 'Farm reports NeedsUpgrade.'; Action = 'Review the approved patch and configuration upgrade plan; this toolkit does not perform upgrades.' }
    }
    foreach ($group in @('Servers', 'Databases')) {
        if ($Snapshot.$group.Count -eq 0) {
            [pscustomobject]@{ Id = 'INVENTORY_EMPTY'; Severity = 'Unknown'; Target = $group; Summary = 'No inventory returned; coverage is incomplete.'; Action = 'Confirm whether empty inventory is expected and verify collection permissions.' }
        }
        foreach ($item in $Snapshot.$group) {
            if ($item.NeedsUpgrade) {
                [pscustomobject]@{ Id = 'ITEM_UPGRADE'; Severity = 'Warning'; Target = [string]$item.Name; Summary = "$group item reports NeedsUpgrade."; Action = 'Check patch deployment and configuration upgrade status with the farm administrator.' }
            }
            # Disabled content databases may be intentionally closed to new sites.
            # SPServer.Status is configuration state, not a network availability probe.
            if ($item.Status -ne 'Online') {
                $severity = 'Warning'
                if ([string]::IsNullOrWhiteSpace([string]$item.Status)) { $severity = 'Unknown' }
                [pscustomobject]@{ Id = 'ITEM_STATUS'; Severity = $severity; Target = [string]$item.Name; Summary = "$group configuration status: '$($item.Status)'."; Action = 'Verify intended configuration. This observation does not prove an outage.' }
            }
        }
    }
}

function Export-SEReport {
    <# .SYNOPSIS
    Writes a new report directory containing JSON evidence and an offline HTML report.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Snapshot, [Parameter(Mandatory)][string]$OutputDirectory)
    Assert-SESnapshot $Snapshot
    $findings = @(Get-SEFinding $Snapshot)
    $status = 'No findings'
    if ($findings.Count -gt 0) { $status = 'Needs attention' }
    if (@($findings | Where-Object Severity -eq 'Unknown').Count -gt 0) { $status = 'Incomplete' }
    $report = [pscustomobject]@{ ToolkitVersion = '0.1.0'; Status = $status; Snapshot = $Snapshot; Findings = $findings }
    $root = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
    $destination = Join-Path $root ('se-report-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $destination -ErrorAction Stop
    $jsonPath = Join-Path $destination 'report.json'
    $htmlPath = Join-Path $destination 'report.html'
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8 -ErrorAction Stop
    $Snapshot | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $destination 'snapshot.json') -Encoding UTF8 -ErrorAction Stop
    $rows = @($findings | ForEach-Object {
        $cells = @($_.Severity, $_.Id, $_.Target, $_.Summary, $_.Action) | ForEach-Object { '<td>' + [System.Net.WebUtility]::HtmlEncode([string]$_) + '</td>' }
        '<tr>' + ($cells -join '') + '</tr>'
    }) -join "`n"
    if ($findings.Count -eq 0) { $rows = '<tr><td colspan="5">No findings in the collected configuration checks.</td></tr>' }
    $source = [System.Net.WebUtility]::HtmlEncode([string]$Snapshot.Source)
    $captured = [System.Net.WebUtility]::HtmlEncode([string]$Snapshot.CapturedAtUtc)
    $build = 'Unavailable'
    if ($null -ne $Snapshot.Farm) { $build = [System.Net.WebUtility]::HtmlEncode([string]$Snapshot.Farm.BuildVersion) }
    $html = @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<title>SharePoint SE support report</title>
<style>body{margin:0;background:#f1f5f9;color:#172b45;font:16px/1.6 system-ui,sans-serif}main{max-width:1150px;margin:auto;padding:40px 24px}header{border-top:5px solid #008577;padding:24px;background:white;border-radius:8px}h1{font-size:32px;margin:8px 0}.label{color:#00695f;font-weight:700;letter-spacing:2px;font-size:12px}.cards{display:flex;flex-wrap:wrap;gap:16px;margin:24px 0}.card{background:white;border:1px solid #dbe3ec;border-radius:8px;padding:18px;flex:1;min-width:170px}.card strong{display:block;font-size:24px}.table-wrap{overflow-x:auto;background:white;border-radius:8px}table{border-collapse:collapse;width:100%;min-width:700px}th,td{text-align:left;padding:14px;border-bottom:1px solid #dbe3ec;vertical-align:top;overflow-wrap:anywhere}th{background:#172b45;color:white}footer{margin-top:24px;color:#42556c}@media print{body{background:white}main{padding:0}.table-wrap{overflow:visible}table{min-width:0;font-size:11px}}</style></head>
<body><main><header><div class="label">SUPPORT TOOLKIT / v0.1.0</div><h1>SharePoint SE diagnostic report</h1><p><strong>$status</strong> &middot; Source: $source &middot; Captured: $captured</p><p>Configuration evidence for support triage. Demo reports contain synthetic data.</p></header>
<section class="cards" aria-label="Inventory summary"><div class="card">Farm build<strong>$build</strong></div><div class="card">Servers<strong>$($Snapshot.Servers.Count)</strong></div><div class="card">Content databases<strong>$($Snapshot.Databases.Count)</strong></div><div class="card">Findings<strong>$($findings.Count)</strong></div></section>
<h2>Findings and next steps</h2><div class="table-wrap"><table><thead><tr><th>Severity</th><th>Rule</th><th>Target</th><th>Observation</th><th>Next step</th></tr></thead><tbody>$rows</tbody></table></div>
<footer>Read-only collection. No remediation performed. No findings does not certify farm health, security, patch currency, or service availability. Reports can contain internal names and error details; review before sharing. JSON evidence is stored alongside this file.</footer></main></body></html>
"@
    Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8 -ErrorAction Stop
    [pscustomobject]@{ Directory = $destination; HtmlPath = $htmlPath; JsonPath = $jsonPath; Status = $status; FindingCount = $findings.Count }
}

function Find-SECorrelation {
    <# .SYNOPSIS
    Searches explicitly provided local ULS log files for an exact correlation GUID.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Path,
        [Parameter(Mandatory)][guid]$CorrelationId,
        [ValidateRange(1, 10000)][int]$MaxMatches = 200,
        [ValidateRange(1, 1024)][int]$MaxFileSizeMB = 100
    )
    $count = 0
    $pattern = '(?i)(?<![0-9a-f-])' + [regex]::Escape($CorrelationId.ToString('D')) + '(?![0-9a-f-])'
    foreach ($logPath in $Path) {
        $file = Get-Item -LiteralPath $logPath -ErrorAction Stop
        if ($file.PSIsContainer -or $file.Length -gt ($MaxFileSizeMB * 1MB)) { throw "Not a file or exceeds size limit: $logPath" }
        $reader = New-Object System.IO.StreamReader($file.FullName)
        try {
            $lineNumber = 0
            while ($null -ne ($line = $reader.ReadLine())) {
                $lineNumber++
                if ($line -match $pattern) {
                    [pscustomobject]@{ Path = $file.FullName; LineNumber = $lineNumber; Line = $line }
                    $count++
                    if ($count -ge $MaxMatches) { Write-Warning 'Match limit reached; results may be truncated.'; return }
                }
            }
        } finally { $reader.Dispose() }
    }
}

Export-ModuleMember -Function Get-SESnapshot, Import-SESnapshot, Get-SEFinding, Export-SEReport, Find-SECorrelation
