# RBZ PC Health v0.3.1

UI/report workflow polish release.

## Changes from v0.3.0

- Removed the Yes/No/Cancel report-type prompt.
- Added explicit **Customer Report** button.
- Added explicit **Technician Report** button.
- Added **Open Reports** button.
- Fixes the visible literal `\r\n` text from the old report prompt by removing that prompt entirely.
- Report generation logic and diagnostic/remediation behaviour are otherwise unchanged from v0.3.0.
- Repair Centre remains limited to the same explicitly selected low-risk actions.

## Report workflow

After running a scan:

- **Customer Report** generates the simplified customer-facing report.
- **Technician Report** generates the detailed technician report.
- **Open Reports** opens the configured Reports directory.

## Bootstrap

```powershell
irm https://raw.githubusercontent.com/rbznet/RBZTechSolutions/main/bootstrap.ps1 | iex
```

## Local test

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\RBZHealth.ps1
```

Test:
1. Run Full Scan.
2. Confirm Customer Report and Technician Report become enabled.
3. Generate each report directly.
4. Confirm Open Reports opens the report directory.
5. Confirm Repair Centre behaviour is unchanged.

## Release

```powershell
.\build-release.ps1

gh release create v0.3.1 `
  ".\dist\RBZ-PC-Health-0.3.1.zip" `
  ".\dist\RBZ-PC-Health-0.3.1.sha256" `
  --repo rbznet/RBZTechSolutions `
  --title "RBZ PC Health v0.3.1" `
  --notes "Report workflow and UI polish."
```
