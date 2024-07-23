Write-Host "Generate Runtime NuGet Packages"

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

$repo = $env:repo
$apps = @(LatestRelease -token $token -repo $repo)

$symbolsOnly = ($env:symbolsOnly -eq 'true')
$packageIdTemplate = $env:packageIdTemplate

foreach($appFile in $apps) {
    $appJson = Get-AppJsonFromAppFile -appFile $appFile

    # Test whether a NuGet package exists for this app?
    $bcContainerHelperConfig.TrustedNuGetFeeds = @( 
        [PSCustomObject]@{ "url" = $toNuGetServerUrl;  "token" = $nuGetToken; "Patterns" = @("*.$($appJson.id)") }
    )
    $package = Get-BcNuGetPackage -packageName $appJson.id -version $appJson.version -select Exact
    if (-not $package) {
        # If the app doesn't exist as a nuGet package, create it
        $useAppFile = GetAppFile -appFile $appFile -symbolsOnly:$symbolsOnly
        $package = New-BcNuGetPackage -appfile $useAppFile -githubRepository $githubRepository -packageId $packageIdTemplate -dependencyIdTemplate $packageIdTemplate
        Push-BcNuGetPackage -nuGetServerUrl $toNuGetServerUrl -nuGetToken $nuGetToken -bcNuGetPackage $package
        if ($useAppFile -ne $appFile) {
            Remove-Item -Path $useAppFile -Force
        }
    }
}
