param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [Parameter(Mandatory = $true)]
    [string]$CertificateThumbprint,
    [Parameter(Mandatory = $true)]
    [string]$TimestampUrl,
    [Parameter(Mandatory = $true)]
    [string]$ExpectedSubject
)

$ErrorActionPreference = "Stop"
$rootPath = (Resolve-Path -LiteralPath $Root).Path
$signer = Join-Path $PSScriptRoot "sign_windows_artifact.ps1"
$artifacts = @(
    Get-ChildItem -LiteralPath $rootPath -File -Recurse |
        Where-Object Extension -In @(".exe", ".dll", ".pyd", ".ps1") |
        Sort-Object FullName
)
if ($artifacts.Count -eq 0) {
    throw "No executable artifacts were found under $rootPath"
}
foreach ($artifact in $artifacts) {
    & $signer -Path $artifact.FullName -CertificateThumbprint $CertificateThumbprint `
        -TimestampUrl $TimestampUrl -ExpectedSubject $ExpectedSubject
}
Write-Host "Signed and verified $($artifacts.Count) executable artifacts under $rootPath"
