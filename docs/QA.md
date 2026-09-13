# QA and acceptance

## Automated checks

Run `tests/Run-Tests.ps1` in PowerShell 5.1 and 7. Tests need no farm or external packages. The partial-collection integration test substitutes SharePoint commands within module scope on 5.1; PowerShell 7 verifies the live-runtime rejection instead.

GitHub Actions runs the suite on Windows for both engines. The workflow never collects live farm evidence. Its HTML artifacts use only the committed synthetic fixture.

## Manual report QA

- Demo clearly labels the source as Demo and shows two servers, two databases and three findings.
- Table content is readable on desktop; narrow windows can scroll the table horizontally.
- Print styles suppress the background and reduce table size.
- Exported HTML contains no executable scripts or external requests.

## Required real-farm acceptance (not performed by offline tests)

On a disposable or designated SE test farm with an approved read identity:

1. Compare farm build and NeedsUpgrade to `Get-SPFarm`.
2. Compare server count, addresses, roles, states and upgrade flags to `Get-SPServer`.
3. Compare all content databases, including disabled ones, to `Get-SPContentDatabase -NoStatusFilter`.
4. Run with an insufficiently authorized identity; verify a clear failure or Incomplete report and no clean result.
5. Verify singleton inventory and intentionally empty content-database inventory.
6. Inspect generated evidence for unwanted fields and verify output-folder ACLs.
7. Search an approved local ULS sample and compare GUID matches and line numbers manually.
8. Confirm no farm state changed; retain test-farm version, timestamp and reviewer sign-off.

## AI review

Request Copilot on the implementation PR and record the actual review outcome. Fix reproducible findings, rerun tests, and request another review when changes warrant it. CI success, repository instructions and an outstanding review request are not evidence that Copilot completed review.
