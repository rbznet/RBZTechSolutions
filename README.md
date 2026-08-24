# RBZ PC Health v0.3.0

First service-ready RBZ PC Health release.

## v0.3.0

### Service workflow
- Customer field
- Job reference field
- Full diagnostic scan
- Attention / All Results views
- Repair Centre
- Customer report
- Technician report
- Service-action audit log

### Guided Repair Centre
v0.3.0 only exposes deliberately low-risk actions:

- Microsoft Defender Quick Scan
- DISM `/Online /Cleanup-Image /ScanHealth`
- SFC `/verifyonly`
- Temporary-file cleanup

Every action:
- must be explicitly ticked by the technician
- requires a confirmation dialog
- is logged
- is included in generated reports
- does not silently run during a scan

### Intentionally NOT included
- driver installation
- Windows Update installation
- registry cleaning
- debloat scripts
- service disabling
- Secure Boot changes
- BitLocker changes
- software removal
- BIOS/firmware changes

### Customer vs Technician reports
Customer reports hide Info findings and sensitive hardware detail where configured.
Technician reports retain full diagnostic detail and category score deductions.

### Branding
Brand/product text, website, support email and report colours are configured in `Config/settings.json`.
A future logo can be placed at:

`Assets\rbz-logo.png`

## Bootstrap

```powershell
irm https://raw.githubusercontent.com/rbznet/RBZTechSolutions/main/bootstrap.ps1 | iex
```

## Local test

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\RBZHealth.ps1
```

## Release

```powershell
.\build-release.ps1

gh release create v0.3.0 `
  ".\dist\RBZ-PC-Health-0.3.0.zip" `
  ".\dist\RBZ-PC-Health-0.3.0.sha256" `
  --repo rbznet/RBZTechSolutions `
  --title "RBZ PC Health v0.3.0" `
  --notes "First service-ready release with guided low-risk remediation and customer/technician reporting."
```
