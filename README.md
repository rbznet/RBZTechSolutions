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


## v0.6.0 — Theme, branding and repository housekeeping

### Light / Dark mode
The application header now includes a Light/Dark mode toggle.

The selected theme is persisted to:

`%LOCALAPPDATA%\RBZ PC Health\ui.json`

and restored on the next launch.

### Logo placeholder
The application header now contains an RBZ branding tile.

To replace the placeholder, add a PNG at:

`Assets\rbz-logo.png`

A transparent square or near-square image of at least 256x256 is recommended.

If the file is absent, the built-in `RBZ` text placeholder remains visible.

### Deploy notes
Historical deployment notes should now be stored under:

`Docs\Deploy\`

Run `Tools\Move-DeployNotes.ps1` once after extracting the v0.6.0 update to move existing root-level `DEPLOY-v0*.txt` files into that folder.

All future deploy notes should be created under `Docs\Deploy`.


### v0.6.0 RC2 dark-mode contrast fix
Dark mode now themes DataGrid headers/cells, tabs, buttons, text boxes, checkboxes and selection states through shared dynamic resources.


### v0.6.0 RC3 dark-mode cleanup

- Customer and Job ref labels now switch colour with the active theme.
- Selected tab headers use a theme-aware custom template instead of the default white WPF selected-tab style.
- Disabled buttons now use muted theme colours instead of Windows' light disabled-button appearance.


### v0.6.0 RC4 button-state fix

Buttons now use a full theme-aware WPF template. This fixes light disabled report buttons and light hover flashes in Dark mode. Normal, hover, pressed and disabled states now use RBZ theme resources.


### v0.6.0 RC5 DataGrid status-row contrast fix

DataGrid cells no longer force the global theme foreground colour.

Cells now inherit foreground from their parent row. This means:

- Healthy / Info / Recommend / Warning / Critical rows keep their pale status backgrounds with dark text.
- Ordinary dark-mode rows keep light text.
- Selected cells still use the theme selection colours.


### v0.6.0 RC6 Repair Centre layout fix

The Repair Centre now uses proportional vertical space instead of a cramped action list and fixed 160px log.

- Action list: `2*`
- Action log: `3*`
- Action list minimum height: 190px
- Action log minimum height: 180px

Both sections expand with the window and remain usable at smaller sizes.


### v0.6.0 RC7 window sizing and Repair Centre balance

The application now opens at a larger default size:

- Width: 1500
- Height: 940
- Minimum width: 1180
- Minimum height: 800

Repair Centre vertical allocation is also rebalanced:

- Action list: 3*
- Action log: 2*
- Action list minimum height: 260px
- Action log minimum height: 150px

This prioritises the action catalogue while still keeping live repair output visible.


### v0.6.0 RC9 XAML and Repair Centre fix

RC9 corrects two issues introduced during the scrollbar/layout patches:

- `ActionLogBox` XAML is rebuilt as a valid self-closing TextBox with explicit vertical and horizontal scrollbars.
- Repair Centre row proportions are corrected to:
  - Action list: `3*`
  - Action log: `2*`

The action catalogue therefore receives more space than the live log.


### v0.6.0 RC10 Repair Centre scrollbar fix

The Repair Centre action list now forces its vertical scrollbar to remain visible rather than relying on WPF's automatic scrollbar calculation.

`ActionGrid` now uses:
- `ScrollViewer.VerticalScrollBarVisibility="Visible"`
- `ScrollViewer.HorizontalScrollBarVisibility="Auto"`
- `ScrollViewer.CanContentScroll="True"`
- `ScrollViewer.IsDeferredScrollingEnabled="False"`

Other result grids retain automatic scrollbar behaviour.


### v0.6.0 RC11 Repair Centre functional scrolling

RC10 forced the scrollbar visible, but the action DataGrid was still being measured at effectively its full content height and then clipped by its parent. That produces a scrollbar which is visible but has no usable scroll extent.

RC11 fixes the layout itself:

- Repair action row is constrained to 320px.
- ActionGrid no longer has a competing MinHeight.
- Vertical scrollbar returns to Auto.
- The action log consumes the remaining vertical space.

This gives the DataGrid's internal ScrollViewer a genuine viewport, so wheel scrolling and scrollbar dragging work normally.


### v0.6.0 RC12 responsive Repair Centre

The fixed 320px action row from RC11 has been removed. Repair Centre now uses responsive proportional rows:

- Action list: `3*`
- Action log: `2*`

No fixed or minimum height is applied to either area, so the layout can shrink and grow with the application window while the DataGrid owns its own scrolling.


## v0.7.0 RC1 — Event Log + crash diagnostics

Full Scan now contains nine modules. The new `Modules\EventLog.psm1` adds targeted stability checks rather than treating every Event Viewer error as a fault.

New checks:
- Unexpected shutdowns / Kernel-Power history
- BSOD / BugCheck and recent minidump history
- WHEA hardware errors
- Targeted disk, NTFS and storage-controller event errors
- Repeated application crashes/hangs with thresholds to suppress isolated noise

The supplied RBZ Tech Solutions monochrome artwork is installed as `Assets\rbz-logo.png`; the header logo area has been widened to display the full mark.


### v0.7.0 RC2 — Event classification refinement

RC2 improves the first real-world Event Log classifications.

#### Storage
- Healthy NTFS Event ID 98 entries containing `is healthy` / `No action is needed` are ignored.
- Disk 7/51/153, storage reset 129, NTFS corruption-oriented events and non-benign NTFS 98 remain actionable.
- Storage findings now report **actionable** events rather than raw matching event count.

#### Application crashes
Crash/hang events are grouped by executable.

Default scoring:
- 3+ failures from the same app → Recommend
- 5+ failures from the same app → Warning
- 10+ total failures spread across unrelated apps → Recommend
- otherwise → Info

Details now show the top recurring applications plus common faulting module and exception code where available.


### v0.7.0 RC3 — cleaner crash diagnostics

Grouped application crash summaries now suppress placeholder metadata that does not help diagnosis:

- `module=unknown`
- empty/none/N/A modules
- `exception=0x00000000`
- equivalent empty/zero exception values

Raw Event Viewer examples remain unchanged underneath the grouped summary so technicians can still inspect the original event data.


### v0.7.0 RC4 — deeper disk health / reliability diagnostics

Storage diagnostics now query Windows Storage Reliability Counters when supported.

Possible telemetry includes:
- temperature / maximum temperature
- SSD/NVMe wear percentage used
- power-on hours
- corrected and uncorrected read/write errors
- latency maxima
- start/stop and load/unload cycles

Missing reliability data is `Info`, not `Healthy` or `Warning`. Physical-disk HealthStatus / OperationalStatus are still assessed separately.


### v0.7.0 RC5 — consolidated disk findings

Physical disk and Storage Reliability Counter results are now combined into a single finding per drive.

All Results therefore shows one row per physical disk rather than a second `Disk N reliability data` row.

The drive Details pane still contains:
- temperature / maximum temperature
- wear percentage used
- power-on hours
- read/write error counters
- latency maxima
- cycle counters
- firmware and serial details

If reliability counters are unavailable, the main disk finding explains that in Details/Recommendation without creating a duplicate row.
