# RBZ PC Health v0.2.3

Polish and accuracy release.

## Changes
- Added INFO dashboard count.
- Attention findings sorted Critical, Warning, Recommend.
- GUI rows colour-coded by status.
- Added Copy Details button.
- HTTPS failures become Recommend when DNS and TCP 443 prove connectivity.
- Defender definition/intelligence updates are informational and do not count as actionable pending updates.
- Pending updates are classified as Definition, Quality, Feature, Driver, or Other.
- Secure Boot disabled is now Recommend rather than Warning.
- GUI version remains driven by Config/settings.json.

## Bootstrap
```powershell
irm https://raw.githubusercontent.com/rbznet/RBZTechSolutions/main/bootstrap.ps1 | iex
```

## Release
```powershell
.\build-release.ps1

gh release create v0.2.3 `
  ".\dist\RBZ-PC-Health-0.2.3.zip" `
  ".\dist\RBZ-PC-Health-0.2.3.sha256" `
  --repo rbznet/RBZTechSolutions `
  --title "RBZ PC Health v0.2.3" `
  --notes "v0.2.3 accuracy and GUI polish."
```
