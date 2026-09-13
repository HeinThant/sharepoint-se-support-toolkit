Review this PowerShell 5.1-compatible SharePoint Server Subscription Edition toolkit for correctness, security and operational safety.

- Live collection must remain read-only: no farm updates, service restarts, SQL writes or automatic remediation.
- Failed collectors and absent inventory must never appear as successful health checks.
- Never interpolate unencoded inventory, error messages or log lines into HTML.
- No credentials, production logs, real snapshots or generated reports should be committed or uploaded to CI.
- Check pipeline cardinality (zero, one, many), strict-mode property access, JSON type validation and resource disposal.
- Windows PowerShell 5.1 is required for live SharePoint cmdlets. PowerShell 7 supports offline functionality only.
- Run tests/Run-Tests.ps1 in Windows PowerShell 5.1 and PowerShell 7. Mocked tests do not prove real-farm compatibility.
- Report concrete defects with reproduction steps and severity. Do not claim that configuration status establishes availability or patch currency.
