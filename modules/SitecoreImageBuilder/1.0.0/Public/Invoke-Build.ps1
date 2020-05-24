class ReportRecord
{
    [string]$Name
    [string]$Time
    [int]$Index

    ReportRecord([string]$Name, [string]$Time, [int]$Index)
    {
        $this.Name = $Name
        $this.Time = $Time
        $this.Index = $Index
    }
}

function Invoke-Build
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "SitecorePassword")]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript( { Test-Path $_ -PathType "Container" })]
        [string]$Path
        ,
        [Parameter(Mandatory = $true)]
        [ValidateScript( { Test-Path $_ -PathType "Container" })]
        [string]$InstallSourcePath
        ,
        [Parameter(Mandatory = $true)]
        [string]$Registry
        ,
        [Parameter(Mandatory = $false)]
        [array]$Tags
        ,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Include", "Skip")]
        [string]$ImplicitTagsBehavior = "Include"
        ,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Include", "Skip")]
        [string]$DeprecatedTagsBehavior = "Skip"
        ,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Include", "Skip")]
        [string]$ExperimentalTagBehavior = "Skip"
        ,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Always", "Never")]
        [string]$PullMode = "Always"
        ,
        [Parameter(Mandatory = $false)]
        [switch]$SkipHashValidation
    )

    # Setup
    $ErrorActionPreference = "STOP"
    $ProgressPreference = "SilentlyContinue"

    $watch = [System.Diagnostics.StopWatch]::StartNew()
    $reportRecords = [System.Collections.Generic.List[ReportRecord]]@()

    # Load packages
    $packages = Get-Packages

    $allSpecs = Get-BuildSpecifications -Path $Path

    if ($Tags -eq $null)
    {
        $Tags = Get-LatestSupportedVersionTags -Specs $allSpecs
    }

    # Find out what to build
    $specs = Initialize-BuildSpecifications -Specifications $allSpecs -InstallSourcePath $InstallSourcePath -Tags $Tags -ImplicitTagsBehavior $ImplicitTagsBehavior -DeprecatedTagsBehavior $DeprecatedTagsBehavior -ExperimentalTagBehavior $ExperimentalTagBehavior

    # Print results
    $specs | Select-Object -Property Tag, Include, Deprecated, Priority, Base | Format-Table

    Write-Message "Build specifications loaded..." -Level Info

    # Start build...
    if ($PSCmdlet.ShouldProcess("Start image builds"))
    {
        $currentCount = 0
        $totalCount = $specs | Where-Object { $_.Include } | Measure-Object | Select-Object -ExpandProperty Count
        $specs | Where-Object { $_.Include } | ForEach-Object {
            $spec = $_
            $fulltag = "{0}/{1}" -f $Registry, $spec.Tag

            $currentCount++
            Write-Message "Processing $($currentCount) of $($totalCount) '$($fulltag)'..."

            $Repository = $spec.Tag.Split(':')[0];
            $existingRepositories = az acr repository list --name $Registry | ConvertFrom-Json
            if ($existingRepositories.Contains($Repository))
            {
                $existingTags = az acr repository show-tags --name $Registry --repository $Repository | ConvertFrom-Json
                if ($existingTags.Contains($spec.Tag.Split(':')[1]))
                {
                    Write-Message "Already exists in Azure CR. Skipping..."
                    return;
                }
            }

            $currentWatch = [System.Diagnostics.StopWatch]::StartNew()

            # Copy any missing source files into build context
            $spec.Sources | ForEach-Object {
                $sourcePath = $_

                # Continue if source file doesn't exist
                if (!(Test-Path $sourcePath))
                {
                    Write-Message "Optional source file '$sourcePath' is missing..." -Level Warning

                    return
                }

                $sourceItem = Get-Item -Path $sourcePath
                $targetPath = Join-Path $spec.Path $sourceItem.Name

                # Copy if target doesn't exist. Legacy support: Always copy if the source is license.xml.
                if (!(Test-Path -Path $targetPath) -or ($sourceItem.Name -eq "license.xml"))
                {
                    Copy-Item $sourceItem -Destination $targetPath -Verbose:$VerbosePreference
                }

                # Check to see if we can lookup the hash of the source filename in sitecore-packages.json
                if (!$SkipHashValidation)
                {
                    $package = $packages."$($sourceItem.Name)"

                    if ($null -ne $package -and ![string]::IsNullOrEmpty($package.hash))
                    {
                        $expectedTargetFileHash = $package.hash

                        # Calculate hash of target file
                        $currentTargetFileHash = Get-FileHash -Path $targetPath -Algorithm "SHA256" | Select-Object -ExpandProperty "Hash"

                        # Compare hashes and fail if not the same
                        if ($currentTargetFileHash -eq $expectedTargetFileHash)
                        {
                            Write-Message ("Hash of '{0}' is valid." -f $sourceItem.Name) -Level Debug
                        }
                        else
                        {
                            Remove-Item -Path $targetPath -Force -Verbose:$VerbosePreference

                            throw ("Hash of '{0}' is invalid:`n Expected: {1}`n Current : {2}`nThe target file '{3}' was deleted, please also check the source file '{4}' and see if it is corrupted, if so delete it and try again." -f $sourceItem.Name, $expectedTargetFileHash, $currentTargetFileHash, $targetPath, $sourceItem.FullName)
                        }
                    }
                    else
                    {
                        Write-Message ("Skipping hash validation on '{0}', package was not found or no hash was defined." -f $sourceItem.Name) -Level Verbose
                    }
                }
            }

            # Build image
            $buildOptions = New-Object System.Collections.Generic.List[System.Object]

            $spec.BuildOptions | ForEach-Object {
                $option = $_

                $index = $option.IndexOf('=');
                if ($index -ge 0) {
                    $key = $option.Substring(0, $index)
                    $value = $option.Substring($index + 1)
                    if ($value.StartsWith("C:")) {
                        $option = $key + '=' + ($value -replace '[^:^\\^/^\.^\w^-]');
                    }
                }

                Write-Host "Build Options: $option"
                $buildOptions.Add($option)
            }

            $buildOptions.Add("--registry '$Registry'")

            $buildOptions.Add("-t '$fulltag'")

            $buildOptions.Add("--platform 'windows'")

            $command = "az acr build {0} '{1}'" -f ($buildOptions -join " "), $spec.Path

            Write-Message ("Invoking: {0} " -f $command) -Level Verbose -Verbose:$VerbosePreference

            Invoke-Expression "$command" -ErrorVariable errorvar -Verbose -Debug

            Write-Warning "ErrorVartiable: $errorvar, code: $LASTEXITCODE"

            $LASTEXITCODE -ne 0 | Where-Object { $_ } | ForEach-Object { throw "Failed: $command" }

            $currentWatch.Stop()
            Write-Message "Build completed for $($fulltag). Time: $($currentWatch.Elapsed.ToString("hh\:mm\:ss\.fff"))." -Level Debug
            $reportRecords.Add(([ReportRecord]::new($fulltag, $currentWatch.Elapsed.ToString("hh\:mm\:ss\.fff"), $currentCount))) > $null

            Write-Message ("Processing complete for '{0}', image pushed." -f $fulltag)
        }
    }

    $watch.Stop()
    Write-Message "Builds completed. Time: $($watch.Elapsed.ToString("hh\:mm\:ss\.fff"))."

    Write-Output $reportRecords | Format-Table -Property Index, Time, Name
}
