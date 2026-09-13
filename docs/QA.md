# QA and acceptance

## Initial QA record — 2026-09-13

- 34 tests passed locally on Windows PowerShell 5.1.26100.9444 and PowerShell 7.6.5.
- GitHub hosted tests passed after correcting workflow shell validation and the test runner's handling of expected nonzero CLI exit codes.
- GitHub's Codex reviewer identified a P2 issue opening active ULS files. The reader now uses read/write/delete sharing; a regression test holds a writer open and verifies the reader releases its handle.
- The formal Copilot reviewer request did not register a reviewer. The completed AI review was provided by `chatgpt-codex-connector`, not Copilot.
- HTML structure, escaping and report data were checked automatically. Browser visual inspection was blocked by the local-file URL policy and remains outstanding.
- No SharePoint farm is installed in the test environment. Real-farm acceptance below remains outstanding.

See [PR #1](https://github.com/HeinThant/sharepoint-se-support-toolkit/pull/1) for the review and current checks.

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
