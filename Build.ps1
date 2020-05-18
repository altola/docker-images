[CmdletBinding(SupportsShouldProcess = $true)]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "SitecorePassword")]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "RegistryPassword")]

param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$InstallSourcePath,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SitecoreUsername,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SitecorePassword,
    [Parameter(Mandatory=$True)]
    [string]$Registry = "",
    [Parameter()]
    [string]$RegistryUserName = "",
    [Parameter()]
    [string]$RegistryPassword = "",
    [Parameter()]
    [string]$AzureBlobStorageCacheAccountName = "",
    [Parameter()]
    [string]$AzureBlobStorageCacheAccountKey = "",
    [Parameter()]
    [string]$AzureBlobStorageCacheContainerName = "",
    [Parameter()]
    [ValidateSet("9.3.0", "9.2.0", "9.1.1", "9.0.2")]
    [string[]]$SitecoreVersion = @("9.3.0"),
    [ValidateSet("xm", "xp")]
    [string[]]$Topology = @("xm", "xp"),
    [ValidateSet("1909", "1903", "ltsc2019")]
    [string[]]$OSVersion = @("ltsc2019"),
    [Parameter()]
    [switch]$IncludeSpe,
    [Parameter()]
    [switch]$IncludeSxa,
    [Parameter()]
    [switch]$IncludeJss,
    [Parameter()]
    [switch]$IncludeExperimental
)

Write-Host "Azure CLI info:"
az --version

function Write-Message
{
    param(
        [string]$Message
    )

    $timeFormat = "HH:mm:ss:fff"

    Write-Host "$(Get-Date -Format $timeFormat): $($Message)"
}

if ([string]::IsNullOrEmpty($InstallSourcePath))
{
    $InstallSourcePath = (Join-Path -Path $PSScriptRoot -ChildPath "\packages")
}

$ErrorActionPreference = "STOP"
$ProgressPreference = "SilentlyContinue"

# load module
Import-Module (Join-Path $PSScriptRoot "\modules\SitecoreImageBuilder") -RequiredVersion 1.0.0 -Force

$tags = [System.Collections.ArrayList]@()

$windowsVersionMapping = @{
    "1909"     = "1909"
    "1903"     = "1903"
    "ltsc2019" = "1809"
}

filter WindowsFilter
{
    param([string]$Version)
    if ($_ -like "*-windowsservercore-$($Version)" -or $_ -like "*-nanoserver-$($windowsVersionMapping[$Version])")
    {
        $_
    }
}

filter SitecoreFilter
{
    param([string]$Version)
    if ($_ -like "*:$($Version)-windowsservercore-*" -or $_ -like "*:$($Version)-nanoserver-*")
    {
        $_
    }
}

$rootFolder = "windows"

$availableSpecs = Get-BuildSpecifications -Path (Join-Path $PSScriptRoot $rootFolder)

if (!$IncludeExperimental)
{
    Write-Message "Excluding experimental images."
    $availableSpecs = $availableSpecs | Where-Object { !$_.Experimental }
}

$availableTags = $availableSpecs | Select-Object -ExpandProperty Tag
$defaultTags = $availableTags | Where-Object { $_ -like "mssql-developer:*" -or $_ -like "sitecore-openjdk:*" }
$xpMiscTags = $availableTags | Where-Object { $_ -like "sitecore-certificates:*" }
$xcMiscTags = $availableTags | Where-Object { $_ -like "sitecore-certificates:*" -or $_ -like "sitecore-redis:*" }

$assetTags = $availableTags | Where-Object { $_ -like "sitecore-assets:*" }
$xmTags = $availableTags | Where-Object { $_ -match "sitecore-xm-(?!sxa|spe|jss).*:.*" }
$xpTags = $availableTags | Where-Object { $_ -match "sitecore-xp-(?!sxa|spe|jss).*:.*" }

$xmSpeTags = $availableTags | Where-Object { $_ -match "sitecore-xm-(spe).*:.*" }
$xmSxaTags = $availableTags | Where-Object { $_ -match "sitecore-xm-(sxa).*:.*" }
$xmJssTags = $availableTags | Where-Object { $_ -match "sitecore-xm-(jss).*:.*" }

$xpSpeTags = $availableTags | Where-Object { $_ -match "sitecore-xp-(spe).*:.*" }
$xpSxaTags = $availableTags | Where-Object { $_ -match "sitecore-xp-(sxa).*:.*" }
$xpJssTags = $availableTags | Where-Object { $_ -match "sitecore-xp-(jss).*:.*" }

