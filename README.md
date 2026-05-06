# Codex App Mirror

Small GitHub Actions mirror for official OpenAI Codex desktop app installers.

This repository does not build or modify Codex. It downloads current official
installer packages and publishes them as GitHub Release assets.

## Assets

- Windows x64 MSIX from Microsoft Store product `9PLM9XGG6VKS`
- macOS Apple Silicon DMG from OpenAI's Codex desktop URL
- macOS Intel DMG from OpenAI's Codex desktop URL

## Run

Use the `Mirror Codex App Installers` workflow from the Actions tab.

The workflow creates a release tagged like:

```text
codex-app-YYYYMMDD-HHMMSS
```

## Sources

The macOS URLs are the same URLs used by the official `openai/codex` CLI
`codex app` installer implementation:

- `https://persistent.oaistatic.com/codex-app-prod/Codex.dmg`
- `https://persistent.oaistatic.com/codex-app-prod/Codex-latest-x64.dmg`

The Windows package is downloaded via `winget download` from the Microsoft Store
source using ProductId `9PLM9XGG6VKS`.

## Notes

Microsoft Store CDN URLs are temporary, so the workflow stores the downloaded
MSIX as a release asset instead of trying to preserve the original CDN URL.

`winget download --skip-license` skips only the Store offline license file. It
does not modify the MSIX package.
