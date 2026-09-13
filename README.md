# SharePoint SE Support Toolkit

Read-only support triage for **SharePoint Server Subscription Edition**. Capture configuration evidence, identify upgrade flags, search local ULS logs by correlation ID, and generate an offline HTML report with JSON evidence.

**v0.1.0 — initial implementation.** Live collection requires validation on a real SE test farm before production adoption. This project is not a Microsoft product or a replacement for SharePoint Health Analyzer.

## Quick start: no SharePoint required

Run from the repository root in Windows PowerShell 5.1 or PowerShell 7:

```powershell
./Invoke-SESupport.ps1 -Demo
```

Open `reports/se-report-<id>/report.html`. The synthetic example deliberately produces three warnings and exits **1**. Its build number is illustrative, not a released build or a patch recommendation.

## Collect a farm

On a SharePoint SE farm server, open **SharePoint Management Shell (Windows PowerShell 5.1)** with an identity already authorized for SharePoint PowerShell:

```powershell
./Invoke-SESupport.ps1 -OutputDirectory C:\Support\Reports
```

The tool calls `Get-SPFarm`, `Get-SPServer` and `Get-SPContentDatabase -NoStatusFilter`. It does not install prerequisites, grant permissions, change farm configuration or load the snap-in automatically. Output is written only to a new local report directory. Existing reports are never overwritten.

| Output | Purpose |
| --- | --- |
| `report.html` | Offline summary and findings with suggested next steps |
| `report.json` | Findings plus captured evidence |
| `snapshot.json` | Validated input for later offline analysis |

```powershell
./Invoke-SESupport.ps1 -SnapshotPath C:\Support\Reports\se-report-EXAMPLE\snapshot.json
```

| Exit | Meaning |
| --- | --- |
| 0 | Complete collected inventory with no findings in implemented rules |
| 1 | Configuration observations require attention |
| 2 | Incomplete coverage, unsupported environment, invalid input or execution failure |

An empty inventory is conservatively marked incomplete. A disabled database can be intentionally closed to new sites. Server configuration status does not establish network or service availability. A clean result does not certify security, health, patch currency or product edition; operators must verify they are collecting an SE farm.

## Search ULS evidence

```powershell
Import-Module ./src/SharePointSE.Support/SharePointSE.Support.psd1
Find-SECorrelation -Path C:\Support\ULS\server.log `
    -CorrelationId 'c6273a92-d88a-445e-964d-1b0a367cb153' -MaxMatches 200
```

Searches only explicitly named files, with literal paths and exact GUID boundaries. Defaults: at most 100 MB per file and 200 returned lines across all files. It streams files and closes handles even when the cap is reached. A warning means matches may be truncated. This is a text-line search, not a ULS parser or farm-wide log merge. No logs are uploaded. Preserve original ULS files and timestamps when escalating incidents.

## Test and QA

```powershell
powershell.exe -NoProfile -File ./tests/Run-Tests.ps1
pwsh -NoProfile -File ./tests/Run-Tests.ps1
```

Dependency-free behavioral tests cover rules, malformed snapshots, partial collector failure, report escaping, evidence round trips, unique output directories, ULS matching and bounds, and CLI exit behavior. GitHub Actions runs both engines and publishes only synthetic demo reports. See [QA and farm acceptance](docs/QA.md) and [architecture](docs/ARCHITECTURE.md).

For AI review, open an implementation pull request and request **Copilot** as reviewer. Repository instructions are in `.github/copilot-instructions.md`. A Copilot review is a separate service result and is not implied by a successful CI run.

## Handling support data

Reports include internal server/database names and collection error details. ULS matches can contain user data and URLs. Output inherits filesystem permissions; choose a restricted destination, review/redact before sharing, and follow your retention policy. The toolkit does not anonymize reports. Generated reports and logs are ignored by Git. Do not attach real farm evidence to public issues or CI runs.

## References

- [Microsoft: Get-SPFarm](https://learn.microsoft.com/en-us/powershell/module/sharepointserver/get-spfarm?view=sharepoint-server-ps)
- [Microsoft: Get-SPServer](https://learn.microsoft.com/en-us/powershell/module/sharepointserver/get-spserver?view=sharepoint-server-ps)
- [Microsoft: Get-SPContentDatabase](https://learn.microsoft.com/en-us/powershell/module/sharepointserver/get-spcontentdatabase?view=sharepoint-server-ps)
- [GitHub: requesting Copilot code review](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/request-a-code-review/use-code-review)
