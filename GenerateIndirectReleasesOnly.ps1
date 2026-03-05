Write-Host "Generate Indirect NuGet Package (Releases Only)"

. (Join-Path $PSScriptRoot "HelperFunctions.ps1")

$nuGetServerUrl, $githubRepository = GetNuGetServerUrlAndRepository -nuGetServerUrl $env:nuGetServerUrl
$secrets = $env:secrets | ConvertFrom-Json
$token = $secrets.GHTOKENWORKFLOW

# Auto-discover repos from org or use explicit list
$org = $env:org
$repos = $env:repos
if ($org) {
    $discoveredRepos = @(DiscoverOrgRepos -token $token -org $org -filenamePattern "*-Apps-*")
    if ($repos) {
        $repos = ($repos.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) + $discoveredRepos | Select-Object -Unique
        $repos = $repos -join ','
    } else {
        $repos = $discoveredRepos -join ','
    }
}

# Get apps and dependencies from releases
$appFiles = @(LatestReleases -token $token -repos $repos -filenamePattern "*-Apps-*")
$depFiles = @(LatestReleases -token $token -repos $repos -filenamePattern "*-Dependencies-*")

# Non-Microsoft dependencies also get indirect packages
$apps = @($appFiles)
foreach ($depFile in $depFiles) {
    $depJson = Get-AppJsonFromAppFile -appFile $depFile
    if ($depJson.publisher -ne 'Microsoft') {
        $apps += $depFile
    }
}

Write-Host "Apps (incl. non-Microsoft dependencies): $($apps.Count)"
$apps | ForEach-Object { Write-Host "  - $_" }

foreach($appFile in $apps) {
    $appJson = Get-AppJsonFromAppFile -appFile $appFile

    # Test whether a NuGet package exists for this app?
    $bcContainerHelperConfig.TrustedNuGetFeeds = @(
        [PSCustomObject]@{ "url" = $nuGetServerUrl;  "token" = $token; "Patterns" = @("*.runtime.$($appJson.id)") }
    )
    $package = Get-BcNuGetPackage -packageName "runtime.$($appJson.id)" -version $appJson.version -select Exact
    if (-not $package) {
        $package = New-BcNuGetPackage -appfile $appFile -githubRepository $githubRepository -isIndirectPackage -packageId "{publisher}.{name}.runtime.{id}" -runtimeDependencyId '{publisher}.{name}.runtime-{version}'
        Push-BcNuGetPackage -nuGetServerUrl $nuGetServerUrl -nuGetToken $token -bcNuGetPackage $package
    }
}
