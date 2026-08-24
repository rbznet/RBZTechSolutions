# RBZ PC Health v0.2.5

Windows Time false-positive fix.

## v0.2.5 changes

- Windows Time no longer treats `W32Time = Stopped` as a fault by itself.
- Checks Windows Time configuration before assigning severity.
- Reads:
  - W32Time service state/start type
  - Windows Time provider type
  - configured NTP server
  - NTP client enabled state
  - special poll interval
  - `SynchronizeTime` scheduled task state
  - `ForceSynchronizeTime` scheduled task state
- Only runs `w32tm /query` when W32Time is actually running.
- Avoids displaying `0x80070426` as the time source when the service is stopped.

### Status model

- `Healthy` - service running and synchronized.
- `Info` - service stopped but time synchronisation is correctly configured.
- `Recommend` - service disabled or provider/NTP configuration is incomplete.
- `Warning` - service running but explicitly reports an unsynchronised state.

v0.2.5 remains scan-only.

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

gh release create v0.2.5 `
  ".\dist\RBZ-PC-Health-0.2.5.zip" `
  ".\dist\RBZ-PC-Health-0.2.5.sha256" `
  --repo rbznet/RBZTechSolutions `
  --title "RBZ PC Health v0.2.5" `
  --notes "Improve Windows Time diagnostics and remove stopped-service false positives."
```
