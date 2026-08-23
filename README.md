# RBZ PC Health v0.1

Scan-only Windows technician diagnostic tool for RBZ Tech Solutions Ltd.

## Safety model
v0.1 performs diagnostics and reporting only. It does not remove software, disable startup items, change services, install drivers, alter the registry, or delete customer data.

## Local test
Open Windows PowerShell as Administrator:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\RBZHealth.ps1
```

CLI test:

```powershell
.\RBZHealth.ps1 -NoGui -Customer "Test Customer"
```

## Configuration
Edit `Config/settings.json`. Paths, GitHub URLs, thresholds, network targets, report names and bootstrap behaviour are kept there rather than hard-coded into the main application where practical.

## GitHub release process
1. Update `app.version` in `Config/settings.json`.
2. Run `./build-release.ps1`.
3. Create a GitHub Release using the same version/tag.
4. Upload both files from `dist`:
   - `RBZ-PC-Health-x.y.z.zip`
   - `RBZ-PC-Health-x.y.z.sha256`
5. The bootstrapper reads the latest GitHub Release, downloads both assets and compares SHA256 before launching.

## Bootstrap command
After you create the repository and first release:

```powershell
irm https://raw.githubusercontent.com/rbznet/RBZTechSolutions/main/bootstrap.ps1 | iex
```

The bootstrapper and configuration are configured for the rbznet/RBZTechSolutions repository.

## Reports
Each scan can produce:
- JSON: machine-readable results for future portal/API ingestion.
- HTML: customer/technician-readable report.

A later version can convert HTML to PDF, add pre/post comparisons, technician approval remediation and code signing.
