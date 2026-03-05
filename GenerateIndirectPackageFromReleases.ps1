Write-Host "Generate Indirect NuGet Package"

. (Join-Path $PSScriptRoot "HelperFunctions.ps1")

$toNuGetServerUrl, $githubRepository = GetNuGetServerUrlAndRepository -nuGetServerUrl $env:toNuGetServerUrl
$fromNugetServerUrl = $env:fromNugetServerUrl
$secrets = $env:secrets | ConvertFrom-Json
$token = $secrets.GHTOKENWORKFLOW

$country = $env:country
if ($country -eq '') { $country = 'w1' }
$artifactType = $env:artifactType
if ($artifactType -eq '') { $artifactType = 'sandbox' }
$artifactVersion = "$env:artifactVersion".Trim()

$repos = $env:repo
$apps = @(LatestReleases -token $token -repos $repos -filenamePattern "*-Apps-*")

# Download any missing dependencies from the source NuGet feed and treat them as apps that also need indirect packages
if ($fromNugetServerUrl) {
    $nugetDeps = @(DownloadMissingDependencies -apps $apps -existingDependencies @() -nuGetServerUrl $fromNugetServerUrl -nuGetToken $token)
    if ($nugetDeps.Count -gt 0) {
        Write-Host "Additional dependencies from NuGet (will also generate indirect packages): $($nugetDeps.Count)"
        $nugetDeps | ForEach-Object { Write-Host "  - $_" }
        $apps += $nugetDeps
    }
}

foreach($appFile in $apps) {
    $appJson = Get-AppJsonFromAppFile -appFile $appFile

    # Test whether a NuGet package exists for this app?
    $bcContainerHelperConfig.TrustedNuGetFeeds = @( 
        [PSCustomObject]@{ "url" = $toNuGetServerUrl;  "token" = $token; "Patterns" = @("*.runtime.$($appJson.id)") }
    )
    $package = Get-BcNuGetPackage -packageName "runtime.$($appJson.id)" -version $appJson.version -select Exact
    if (-not $package) {
        # If just one of the apps doesn't exist as a nuGet package, we need to create a new indirect nuGet package and build all runtime versions of the nuGet
        $package = New-BcNuGetPackage -appfile $appFile -githubRepository $githubRepository -isIndirectPackage -packageId "{publisher}.{name}.runtime.{id}" -runtimeDependencyId '{publisher}.{name}.runtime-{version}'
        Push-BcNuGetPackage -nuGetServerUrl $toNuGetServerUrl -nuGetToken $token -bcNuGetPackage $package
    }
}
