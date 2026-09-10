[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDir,
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [switch]$RequireValidSignatures
)

$ErrorActionPreference = "Stop"
$release = (Resolve-Path -LiteralPath $ReleaseDir).Path
$executables = @(
    "WheelAthlete\WheelAthlete.exe",
    "WheelAthlete\_internal\WheelAthleteDaemon.exe",
    "WheelAthleteSetup-$Version.exe"
)
$artifacts = @(
    foreach ($relative in $executables) {
        $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $release $relative)
        [ordered]@{
            path = $relative
            status = [string]$signature.Status
            signer = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { $null }
        }
    }
)
$ready = @($artifacts | Where-Object { $_.status -ne "Valid" }).Count -eq 0
$report = [ordered]@{
    schema_version = 1
    public_release_ready = $ready
    artifacts = $artifacts
} | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText(
    (Join-Path $release "signing-report.json"),
    $report + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false)
)

$releaseFiles = @(
    "WheelAthleteSetup-$Version.exe",
    "WheelAthlete-$Version-portable.zip"
)
$checksumLines = @(
    foreach ($name in $releaseFiles) {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $release $name)).Hash.ToLowerInvariant()
        "$hash *$name"
    }
)
[IO.File]::WriteAllLines(
    (Join-Path $release "SHA256SUMS.txt"),
    $checksumLines,
    [Text.Encoding]::ASCII
)

$installer = Join-Path $release "WheelAthleteSetup-$Version.exe"
$installerHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $installer).Hash.ToLowerInvariant()
Write-Host "Installer SHA256: $installerHash"
Write-Host "Installer bytes:  $((Get-Item -LiteralPath $installer).Length)"
if ($RequireValidSignatures -and -not $ready) {
    throw "Public release requires valid signatures on the GUI, daemon, and installer."
}
