Write-Host "Generate Indirect NuGet Package"

. (Join-Path $PSScriptRoot "HelperFunctions.ps1")

$appsFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())

$apps = @("$env:apps".Split(','))
# Get workflow input
$nuGetServerUrl, $githubRepository = GetNuGetServerUrlAndRepository -nuGetServerUrl $env:nuGetServerUrl
$nuGetToken = $env:nuGetToken

$fromNugetServerUrl = $env:fromNugetServerUrl
$fromNugetToken = $env:fromNugetToken
$fromApps = @("$env:fromApps".Split(','))

if ($fromNugetServerUrl -ne '' -and $fromNugetToken -ne '') {
    @($fromApps) | % {
        $packageParts = $_.Split(':')
        
        if ($fromApps.Count -eq 2) {
            $apps += Get-BcNuGetPackage -nuGetServerUrl $fromNugetServerUrl -nuGetToken $fromNugetToken -packageName $packageParts[0] -version $packageParts[1] -select Exact
        } else {
            $apps += Get-BcNuGetPackage -nuGetServerUrl $fromNugetServerUrl -nuGetToken $fromNugetToken -packageName $packageParts[0]
        }
    }
}

$apps = @(Copy-AppFilesToFolder -appFiles $apps -folder $appsFolder)

# Download any missing dependencies from the NuGet feed and treat them as apps that also need indirect packages
$nugetDeps = @(DownloadMissingDependencies -apps $apps -existingDependencies @() -nuGetServerUrl $nuGetServerUrl -nuGetToken $nuGetToken)
if ($nugetDeps.Count -gt 0) {
    Write-Host "Additional dependencies from NuGet (will also generate indirect packages): $($nugetDeps.Count)"
    $nugetDeps | ForEach-Object { Write-Host "  - $_" }
    $apps += $nugetDeps
}

foreach($appFile in $apps) {
    $appJson = Get-AppJsonFromAppFile -appFile $appFile

    # Test whether a NuGet package exists for this app?
    $bcContainerHelperConfig.TrustedNuGetFeeds = @( 
        [PSCustomObject]@{ "url" = $nuGetServerUrl;  "token" = $nuGetToken; "Patterns" = @("*.runtime.$($appJson.id)") }
    )
    $package = Get-BcNuGetPackage -packageName "runtime.$($appJson.id)" -version $appJson.version -select Exact
    if (-not $package) {
        # If just one of the apps doesn't exist as a nuGet package, we need to create a new indirect nuGet package and build all runtime versions of the nuGet
        $package = New-BcNuGetPackage -appfile $appFile -githubRepository $githubRepository -isIndirectPackage -packageId "{publisher}.{name}.runtime.{id}" -runtimeDependencyId '{publisher}.{name}.runtime-{version}'
        Push-BcNuGetPackage -nuGetServerUrl $nuGetServerUrl -nuGetToken $nuGetToken -bcNuGetPackage $package
    }
}
