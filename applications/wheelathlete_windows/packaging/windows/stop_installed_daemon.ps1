param(
    [Parameter(Mandatory = $true)]
    [string]$InstallRoot,
    [int]$Port = 8765
)

$ErrorActionPreference = "Stop"
$root = [IO.Path]::GetFullPath($InstallRoot).TrimEnd("\") + "\"
$processes = @(
    Get-CimInstance Win32_Process -Filter "Name='WheelAthleteDaemon.exe'" |
        Where-Object {
            $_.ExecutablePath -and
            [IO.Path]::GetFullPath($_.ExecutablePath).StartsWith(
                $root,
                [StringComparison]::OrdinalIgnoreCase
            )
        }
)

if ($processes.Count -eq 0) {
    exit 0
}

function Read-Response {
    param($Reader, [string]$RequestId)
    while ($true) {
        $line = $Reader.ReadLine()
        if ($null -eq $line) {
            throw "WheelAthlete daemon closed the IPC connection before responding."
        }
        $message = $line | ConvertFrom-Json
        if ($message.request_id -ne $RequestId) {
            continue
        }
        if ($message.type -eq "error") {
            throw [string]$message.payload.message
        }
        if ($message.type -in @("hello_ack", "response")) {
            return $message.payload.result
        }
    }
}

function Send-Command {
    param($Writer, $Reader, [string]$Type)
    $requestId = [Guid]::NewGuid().ToString("N")
    $request = @{
        protocol_version = 1
        type = $Type
        payload = @{}
        request_id = $requestId
    } | ConvertTo-Json -Compress
    $Writer.WriteLine($request)
    $Writer.Flush()
    return Read-Response $Reader $requestId
}

$client = [Net.Sockets.TcpClient]::new()
try {
    $client.Connect("127.0.0.1", $Port)
    $stream = $client.GetStream()
    $stream.ReadTimeout = 5000
    $stream.WriteTimeout = 5000
    $reader = [IO.StreamReader]::new($stream)
    $writer = [IO.StreamWriter]::new($stream)
    $writer.NewLine = "`n"
    $helloId = [Guid]::NewGuid().ToString("N")
    $writer.WriteLine((@{
        protocol_version = 1
        type = "hello"
        payload = @{}
        request_id = $helloId
    } | ConvertTo-Json -Compress))
    $writer.Flush()
    $null = Read-Response $reader $helloId

    $supportsShutdown = $false
    try {
        $null = Send-Command $writer $reader "shutdown"
        $supportsShutdown = $true
    }
    catch {
        # 1.8.1 and older have no shutdown command. Finalize through their
        # existing IPC before terminating only the path-verified process.
        $status = Send-Command $writer $reader "status"
        if ($status.recording_starting) {
            throw "Recording startup is still in progress. Wait for it to start or cancel it before uninstalling."
        }
        if ($status.recording) {
            $null = Send-Command $writer $reader "end_record"
        }
        if ($status.live) {
            $null = Send-Command $writer $reader "stop_live"
        }
    }
    $writer.Dispose()
    $reader.Dispose()
    $stream.Dispose()
    $client.Dispose()

    if (-not $supportsShutdown) {
        foreach ($process in $processes) {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
        }
    }
}
catch {
    $client.Dispose()
    Write-Error (
        "Could not stop the installed WheelAthlete acquisition daemon safely. " +
        $_.Exception.Message
    )
    exit 1
}

$deadline = [DateTime]::UtcNow.AddSeconds(12)
do {
    $remaining = @(
        foreach ($process in $processes) {
            Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
        }
    )
    if ($remaining.Count -eq 0) {
        exit 0
    }
    Start-Sleep -Milliseconds 200
} while ([DateTime]::UtcNow -lt $deadline)

Write-Error "The installed WheelAthlete daemon did not exit. Close WheelAthlete and retry."
exit 1
