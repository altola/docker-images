param(
    [Parameter(Mandatory=$true)]
    [int]
    $sitecoreVersion
)

$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';

Write-Host "Sitecore version is $sitecoreVersion"

if ($sitecoreVersion -lt 930) {
    Write-Warning "Sitecore version is prior to 9.3.0 means C:\license\license.xml file is to be created"
    try
    {
        $gzipBytes = [System.Convert]::FromBase64String($env:SITECORE_LICENSE)
        $memory = [System.IO.MemoryStream]::new($gzipBytes)

        $licenseFileStream = [System.IO.Compression.GZipStream]::new($memory, [System.IO.Compression.CompressionMode]::Decompress)
        $reader = [System.IO.StreamReader]::new($licenseFileStream)
        $licenseText = $reader.ReadToEnd();
        $licenseFileStream.Close()

        if (-not (Test-Path "C:\license")) {
            MKDIR "C:\license" | Out-Null
        }    
        [System.IO.File]::WriteAllText("C:\license\license.xml", $licenseText)
    }
    finally
    {
        # cleanup
        if ($null -ne $reader)
        {
            $reader.Dispose()
            $reader = $null
        }


        if ($null -ne $gzip)
        {
            $gzip.Dispose()
            $gzip = $null
        }

        if ($null -ne $memory)
        {
            $memory.Dispose()
            $memory = $null
        }

        $licenseFileStream = $null
    }
}

$env:REGISTRY = "$env:REGISTRY".TrimEnd('/') + "/";
