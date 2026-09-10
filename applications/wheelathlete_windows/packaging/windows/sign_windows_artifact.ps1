param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [string]$CertificateThumbprint,
    [Parameter(Mandatory = $true)]
    [string]$TimestampUrl
)

$ErrorActionPreference = "Stop"
$thumbprint = ($CertificateThumbprint -replace "\s", "").ToUpperInvariant()
if ($thumbprint -notmatch "^[0-9A-F]{40}$") {
    throw "Certificate thumbprint must contain exactly 40 hexadecimal characters."
}
if (-not [Uri]::IsWellFormedUriString($TimestampUrl, [UriKind]::Absolute)) {
    throw "TimestampUrl must be an absolute URL."
}
$artifact = (Resolve-Path -LiteralPath $Path).Path
$signTool = (Get-Command signtool.exe -ErrorAction SilentlyContinue).Source
if (-not $signTool) {
    $kitRoot = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
    if (Test-Path -LiteralPath $kitRoot) {
        $signTool = Get-ChildItem -LiteralPath $kitRoot -Filter signtool.exe -Recurse |
            Where-Object FullName -Match "\\x64\\signtool.exe$" |
            Sort-Object FullName -Descending |
            Select-Object -First 1 -ExpandProperty FullName
    }
}
if (-not $signTool) {
    throw "signtool.exe was not found. Install the Windows SDK signing tools."
}

& $signTool sign /sha1 $thumbprint /fd SHA256 /tr $TimestampUrl /td SHA256 $artifact
if ($LASTEXITCODE -ne 0) {
    throw "SignTool failed to sign $artifact"
}
& $signTool verify /pa /all $artifact
if ($LASTEXITCODE -ne 0) {
    throw "SignTool could not verify $artifact"
}
