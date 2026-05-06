param(
  [string] $OutDir = "dist"
)

$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

winget --version
winget source update

winget download `
  --id 9PLM9XGG6VKS `
  --source msstore `
  --architecture x64 `
  --platform Windows.Desktop `
  --download-directory $OutDir `
  --accept-source-agreements `
  --accept-package-agreements `
  --skip-license `
  --disable-interactivity

$package = Get-ChildItem -Path $OutDir -Recurse -Include *.msix,*.msixbundle |
  Sort-Object Length -Descending |
  Select-Object -First 1

if (-not $package) {
  throw "No MSIX/MSIXBundle was downloaded."
}

$target = Join-Path $OutDir "Codex-windows-x64$($package.Extension)"
Move-Item -Force -Path $package.FullName -Destination $target

Get-FileHash -Algorithm SHA256 -Path $target |
  ForEach-Object { "$($_.Hash.ToLowerInvariant())  $(Split-Path -Leaf $_.Path)" } |
  Set-Content -Encoding ascii -Path (Join-Path $OutDir "SHA256SUMS-windows.txt")
