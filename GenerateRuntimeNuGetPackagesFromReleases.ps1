Write-Host "Generate Runtime NuGet Packages"

. (Join-Path $PSScriptRoot "HelperFunctions.ps1")

$containerName = 'bcserver'

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
$dependencies = @(LatestReleases -token $token -repos $repos -filenamePattern "*-Dependencies-*")

Write-Host "Apps: $($apps.Count)"
$apps | ForEach-Object { Write-Host "  - $_" }
Write-Host "Dependencies from releases: $($dependencies.Count)"
$dependencies | ForEach-Object { Write-Host "  - $_" }

# Download any missing dependencies from the source NuGet feed
if ($fromNugetServerUrl) {
    $nugetDeps = @(DownloadMissingDependencies -apps $apps -existingDependencies $dependencies -nuGetServerUrl $fromNugetServerUrl -nuGetToken $token)
    if ($nugetDeps.Count -gt 0) {
        Write-Host "Additional dependencies from NuGet: $($nugetDeps.Count)"
        $nugetDeps | ForEach-Object { Write-Host "  - $_" }
        $dependencies += $nugetDeps
    }
}

Write-Host "Total dependencies: $($dependencies.Count)"

$additionalCountries = @("$env:additionalCountries".Split(',') | Where-Object { $_ -and $_ -ne $country })
# Artifact version is from the matrix
$artifactVersion = $env:artifactVersion
$incompatibleArtifactVersion = $env:incompatibleArtifactVersion

# Determine runtime dependency package ids for all apps and whether any of the apps doesn't exist as a nuGet package
$runtimeDependencyPackageIds, $newPackage = GetRuntimeDependencyPackageIds -apps $apps -nuGetServerUrl $nuGetServerUrl -nuGetToken $token

$licenseFileUrl = $env:licenseFileUrl
if ([System.Version]$artifactVersion -ge [System.Version]'22.0.0.0') {
    $licenseFileUrl = ''
}

# Create Runtime packages for main country and additional countries
$runtimeAppFiles, $countrySpecificRuntimeAppFiles = GenerateRuntimeAppFiles -containerName $containerName -type $artifactType -country $country -additionalCountries $additionalCountries -artifactVersion $artifactVersion -apps $apps -dependencies $dependencies -licenseFileUrl $licenseFileUrl

# For every app create and push nuGet package (unless the exact version already exists)
foreach($appFile in $apps) {
    $appName = [System.IO.Path]::GetFileName($appFile)
    $runtimeDependencyPackageId = $runtimeDependencyPackageIds."$appName"
    $bcContainerHelperConfig.TrustedNuGetFeeds = @( 
        [PSCustomObject]@{ "url" = $nuGetServerUrl;  "token" = $token; "Patterns" = @($runtimeDependencyPackageId) }
    )
    $package = Get-BcNuGetPackage -packageName $runtimeDependencyPackageId -version $artifactVersion -select Exact
    if (-not $package) {
        $runtimePackage = New-BcNuGetPackage -appfile $runtimeAppFiles."$appName" -countrySpecificAppFiles $countrySpecificRuntimeAppFiles."$appName" -packageId $runtimeDependencyPackageId -packageVersion $artifactVersion -applicationDependency "[$artifactVersion,$incompatibleArtifactVersion)" -githubRepository $githubRepository
        try {
            Push-BcNuGetPackage -nuGetServerUrl $toNuGetServerUrl -nuGetToken $token -bcNuGetPackage $runtimePackage
        }
        catch {
            if ($_.Exception.Message -like '*409*') {
                Write-Host "Package already exists (409 Conflict), skipping: $runtimeDependencyPackageId $artifactVersion"
            }
            else {
                throw $_
            }
        }
    }
}