$knownTags = $defaultTags + $xpMiscTags + $xcMiscTags + $assetTags + $xmTags + $xpTags + $xmSpeTags + $xpSpeTags + $xmSxaTags + $xpSxaTags + $xmJssTags + $xpJssTags
# These tags are not yet classified and no dependency check is made at this point to know which image it belongs to.
$catchAllTags = [System.Linq.Enumerable]::Except([string[]]$availableTags, [string[]]$knownTags)

foreach ($wv in $OSVersion)
{
    $defaultTags | WindowsFilter -Version $wv | ForEach-Object { $tags.Add($_) > $null }

    if ($Topology -contains "xp")
    {
        $xpMiscTags | WindowsFilter -Version $wv | ForEach-Object { $tags.Add($_) > $null }
    }

    foreach ($scv in $SitecoreVersion)
    {
        $assetTags | SitecoreFilter -Version $scv | WindowsFilter -Version $wv | ForEach-Object { $tags.Add($_) > $null }
        $catchAllTags | SitecoreFilter -Version $scv | WindowsFilter -Version $wv | ForEach-Object { $tags.Add($_) > $null }

        if ($Topology -contains "xm")
        {
            $xmTags | SitecoreFilter -Version $scv | WindowsFilter -Version $wv | ForEach-Object { $tags.Add($_) > $null }
        }

        if ($Topology -contains "xp")
        {
            $xpTags | SitecoreFilter -Version $scv | WindowsFilter -Version $wv | ForEach-Object { $tags.Add($_) > $null }
        }

        if ($IncludeSpe)
        {
            if ($Topology -contains "xm")
            {
                $xmSpeTags | SitecoreFilter -Version $scv | WindowsFilter -Version $wv | ForEach-Object { $tags.Add($_) > $null }
            }

            if ($Topology -contains "xp")
            {
                $xpSpeTags | SitecoreFilter -Version $scv | WindowsFilter -Version $wv | ForEach-Object { $tags.Add($_) > $null }
            }
        }

        if ($IncludeSxa)
        {
            if ($Topology -contains "xm")
            {
                $xmSxaTags | SitecoreFilter -Version $scv | WindowsFilter -Version $wv | ForEach-Object { $tags.Add($_) > $null }
            }

            if ($Topology -contains "xp")
            {
                $xpSxaTags | SitecoreFilter -Version $scv | WindowsFilter -Version $wv | ForEach-Object { $tags.Add($_) > $null }
            }
        }

        if ($IncludeJss)
        {
            if ($Topology -contains "xm")
            {
                $xmJssTags | SitecoreFilter -Version $scv | WindowsFilter -Version $wv | ForEach-Object { $tags.Add($_) > $null }
            }

            if ($Topology -contains "xp")
            {
                $xpJssTags | SitecoreFilter -Version $scv | WindowsFilter -Version $wv | ForEach-Object { $tags.Add($_) > $null }
            }
        }
    }
}

$tags = [System.Collections.ArrayList]@($tags | Select-Object -Unique)

if ($tags)
{
    Write-Message "The following images will be built:"
    $tags
}
else
{
    Write-Message "No images need to be built."
    exit
}


# restore any missing packages
SitecoreImageBuilder\Invoke-PackageRestore `
    -Path (Join-Path $PSScriptRoot $rootFolder) `
    -Destination $InstallSourcePath `
    -SitecoreUsername $SitecoreUsername `
    -SitecorePassword $SitecorePassword `
    -Tags $tags `
    -AzureBlobStorageCacheAccountName $(AzureBlobStorageCacheAccountName) `
    -AzureBlobStorageCacheAccountKey $(AzureBlobStorageCacheAccountKey) `
    -AzureBlobStorageCacheContainerName $(AzureBlobStorageCacheContainerName) `
    -ExperimentalTagBehavior:(@{$true = "Include"; $false = "Skip" }[$IncludeExperimental -eq $true]) `
    -WhatIf:$WhatIfPreference

# start the build
SitecoreImageBuilder\Invoke-Build `
    -Path (Join-Path $PSScriptRoot $rootFolder) `
    -InstallSourcePath $InstallSourcePath `
    -Registry $Registry `
    -Tags $tags `
    -ExperimentalTagBehavior:(@{$true = "Include"; $false = "Skip" }[$IncludeExperimental -eq $true]) `
    -WhatIf:$WhatIfPreference
