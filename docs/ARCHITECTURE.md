# Architecture

The CLI selects one input source: live SharePoint cmdlets, a stored snapshot, or synthetic demo evidence. All paths pass through the same schema validation and deterministic rule engine. The exporter creates an HTML summary and JSON evidence in a new directory. Local ULS correlation search is an independent utility.

## Boundaries

1. **Collection:** Windows PowerShell 5.1, current authorized identity, three read-only SharePoint queries. Each query fails independently so evidence from successful collectors survives.
2. **Snapshot contract:** version 1.0, source, capture timestamp, optional farm metadata, arrays of servers, databases and collection errors. Unknown schema and incorrectly typed booleans are rejected. Only explicitly selected fields are serialized; SharePoint object graphs are not exported.
3. **Analysis:** upgrade flags and non-Online configuration states become warnings. Missing inventory, blank status, or failed collection becomes Unknown and an Incomplete overall report.
4. **Presentation:** HTML-encoded text, no JavaScript or external resources, a restrictive CSP, and local JSON evidence. No findings is scoped to the implemented checks.
5. **Evidence search:** literal input files, GUID boundaries, size limits, global match cap and deterministic handle disposal.

## Intentionally outside v0.1

No remote execution, automatic remediation, patch catalog lookup, SQL connectivity tests, certificate monitoring, endpoint availability checks, farm-wide ULS aggregation, credential storage, telemetry, or SharePoint Online support. Farm BuildVersion alone does not identify Subscription Edition or establish patch parity between servers.

Collectors can be extended with a versioned schema and corresponding failure/empty/success tests. New checks should cite their semantics and avoid interpreting expected administrative states as outages.
