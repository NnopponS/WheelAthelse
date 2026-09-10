[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDir,
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [string]$ExpectedSignerSubject,
    [switch]$RequireValidSignatures
)

$ErrorActionPreference = "Stop"
$release = (Resolve-Path -LiteralPath $ReleaseDir).Path
$releasePrefix = $release.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar

function Get-ReleaseRelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith($releasePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Artifact path is outside the release directory: $fullPath"
    }
    return $fullPath.Substring($releasePrefix.Length)
}

$firstParty = @(
    "WheelAthlete\WheelAthlete.exe",
    "WheelAthlete\_internal\WheelAthleteDaemon.exe",
    "WheelAthlete\stop_installed_daemon.ps1",
    "WheelAthleteSetup-$Version.exe"
)
$executables = @(
    Get-ChildItem -LiteralPath (Join-Path $release "WheelAthlete") -File -Recurse |
        Where-Object Extension -In @(".exe", ".dll", ".pyd", ".ps1") |
        ForEach-Object { Get-ReleaseRelativePath -Path $_.FullName }
    "WheelAthleteSetup-$Version.exe"
) | Sort-Object -Unique
$artifacts = @(
    foreach ($relative in $executables) {
        $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $release $relative)
        [ordered]@{
            path = $relative
            status = [string]$signature.Status
            signer = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { $null }
            timestamped = $null -ne $signature.TimestampCertificate
            first_party = $relative -in $firstParty
            expected_signer = ($relative -notin $firstParty) -or ($signature.SignerCertificate -and $signature.SignerCertificate.Subject -ceq $ExpectedSignerSubject)
        }
    }
)
$ready = @($artifacts | Where-Object {
    $_.status -ne "Valid" -or -not $_.timestamped -or -not $_.expected_signer
}).Count -eq 0
$report = [ordered]@{
    schema_version = 2
    public_release_ready = $ready
    is_signed = $ready
    executable_count = $artifacts.Count
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
$allowUnsigned = ($env:ALLOW_UNSIGNED_RELEASE -eq "true")
if ($RequireValidSignatures -and -not $allowUnsigned) {
    if (-not $ExpectedSignerSubject) {
        throw "ExpectedSignerSubject is required for public release verification."
    }
    if (-not $ready) {
        throw "Public release requires valid timestamped signatures on every executable component and the expected signer on first-party files."
    }
}
