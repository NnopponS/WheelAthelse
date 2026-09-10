param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [string]$CertificateThumbprint,
    [Parameter(Mandatory = $true)]
    [string]$TimestampUrl,
    [Parameter(Mandatory = $true)]
    [string]$ExpectedSubject
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
$certificate = Get-Item -LiteralPath "Cert:\CurrentUser\My\$thumbprint" -ErrorAction Stop
if (-not $certificate.HasPrivateKey) {
    throw "Signing certificate does not have a private key."
}
if ($certificate.Subject -cne $ExpectedSubject) {
    throw "Signing certificate subject '$($certificate.Subject)' does not match '$ExpectedSubject'."
}
$now = Get-Date
if ($now -lt $certificate.NotBefore -or $now -gt $certificate.NotAfter) {
    throw "Signing certificate is not currently valid."
}
$codeSigningEku = @(
    $certificate.Extensions |
        Where-Object { $_.Oid.Value -eq "2.5.29.37" } |
        ForEach-Object EnhancedKeyUsages |
        ForEach-Object Value
)
if ($codeSigningEku -notcontains "1.3.6.1.5.5.7.3.3") {
    throw "Signing certificate does not permit code signing."
}
$rsa = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($certificate)
if (-not $rsa) {
    throw "Smart App Control requires an RSA code-signing certificate."
}
$rsa.Dispose()

if ([IO.Path]::GetExtension($artifact) -ieq ".ps1") {
    $signature = Set-AuthenticodeSignature -LiteralPath $artifact -Certificate $certificate `
        -HashAlgorithm SHA256 -TimestampServer $TimestampUrl
    if ($signature.Status -ne "Valid" -or -not $signature.TimestampCertificate) {
        throw "PowerShell could not create a valid timestamped signature for $artifact"
    }
    return
}

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

$existing = Get-AuthenticodeSignature -LiteralPath $artifact
if ($existing.Status -notin @("NotSigned", "Valid")) {
    throw "Refusing to replace $($existing.Status) signature on $artifact"
}
$append = if ($existing.Status -eq "Valid") { "/as" } else { $null }
& $signTool sign $append /sha1 $thumbprint /fd SHA256 /tr $TimestampUrl /td SHA256 $artifact
if ($LASTEXITCODE -ne 0) {
    throw "SignTool failed to sign $artifact"
}
& $signTool verify /pa /all $artifact
if ($LASTEXITCODE -ne 0) {
    throw "SignTool could not verify $artifact"
}
$signature = Get-AuthenticodeSignature -LiteralPath $artifact
if ($signature.Status -ne "Valid" -or -not $signature.TimestampCertificate) {
    throw "Authenticode did not report a valid timestamped signature for $artifact"
}
