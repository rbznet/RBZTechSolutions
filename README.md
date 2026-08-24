# RBZ PC Health v0.5.0

Controlled repair release.

## Design

v0.5.0 expands the Repair Centre without changing the diagnostic, reporting, or before/after engine.

All repair actions still:
- require a completed scan before the Repair Centre is enabled
- require explicit technician selection
- are shown with a risk level
- require confirmation before execution
- are logged into the service history
- can be verified by running another full scan
- appear in reports through the existing service-action log

## Low-risk actions

- Create System Restore point
- Update Microsoft Defender security intelligence
- Microsoft Defender Quick Scan
- DISM ScanHealth
- SFC VerifyOnly
- CHKDSK `/scan` on the Windows system drive
- Windows Time resynchronisation
- Temporary-file cleanup

## Medium-risk actions

- DISM RestoreHealth
- SFC `/scannow`

When a Medium-risk action is selected, RBZ PC Health attempts to create a restore point first when configured.

By default a restore-point failure is recorded but does **not** block the repair, because many valid Windows installations have System Protection disabled. Change:

```json
"blockMediumActionIfRestorePointFails": false
```

to `true` if you want a stricter service policy.

## Windows Time safety

The time action does not rewrite NTP/domain configuration.

It:
1. checks that W32Time is not Disabled
2. starts W32Time if necessary
3. requests `/resync /rediscover`
4. records source and status

If W32Time is Disabled, the action stops and reports the condition instead of altering the service configuration.

## Not included

v0.5.0 still does not automatically:
- reset Winsock/TCP-IP
- delete Windows Update databases
- install Windows Updates
- install/remove drivers
- change Secure Boot
- enable/disable BitLocker
- remove applications
- clean the registry
- debloat Windows
- modify BIOS/firmware
- change Disabled Windows services

Those need stronger rollback/testing before being exposed in a customer-service tool.

## Local test

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\RBZHealth.ps1
```

Suggested first test:
1. Run Full Scan.
2. Set/confirm the baseline.
3. Test **Create system restore point**.
4. Test **CHKDSK /scan**.
5. Test **Defender security intelligence update**.
6. Test **Windows Time resynchronisation**.
7. Test DISM RestoreHealth and SFC /scannow separately.
8. Run Full Scan again.
9. Review Before / After.
10. Generate Customer and Technician reports.

## Release

```powershell
.\build-release.ps1

gh release create v0.5.0 `
  ".\dist\RBZ-PC-Health-0.5.0.zip" `
  ".\dist\RBZ-PC-Health-0.5.0.sha256" `
  --repo rbznet/RBZTechSolutions `
  --title "RBZ PC Health v0.5.0" `
  --notes "Add controlled repair actions with restore-point protection."
```

Bootstrap:

```powershell
irm https://raw.githubusercontent.com/rbznet/RBZTechSolutions/main/bootstrap.ps1 | iex
```
