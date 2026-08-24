# RBZ PC Health v0.4.0

Before/after service comparison release.

## v0.4.0

- Session scan history (up to 10 scans by default).
- First scan automatically becomes the baseline.
- New **Before / After** tab.
- Baseline score, current score, and score change.
- Finding changes classified as Improved, Worsened, New, Removed, or Updated.
- **Set Current as Baseline** control.
- **Clear Session History** control.
- Customer and Technician reports include Before / After when comparison data exists.
- Existing low-risk Repair Centre actions are unchanged from v0.3.1.
- Session history stays in memory only; nothing is uploaded.

## Suggested test

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\RBZHealth.ps1
```

1. Run Full Scan. Baseline and Current should match.
2. Run a safe Repair Centre action.
3. Run Full Scan again.
4. Check score delta and changed findings.
5. Generate both report types and confirm Before / After appears.
6. Test Set Current as Baseline and Clear Session History.

## Release

```powershell
.\build-release.ps1

gh release create v0.4.0 `
  ".\dist\RBZ-PC-Health-0.4.0.zip" `
  ".\dist\RBZ-PC-Health-0.4.0.sha256" `
  --repo rbznet/RBZTechSolutions `
  --title "RBZ PC Health v0.4.0" `
  --notes "Add session scan history and before/after service comparison."
```

Bootstrap:

```powershell
irm https://raw.githubusercontent.com/rbznet/RBZTechSolutions/main/bootstrap.ps1 | iex
```
