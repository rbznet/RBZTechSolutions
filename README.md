# RBZ PC Health v0.2

Scan-only Windows technician diagnostic tool for RBZ Tech Solutions Ltd.

## v0.2 changes

- Redesigned technician dashboard with health score, status counts, Attention and All Results tabs.
- Finding detail pane for technical evidence and recommendations.
- Replaced ICMP/ping internet test with HTTPS connectivity testing.
- Device Manager findings now identify individual problem devices and attempt to include problem codes.
- Expanded system inventory, BIOS information, physical disk detail and network configuration.
- Added Secure Boot, TPM and BitLocker checks.
- Defender check now considers real-time protection and signature age.
- Weighted category scoring controlled by `Config/settings.json`.
- Improved HTML/JSON reports with score label, status counts and detailed findings.
- Still scan-only: v0.2 does not automatically repair or change the customer device.

## Bootstrap

Open Windows PowerShell as Administrator:

```powershell
irm https://raw.githubusercontent.com/rbznet/RBZTechSolutions/main/bootstrap.ps1 | iex
```

## Local test

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\RBZHealth.ps1
```

CLI:

```powershell
.\RBZHealth.ps1 -NoGui -Customer "Test Customer"
```

## Configuration

Edit `Config/settings.json`.

The configuration controls:

- application version
- paths
- GitHub release endpoints
- enabled checks
- network test endpoint
- diagnostic thresholds
- category scoring weights
- status scoring factors

## Release process

1. Update `app.version` in `Config/settings.json`.
2. Run:

```powershell
.\build-release.ps1
```

3. Create a GitHub release using the same version:

```powershell
gh release create v0.2.0 `
  ".\dist\RBZ-PC-Health-0.2.0.zip" `
  ".\dist\RBZ-PC-Health-0.2.0.sha256" `
  --repo rbznet/RBZTechSolutions `
  --title "RBZ PC Health v0.2.0" `
  --notes "v0.2 diagnostic and dashboard upgrade."
```

The bootstrapper reads the latest GitHub Release, validates SHA256, extracts the package and launches `RBZHealth.ps1`.

## Safety model

v0.2 performs diagnostics and reporting only. It does not:

- remove software
- disable startup entries
- modify services
- install drivers
- modify the registry
- delete customer data
- install Windows updates
- run SFC/DISM repairs

Remediation will be introduced only after the diagnostic engine has been tested across multiple Windows systems.
