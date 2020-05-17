$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';

if ([string]::IsNullOrWhiteSpace($env:REGISTRY)) {
    Write-Error "No REGISTRY environment variable specified"

    exit -1;
}

if ([string]::IsNullOrWhiteSpace($env:SITECORE_LICENSE)) {
    Write-Error "No SITECORE_LICENSE environment variable specified"

    exit -1;
}

$sitecoreVersion = $env:SITECORE_VERSION;
if (-not [string]::IsNullOrWhiteSpace($sitecoreVersion)) {
    $sitecoreVersion = [int]::Parse($sitecoreVersion.Replace('.', ''))
} else {
    $sitecoreVersion = [int]::Parse((Get-Content .env | where-object { $_ -like 'SITECORE_VERSION=*' }).ToString().Substring("Sitecore_Version=".Length).Replace('.', ''))
}

return $sitecoreVersion