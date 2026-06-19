param(
  [string] $OutDir = "dist",
  [string] $ManifestPath = "",
  [int] $StoreLinkMaxAttempts = 12,
  [int] $StoreLinkRetryDelaySeconds = 30
)

$ErrorActionPreference = "Stop"

if ($StoreLinkMaxAttempts -lt 1) {
  throw "StoreLinkMaxAttempts must be at least 1."
}

if ($StoreLinkRetryDelaySeconds -lt 0) {
  throw "StoreLinkRetryDelaySeconds must be non-negative."
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

dotnet --info

$expectedPackageMoniker = $null
$expectedContentLength = $null

if ($ManifestPath) {
  if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "Probe manifest not found: $ManifestPath"
  }

  $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
  $expectedPackageMoniker = $manifest.sources.windows.packageMoniker
  $expectedContentLength = [int64] $manifest.sources.windows.contentLength

  if (-not $expectedPackageMoniker) {
    throw "Probe manifest is missing sources.windows.packageMoniker"
  }
}

function Resolve-StorePackageLink {
  param(
    [string] $ExpectedPackageMoniker
  )

  $lastError = "No Microsoft Store package link was resolved."

  for ($attempt = 1; $attempt -le $StoreLinkMaxAttempts; $attempt++) {
    Write-Host "Resolving Microsoft Store package link (attempt $attempt/$StoreLinkMaxAttempts)"

    $resolverOutput = & dotnet run --project scripts/store-link -- 9PLM9XGG6VKS x64
    if ($LASTEXITCODE -ne 0) {
      $lastError = "Microsoft Store resolver failed with exit code $LASTEXITCODE."
    } else {
      $linkLine = $resolverOutput |
        Where-Object { $_ -match "^OpenAI\.Codex_" } |
        Select-Object -First 1

      if (-not $linkLine) {
        $lastError = "No Microsoft Store package link was resolved."
      } else {
        $parts = $linkLine -split "`t", 2
        if ($parts.Count -lt 2 -or -not $parts[1]) {
          $lastError = "Microsoft Store package link is malformed: $linkLine"
        } else {
          $packageMoniker = $parts[0]
          $downloadUrl = $parts[1]

          if ($ExpectedPackageMoniker -and $packageMoniker -ne $ExpectedPackageMoniker) {
            $lastError = "Microsoft Store package changed after probe. Expected $ExpectedPackageMoniker, got $packageMoniker."
          } else {
            return [pscustomobject]@{
              PackageMoniker = $packageMoniker
              DownloadUrl = $downloadUrl
            }
          }
        }
      }
    }

    if ($attempt -lt $StoreLinkMaxAttempts) {
      Write-Warning "$lastError Retrying in $StoreLinkRetryDelaySeconds seconds."
      if ($StoreLinkRetryDelaySeconds -gt 0) {
        Start-Sleep -Seconds $StoreLinkRetryDelaySeconds
      }
    }
  }

  throw $lastError
}

$resolvedPackage = Resolve-StorePackageLink -ExpectedPackageMoniker $expectedPackageMoniker
$packageMoniker = $resolvedPackage.PackageMoniker
$downloadUrl = $resolvedPackage.DownloadUrl

$target = Join-Path $OutDir "$packageMoniker.Msix"

Write-Host "Downloading $packageMoniker"
Write-Host "Resolved Microsoft CDN URL: $downloadUrl"

Invoke-WebRequest `
  -Uri $downloadUrl `
  -OutFile $target `
  -MaximumRedirection 5

if ($expectedContentLength -gt 0) {
  $actualLength = (Get-Item -LiteralPath $target).Length
  if ($actualLength -ne $expectedContentLength) {
    throw "Downloaded size mismatch for $target. Expected $expectedContentLength bytes, got $actualLength bytes."
  }
}

Get-FileHash -Algorithm SHA256 -Path $target |
  ForEach-Object { "$($_.Hash.ToLowerInvariant())  $(Split-Path -Leaf $_.Path)" } |
  Set-Content -Encoding ascii -Path (Join-Path $OutDir "SHA256SUMS-windows.txt")
