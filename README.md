# RBZ PC Health v0.5.1

Repair progress and verification integration release.

## Live Repair Progress

Long-running Repair Centre actions now execute in a background PowerShell job so the WPF window remains responsive.

The Repair Centre shows:

- current action/stage
- determinate progress percentage when DISM/SFC/CHKDSK expose one
- an indeterminate activity bar when no reliable percentage is available
- elapsed time
- final action result

`Run Selected Actions` and `Run Full Scan` are disabled while a service action is actively running.

## DISM Verification

`DISM /RestoreHealth` now:

1. shows live activity/progress
2. records the complete DISM result
3. optionally runs `DISM /CheckHealth` after a successful repair
4. parses the verification result into:
   - Healthy
   - Recommend
   - Warning
   - Info

The parsed result is exposed as **Windows Component Store** in repair verification.

## SFC Verification

SFC output is parsed for common Windows Resource Protection outcomes:

- No integrity violations → Healthy
- Corrupt files repaired successfully → Healthy
- Corruption not fully repaired → Warning
- Requested operation could not be performed → Warning
- Unrecognised successful output → Info

The result is exposed as **Protected System Files**.

## Before / After Integration

Repair verification rows now appear directly in the **Before / After** tab with:

`Change = Verified`

Examples:

- Windows Component Store | Service action → Healthy
- Protected System Files | Service action → Healthy
- Windows Time synchronisation | Service action → Healthy
- Defender security intelligence | Service action → Healthy

These verification rows complement the normal baseline/current diagnostic comparison. They do not alter the health score by themselves.

A normal **Run Full Scan** after repair is still recommended because it validates the broader machine state.

## Reports

Customer and Technician reports now include a dedicated **Repair Verification** section when service actions returned verification results.

The existing:
- Before / After section
- Service Actions Performed
- diagnostic findings
- technician scoring explanation

remain unchanged.

## Install

Replace/add:

- `Config\settings.json`
- `Modules\Service.psm1`
- `Modules\Report.psm1`
- `RBZHealth.ps1`
- `README.md`

Keep all other v0.5.0/v0.4.0 modules unchanged.

## Local test

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\RBZHealth.ps1
```

Recommended test:

1. Run Full Scan.
2. Run DISM RestoreHealth by itself.
3. Confirm the Repair Centre remains responsive.
4. Confirm elapsed time increases.
5. Confirm the bar becomes determinate if DISM percentage output is detected.
6. Confirm Windows Component Store appears as Verified in Before / After.
7. Run SFC `/scannow`.
8. Confirm Protected System Files appears as Verified.
9. Run Full Scan again.
10. Generate Customer and Technician reports and confirm Repair Verification appears.

## Release

```powershell
.\build-release.ps1

gh release create v0.5.1 `
  ".\dist\RBZ-PC-Health-0.5.1.zip" `
  ".\dist\RBZ-PC-Health-0.5.1.sha256" `
  --repo rbznet/RBZTechSolutions `
  --title "RBZ PC Health v0.5.1" `
  --notes "Add live repair progress and DISM/SFC verification integration."
```

Bootstrap:

```powershell
irm https://raw.githubusercontent.com/rbznet/RBZTechSolutions/main/bootstrap.ps1 | iex
```

## Final v0.5.1 System Protection preflight

Medium-risk repairs now check System Protection before execution.

If protection is disabled, RBZ PC Health offers three explicit choices:

- **Enable System Protection** — enables protection for the Windows system drive, configures restore storage using `systemProtectionAllocationPercent`, creates a restore point, and verifies that a new matching restore point actually exists.
- **Continue Without Restore Point** — requires a second confirmation and logs that rollback protection was skipped by the technician.
- **Cancel Repair** — no repair is run.

Default allocation:

```json
"systemProtectionAllocationPercent": 5
```

RBZ PC Health does not silently enable System Protection. `Checkpoint-Computer` returning without an error is no longer treated as enough evidence: when verification is enabled, a newly created matching restore point must be found.


## RC3 restore-point logic correction

The System Protection/VSS state is no longer used to decide whether a Medium-risk repair can proceed.

The workflow is now:

1. Capture existing restore-point sequence numbers.
2. Run `Checkpoint-Computer`.
3. Read restore points again.
4. Verify that a new restore point with the requested RBZ description exists.
5. If verified, proceed directly with the repair.
6. If creation or verification fails, offer:
   - Enable Protection & Retry
   - Continue Without Restore Point
   - Cancel Repair

This avoids false disabled-state detection on systems where VSS/shadow-storage state does not accurately reflect System Restore capability.


## RC4 correction

Removed the `Get-Command Checkpoint-Computer` availability pre-check.

RBZ PC Health now directly attempts:

```powershell
Checkpoint-Computer
```

inside the repair workflow and treats the actual command result as authoritative.

The workflow is now:

1. Capture existing restore-point sequence numbers.
2. Attempt `Checkpoint-Computer`.
3. Read restore points again.
4. Verify a new matching RBZ restore point exists.
5. Proceed with the Medium-risk repair only when verified.
6. If the actual creation/verification fails, offer retry/enable, skip, or cancel.

This avoids false failures caused by command discovery behaving differently inside the application execution context.


## RC5 restore-point isolation

Restore-point creation now runs in a clean Windows PowerShell child process:

```text
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass
```

This isolates `Checkpoint-Computer` from module/autoload corruption in the main RBZ PC Health process.

Success is still determined only by verification:

1. Read existing restore-point sequence numbers.
2. Launch clean child Windows PowerShell and run `Checkpoint-Computer`.
3. Read restore points again.
4. Confirm that a new matching RBZ restore point exists.

The customer-facing dialog now shows a concise failure summary; detailed child-process output remains available for technician troubleshooting.


## RC7 runtime correction

RBZ PC Health now standardises on **Windows PowerShell 5.1** for the application runtime.

If `RBZHealth.ps1` is launched from PowerShell 7 / `pwsh`, it immediately relaunches itself using:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
```

before importing RBZ modules or Windows-native management modules.

This avoids PowerShell 7 Windows-Compatibility proxy modules such as `remoteIpMoProxy_*`, which caused Defender/System Restore cmdlets to become unreliable after the temporary compatibility module was removed.

Restore-point creation is therefore simplified back to the native same-process workflow:

1. Capture existing restore-point sequence numbers.
2. Run `Checkpoint-Computer`.
3. Read restore points again using `Get-ComputerRestorePoint`.
4. Verify a new matching RBZ restore point exists.
5. Continue with DISM/SFC only after successful verification, unless the technician explicitly chooses to continue without one.

PowerShell 7 remains suitable for launching the script; RBZ handles the runtime hand-off automatically.


## v0.5.2 Full Scan progress

Run Full Scan now displays real module-level progress across:
System, Storage, Security, Network, Devices, Battery, Startup and Updates.

The footer shows:
- current module/stage
- completed module count
- percentage complete
- elapsed time

The WPF dispatcher is updated between modules so the interface remains responsive.
Repair logic is unchanged from v0.5.1.
