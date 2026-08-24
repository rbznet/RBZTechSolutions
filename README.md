# RBZ PC Health v0.2.2

Scan-only Windows technician diagnostic tool for RBZ Tech Solutions Ltd.

## v0.2.2 changes

- Separates DNS, TCP 443 reachability, and HTTPS certificate/session validation.
- TLS trust failures no longer incorrectly report that internet access itself is unavailable when DNS and TCP connectivity succeed.
- Physical disks are identified by disk ID and serial suffix to distinguish identical models.
- Startup applications are listed in finding details.
- Windows Update reports latest installed update, pending updates, recent failed update events, and pending restart state.
- Customer report puts Needs Attention first.
- Customer, device and unique scan ID are displayed at the top of reports.
- Score explanation shows category-level deductions.
- Full hardware serial numbers remain in technician JSON but are hidden from customer HTML by default.
- GUI version is read dynamically from settings.json.

## Bootstrap

```powershell
irm https://raw.githubusercontent.com/rbznet/RBZTechSolutions/main/bootstrap.ps1 | iex
```

## Local test

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\RBZHealth.ps1
```

## Release

```powershell
.\build-release.ps1

gh release create v0.2.2 `
  ".\dist\RBZ-PC-Health-0.2.2.zip" `
  ".\dist\RBZ-PC-Health-0.2.2.sha256" `
  --repo rbznet/RBZTechSolutions `
  --title "RBZ PC Health v0.2.2" `
  --notes "v0.2.2 diagnostic and reporting refinements."
```

v0.2.2 remains scan-only and does not automatically change the customer device.
