# RBZ PC Health v0.2.4

Focused network and Windows Time diagnostic update.

## v0.2.4 changes

- Corrected the Microsoft connectivity test to use the intended HTTP endpoint:
  `http://www.msftconnecttest.com/connecttest.txt`
- Validates the expected response: `Microsoft Connect Test`.
- HTTPS/TLS health is now checked separately against `www.microsoft.com`.
- TLS diagnostics use `SslStream` plus `X509Chain` instead of treating `Invoke-WebRequest` as the authority.
- TLS finding includes:
  - negotiated TLS protocol
  - certificate subject
  - issuer
  - validity dates
  - thumbprint
  - chain validity/status
  - SSL policy errors
  - Subject Alternative Names when available
- Added Windows Time synchronisation diagnostic.
- Detects:
  - stopped Windows Time service
  - Local CMOS Clock source
  - Leap Indicator "not synchronized"
  - missing/unspecified last successful sync
- v0.2.4 remains scan-only.

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

gh release create v0.2.4 `
  ".\dist\RBZ-PC-Health-0.2.4.zip" `
  ".\dist\RBZ-PC-Health-0.2.4.sha256" `
  --repo rbznet/RBZTechSolutions `
  --title "RBZ PC Health v0.2.4" `
  --notes "Correct network connectivity/TLS diagnostics and add Windows Time synchronisation checks."
```
