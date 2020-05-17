param(
    [Parameter(Mandatory=$True)]
    [string]
    $File
)

$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';

$Dir = [System.IO.Path]::GetDirectoryName($File);
$File = [System.IO.Path]::GetFileName($File);
$File = ".\$File";

Push-Location $Dir
try
{
    docker-compose --file $File down
} finally {
    Pop-Location
}