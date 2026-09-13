#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'src/SharePointSE.Support/SharePointSE.Support.psd1') -Force
$script:passed = 0
function Test-Case([string]$Name, [scriptblock]$Body) {
    & $Body
    $script:passed++
    Write-Host "PASS $Name"
}
function Assert-True($Condition, [string]$Message = 'Assertion failed') {
    if (-not $Condition) { throw $Message }
}
function Assert-Throws([scriptblock]$Body, [string]$Pattern = '*') {
    $thrown = $false
    try { & $Body | Out-Null } catch {
        $thrown = $true
        if ($_.Exception.Message -notlike $Pattern) { throw "Unexpected error: $($_.Exception.Message)" }
    }
    Assert-True $thrown 'Expected an exception'
}
function New-Snapshot {
    Import-SESnapshot (Join-Path $root 'examples/demo-snapshot.json')
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('se-tests-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temp
try {
    Test-Case 'PowerShell source parses without errors' {
        foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object Extension -in @('.ps1', '.psm1', '.psd1')) {
            $tokens = $null; $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
            Assert-True ($parseErrors.Count -eq 0) "Parse error in $($file.FullName): $parseErrors"
        }
    }
    Test-Case 'Module exports exactly the supported commands' {
        Assert-True (@(Get-Command -Module SharePointSE.Support).Count -eq 5)
    }
    Test-Case 'Demo yields three expected configuration findings' {
        $f = @(Get-SEFinding (New-Snapshot))
        Assert-True ($f.Count -eq 3)
        Assert-True (($f.Id -join ',') -eq 'FARM_UPGRADE,ITEM_UPGRADE,ITEM_STATUS')
    }
    Test-Case 'Clean inventory yields no findings' {
        $s = New-Snapshot
        $s.Farm.NeedsUpgrade = $false; $s.Servers[1].NeedsUpgrade = $false; $s.Databases[1].Status = 'Online'
        Assert-True (@(Get-SEFinding $s).Count -eq 0)
        Assert-True ((Export-SEReport $s $temp).Status -eq 'No findings')
    }
    Test-Case 'Database upgrade requirement is detected' {
        $s = New-Snapshot; $s.Databases[0].NeedsUpgrade = $true
        Assert-True (@(Get-SEFinding $s | Where-Object { $_.Id -eq 'ITEM_UPGRADE' -and $_.Target -eq 'WSS_Content_Demo' }).Count -eq 1)
    }
    Test-Case 'Missing farm cannot look healthy' {
        $s = New-Snapshot; $s.Farm = $null
        Assert-True ((Export-SEReport $s $temp).Status -eq 'Incomplete')
    }
    Test-Case 'Empty servers cannot look healthy' {
        $s = New-Snapshot; $s.Servers = @()
        Assert-True (@(Get-SEFinding $s | Where-Object Id -eq 'INVENTORY_EMPTY').Count -eq 1)
    }
    Test-Case 'Empty databases produce unknown coverage' {
        $s = New-Snapshot; $s.Databases = @()
        Assert-True ((Export-SEReport $s $temp).Status -eq 'Incomplete')
    }
    Test-Case 'Collection failures remain visible alongside successful inventory' {
        $s = New-Snapshot; $s.CollectionErrors = @([pscustomobject]@{ Collector = 'Databases'; Message = 'Access denied' })
        $r = Export-SEReport $s $temp
        Assert-True ($r.Status -eq 'Incomplete')
        Assert-True ((Get-Content $r.HtmlPath -Raw).Contains('Access denied'))
    }
    Test-Case 'Blank status produces unknown rather than healthy' {
        $s = New-Snapshot; $s.Servers[0].Status = ''
        Assert-True ((Export-SEReport $s $temp).Status -eq 'Incomplete')
    }
    Test-Case 'Reject unsupported schema' {
        $s = New-Snapshot; $s.SchemaVersion = '2.0'
        Assert-Throws { Get-SEFinding $s } '*Unsupported*'
    }
    Test-Case 'Reject missing required fields' {
        $s = New-Snapshot; $s.PSObject.Properties.Remove('Servers')
        Assert-Throws { Get-SEFinding $s } '*missing*'
    }
    Test-Case 'Reject non-array inventory' {
        $s = New-Snapshot; $s.Servers = $s.Servers[0]
        Assert-Throws { Get-SEFinding $s } '*array*'
    }
    Test-Case 'Reject string booleans instead of misreading false as true' {
        $s = New-Snapshot; $s.Farm.NeedsUpgrade = 'false'
        Assert-Throws { Get-SEFinding $s } '*boolean*'
    }
    Test-Case 'Reject malformed inventory records' {
        $s = New-Snapshot; $s.Servers = @([pscustomobject]@{ Name = 'server' })
        Assert-Throws { Get-SEFinding $s } '*missing*'
    }
    Test-Case 'Reject invalid timestamp' {
        $s = New-Snapshot; $s.CapturedAtUtc = 'yesterday'
        Assert-Throws { Get-SEFinding $s } '*timestamp*'
    }
    Test-Case 'Reject invalid build' {
        $s = New-Snapshot; $s.Farm.BuildVersion = '<script>'
        Assert-Throws { Get-SEFinding $s } '*build*'
    }
    Test-Case 'Reject malformed JSON' {
        $path = Join-Path $temp 'bad.json'; Set-Content $path '{broken'
        Assert-Throws { Import-SESnapshot $path }
    }
    Test-Case 'Reject missing snapshot file' { Assert-Throws { Import-SESnapshot (Join-Path $temp 'missing.json') } }
    Test-Case 'Reject oversized snapshot before parsing' {
        $path = Join-Path $temp 'oversized.json'
        [IO.File]::WriteAllText($path, (' ' * (10MB + 1)))
        Assert-Throws { Import-SESnapshot $path } '*at most 10 MB*'
    }
    Test-Case 'Reports escape hostile values and disable script execution' {
        $s = New-Snapshot; $s.Servers[1].Name = '<script>alert(1)</script>'
        $s.CollectionErrors = @([pscustomobject]@{ Collector = '<img>'; Message = '<svg onload=alert(2)>' })
        $r = Export-SEReport $s $temp
        $html = Get-Content $r.HtmlPath -Raw
        Assert-True (-not $html.Contains('<script>'))
        Assert-True (-not $html.Contains('<svg'))
        Assert-True ($html.Contains('&lt;script&gt;'))
        Assert-True ($html.Contains('Content-Security-Policy'))
    }
    Test-Case 'JSON preserves evidence and snapshot round trips' {
        $r = Export-SEReport (New-Snapshot) $temp
        $report = Get-Content $r.JsonPath -Raw | ConvertFrom-Json
        Assert-True ($report.Findings.Count -eq 3)
        Assert-True ((Import-SESnapshot (Join-Path $r.Directory 'snapshot.json')).Source -eq 'Demo')
    }
    Test-Case 'Repeated exports never overwrite reports' {
        $r1 = Export-SEReport (New-Snapshot) $temp; $r2 = Export-SEReport (New-Snapshot) $temp
        Assert-True ($r1.Directory -ne $r2.Directory)
        Assert-True (Test-Path $r1.HtmlPath)
    }
    $id = 'c6273a92-d88a-445e-964d-1b0a367cb153'
    $log = Join-Path $temp 'uls[1].log'
    @('unrelated', "entry $id message", "entry $($id.ToUpperInvariant()) message", "prefix0$id suffix", "entry $id final") | Set-Content -LiteralPath $log -Encoding UTF8
    Test-Case 'ULS search uses literal file paths and exact GUID boundaries' {
        $matches = @(Find-SECorrelation -Path $log -CorrelationId $id)
        Assert-True ($matches.Count -eq 3)
        Assert-True ($matches[0].LineNumber -eq 2)
    }
    Test-Case 'ULS result cap is enforced across files' {
        $matches = @(Find-SECorrelation -Path @($log, $log) -CorrelationId $id -MaxMatches 2 -WarningAction SilentlyContinue)
        Assert-True ($matches.Count -eq 2)
    }
    Test-Case 'ULS missing correlation returns zero results' {
        Assert-True (@(Find-SECorrelation -Path $log -CorrelationId ([guid]::NewGuid())).Count -eq 0)
    }
    Test-Case 'ULS rejects invalid GUID' { Assert-Throws { Find-SECorrelation -Path $log -CorrelationId 'not-a-guid' } }
    Test-Case 'ULS rejects directories' { Assert-Throws { Find-SECorrelation -Path $temp -CorrelationId $id } '*Not a file*' }
    Test-Case 'ULS rejects oversized files' {
        $large = Join-Path $temp 'large.log'
        [IO.File]::WriteAllText($large, ('x' * (1MB + 1)))
        Assert-Throws { Find-SECorrelation -Path $large -CorrelationId $id -MaxFileSizeMB 1 } '*size limit*'
    }
    Test-Case 'Live collection fails clearly outside the supported shell' {
        Assert-Throws { Get-SESnapshot } '*SharePoint Management Shell*'
    }
    Test-Case 'Collector handles partial failure (mocked SharePoint commands)' {
        if ($PSVersionTable.PSEdition -eq 'Desktop') {
            $module = Get-Module SharePointSE.Support
            & $module {
                function Get-SPFarm { [CmdletBinding()]param(); [pscustomobject]@{ BuildVersion = [version]'16.0.1.0'; NeedsUpgrade = $false } }
                function Get-SPServer { [CmdletBinding()]param(); throw 'simulated server collector failure' }
                function Get-SPContentDatabase { [CmdletBinding()]param([switch]$NoStatusFilter); [pscustomobject]@{ Name = 'Content'; Status = 'Online'; NeedsUpgrade = $false } }
                $s = Get-SESnapshot
                if ($s.CollectionErrors.Count -ne 1 -or $s.Databases.Count -ne 1 -or $s.CollectionErrors[0].Collector -ne 'Servers') { throw 'Partial collection contract failed' }
            }
        } else {
            Assert-Throws { Get-SESnapshot } '*Windows PowerShell 5.1*'
        }
    }
    Test-Case 'CLI demo exits 1 with report and missing input exits 2' {
        $engine = (Get-Process -Id $PID).Path
        & $engine -NoProfile -File (Join-Path $root 'Invoke-SESupport.ps1') -Demo -OutputDirectory $temp | Out-Null
        Assert-True ($LASTEXITCODE -eq 1)
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & $engine -NoProfile -File (Join-Path $root 'Invoke-SESupport.ps1') -SnapshotPath (Join-Path $temp 'missing.json') 2>&1 | Out-Null
        $ErrorActionPreference = $previousPreference
        Assert-True ($LASTEXITCODE -eq 2)
    }
    Test-Case 'CLI clean snapshot exits 0 and incomplete snapshot exits 2' {
        $engine = (Get-Process -Id $PID).Path
        $s = New-Snapshot
        $s.Farm.NeedsUpgrade = $false; $s.Servers[1].NeedsUpgrade = $false; $s.Databases[1].Status = 'Online'
        $path = Join-Path $temp 'cli-snapshot.json'
        $s | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
        & $engine -NoProfile -File (Join-Path $root 'Invoke-SESupport.ps1') -SnapshotPath $path -OutputDirectory $temp | Out-Null
        Assert-True ($LASTEXITCODE -eq 0)
        $s.Servers = @()
        $s | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
        & $engine -NoProfile -File (Join-Path $root 'Invoke-SESupport.ps1') -SnapshotPath $path -OutputDirectory $temp | Out-Null
        Assert-True ($LASTEXITCODE -eq 2)
    }
    Write-Host "All $script:passed tests passed on PowerShell $($PSVersionTable.PSVersion)."
} finally {
    # Delete only the unique directory created by this test run, beneath the temp root.
    $resolved = [IO.Path]::GetFullPath($temp)
    $expectedParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ((Split-Path $resolved -Parent) -eq $expectedParent -and (Split-Path $resolved -Leaf) -like 'se-tests-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
