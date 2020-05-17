param(
    [Parameter(Mandatory=$True)]
    [string]
    $File,
    [Parameter(Mandatory=$false)]
    [Switch]
    $Detach
)

$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';

if (-not (Test-Path $File)) {
    Write-Error "The file does not exist: $File"

    exit -1;
}

$RootDir = "$(Get-Location)"
$Dir = [System.IO.Path]::GetDirectoryName($File);
$File = [System.IO.Path]::GetFileName($File);
$File = ".\$File";

Push-Location $Dir
try 
{
    $LASTEXITCODE = 0;
    $sitecoreVersion = (. $RootDir\_ParseSitecoreVersion.ps1)
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE;
    }
    
    $LASTEXITCODE = 0;
    . $RootDir\_Prepare.ps1 -SitecoreVersion $sitecoreVersion
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE;
    }

    Write-Host "Composing containers"
    if ($Detach) {
        docker-compose --file $File up --detach --quiet-pull;

        $KeepAliveTimeoutSec = 180

        $KeepAliveUrl= "http://localhost:44001/sitecore/service/keepalive.aspx"

        ## Enable TLS 1.2 to allow HTTPS communication
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        $OriginalTimeoutSec = $KeepAliveTimeoutSec
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew();
        while ($KeepAliveTimeoutSec -gt 0) {
            try {
                Write-Host "Requesting $KeepAliveUrl page"
                $code = (Invoke-WebRequest $KeepAliveUrl -TimeoutSec $KeepAliveTimeoutSec -UseBasicParsing).StatusCode
                if ($code -ne 200) {
                    Write-Error "Response status code is $code";                
                } else {
                    Write-Host "The service is up"
                    break;
                }
            } catch {
                Write-Warning "Request has failed: $_. It will be retried in 5s, $([Convert]::ToInt32($OriginalTimeoutSec - $stopwatch.Elapsed.TotalSeconds))s before timeout"
                [System.Threading.Thread]::Sleep(5000);
                $KeepAliveTimeoutSec = $OriginalTimeoutSec - $stopwatch.Elapsed.TotalSeconds
            }
        }
    } else {
        docker-compose --file $File up; 
    }
} finally {
    Pop-Location
}