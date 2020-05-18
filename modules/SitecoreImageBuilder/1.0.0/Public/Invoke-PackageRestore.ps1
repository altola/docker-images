function Invoke-PackageRestore
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "SitecorePassword")]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript( { Test-Path $_ -PathType "Container" })]
        [string]$Path
        ,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination
        ,
        [Parameter(Mandatory = $false)]
        [array]$Tags
        ,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Include", "Skip")]
        [string]$DeprecatedTagsBehavior = "Skip"
        ,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Include", "Skip")]
        [string]$ExperimentalTagBehavior = "Skip"
        ,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SitecoreUsername
        ,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SitecorePassword
        ,
        [Parameter(Mandatory = $true)]
        [string]$AzureBlobStorageCacheAccountName
        ,
        [Parameter(Mandatory = $true)]
        [string]$AzureBlobStorageCacheAccountKey
        ,
        [Parameter(Mandatory = $true)]
        [string]$AzureBlobStorageCacheContainerName
    )

    # Setup
    $ErrorActionPreference = "STOP"
    $ProgressPreference = "SilentlyContinue"

    $watch = [System.Diagnostics.StopWatch]::StartNew()

    $sitecoreDownloadUrl = "https://dev.sitecore.net"
    $destinationPath = $Destination.TrimEnd('\')

    # Load packages
    $packages = Get-Packages

    # Ensure destination exists
    if (!(Test-Path $destinationPath -PathType "Container"))
    {
        New-Item $destinationPath -ItemType Directory -WhatIf:$false | Out-Null
    }

    if ($AzureBlobStorageCacheAccountName -or $AzureBlobStorageCacheContainerName -or $AzureBlobStorageCacheAccountKey) {
        if ([string]::IsNullOrWhiteSpace($AzureBlobStorageCacheAccountName)) {
            Write-Error "AzureBlobStorageCacheAccountName is not specified"
            exit -1;
        }

        if ([string]::IsNullOrWhiteSpace($AzureBlobStorageCacheContainerName)) {
            Write-Error "AzureBlobStorageCacheContainerName is not specified"
            exit -1;
        }

        if ([string]::IsNullOrWhiteSpace($AzureBlobStorageCacheAccountKey)) {
            Write-Error "AzureBlobStorageCacheAccountKey is not specified"
            exit -1;
        }

        Push-Location $Destination
        try {
            Write-Host "Syncing folder with azure blob storage before we start downloading anything, folder: $Destination"
            Write-Host "npx sync-azure-blob@0.0.12 --container `"$AzureBlobStorageCacheContainerName`" --account-name `"$AzureBlobStorageCacheAccountName`" --account-key `"$AzureBlobStorageCacheAccountKey`""
            npx sync-azure-blob@0.0.12 --container "$AzureBlobStorageCacheContainerName" --account-name "$AzureBlobStorageCacheAccountName" --account-key "$AzureBlobStorageCacheAccountKey"
        }
        catch {
            Write-Information "Uploading to azure blob thrown the exception. $($_ | ConvertTo-Json)"
            $LASTEXITCODE = 0;
        }
        finally {
            Pop-Location
        }
    }

    $sitecoreDownloadSession = $null

    # Find out which files is needed
    $allSpecs = Get-BuildSpecifications -Path $Path

    if ($Tags -eq $null)
    {
        $Tags = Get-LatestSupportedVersionTags -Specs $allSpecs
    }

    $specs = Initialize-BuildSpecifications -Specifications $allSpecs -InstallSourcePath $Destination -Tags $Tags -ImplicitTagsBehavior "Include" -DeprecatedTagsBehavior $DeprecatedTagsBehavior -ExperimentalTagBehavior $ExperimentalTagBehavior
    $expected = $specs | Where-Object { $_.Include -and $_.Sources.Length -gt 0 } | Select-Object -ExpandProperty Sources -Unique

    $downloadedAtLeastOneFile = $false

    # Check or download needed files
    $expected | ForEach-Object {
        $filePath = $_

        if (Test-Path $filePath -PathType Leaf)
        {
            $requiredFile = Get-Item -Path $filePath

            if ($requiredFile.Length -gt 0)
            {
                Write-Message ("Required package found: '{0}'" -f $filePath) -Level Debug

                return
            }

            Remove-Item -Path $filePath -Force
        }

        $fileName = $filePath.Replace(("{0}\" -f $destinationPath), "")
        $package = $packages.$fileName

        if ($null -eq $package)
        {
            throw ("Required package '{0}' was not defined in 'sitecore-packages.json' so it can't be downloaded, please add the package ' {1}' manually." -f $fileName, $filePath)
        }

        $fileUrl = $package.url

        if ([string]::IsNullOrEmpty($fileUrl))
        {
            Write-Message ("Required package '{0}' not available for download because the url property is empty, please copy '{0}' into '{1}' manually." -f $fileName, $Destination) -Level Warning
        }
        else
        {
            if ($PSCmdlet.ShouldProcess($fileName))
            {
                Write-Message ("Downloading '{0}' to '{1}'..." -f $fileUrl, $filePath)

                if ($fileUrl.StartsWith($sitecoreDownloadUrl))
                {
                    # Login to dev.sitecore.net and save session for re-use
                    if ($null -eq $sitecoreDownloadSession)
                    {
                        Write-Message ("Logging in to '{0}'..." -f $sitecoreDownloadUrl) -Level Verbose

                        $loginResponse = Invoke-WebRequest "https://dev.sitecore.net/api/authorization" -Method Post -Body @{
                            username   = $SitecoreUsername
                            password   = $SitecorePassword
                            rememberMe = $true
                        } -SessionVariable "sitecoreDownloadSession" -UseBasicParsing

                        if ($null -eq $loginResponse -or $loginResponse.StatusCode -ne 200 -or $loginResponse.Content -eq "false")
                        {
                            throw ("Unable to login to '{0}' with the supplied credentials." -f $sitecoreDownloadUrl)
                        }

                        Write-Message ("Logged in to '{0}'." -f $sitecoreDownloadUrl) -Level Verbose
                    }

                    # Download package using saved session
                    Invoke-FileDownload -Url $fileUrl -Path $filePath -Cookies $sitecoreDownloadSession.Cookies

                    $downloadedAtLeastOneFile = $true;
                }
                else
                {
                    # Download package
                    Invoke-FileDownload -Url $fileUrl -Path $filePath

                    $downloadedAtLeastOneFile = $true;
                }
            }
        }
    }

    if ($downloadedAtLeastOneFile) {
        if ($AzureBlobStorageCacheAccountName -or $AzureBlobStorageCacheContainerName -or $AzureBlobStorageCacheAccountKey) {
            if ([string]::IsNullOrWhiteSpace($AzureBlobStorageCacheAccountName)) {
                Write-Error "AzureBlobStorageCacheAccountName is not specified"
                exit -1;
            }

            if ([string]::IsNullOrWhiteSpace($AzureBlobStorageCacheContainerName)) {
                Write-Error "AzureBlobStorageCacheContainerName is not specified"
                exit -1;
            }

            if ([string]::IsNullOrWhiteSpace($AzureBlobStorageCacheAccountKey)) {
                Write-Error "AzureBlobStorageCacheAccountKey is not specified"
                exit -1;
            }

            Push-Location $Destination
            try {
                Write-Host "Syncing folder with azure blob storage after extra files were downloaded, folder: $Destination"
                Write-Host "npx copy-azure-blob@0.0.12 --container `"$AzureBlobStorageCacheContainerName`" --account-name `"$AzureBlobStorageCacheAccountName`" --account-key `"$AzureBlobStorageCacheAccountKey`""
                npx upload-azure-blob@0.0.12 --container "$AzureBlobStorageCacheContainerName" --account-name "$AzureBlobStorageCacheAccountName" --account-key "$AzureBlobStorageCacheAccountKey"
            }
            catch {
                Write-Information "Uploading to azure blob thrown the exception. $($_ | ConvertTo-Json)"
                $LASTEXITCODE = 0;
            }
            finally {
                Pop-Location
            }
        }
    }

    $watch.Stop()
    Write-Message "Restore completed. Time: $($watch.Elapsed.ToString("hh\:mm\:ss\.fff"))."
}
