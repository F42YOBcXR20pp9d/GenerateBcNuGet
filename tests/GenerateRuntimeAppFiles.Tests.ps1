# Feature-level test of GenerateRuntimeAppFiles with BcContainerHelper (the container boundary) faked.
# HelperFunctions.ps1 downloads BcContainerHelper when dot-sourced, so only the function under test is loaded.
BeforeAll {
    . (Join-Path $PSScriptRoot '..\RuntimeAppFiles.ps1')
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\HelperFunctions.ps1'), [ref]$null, [ref]$null)
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'GenerateRuntimeAppFiles' }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))

    function Get-BCArtifactUrl { Param($type, $country, $version, $select) "https://bcartifacts/$type/$version/$country" }

    # Emulates BcContainerHelper's Convert-BcAppsToRuntimePackages: writes <publisher>_<name>.runtime-<version>-<country>.app
    # into the destination folder and reports runtimeFile the way BcContainerHelper does for the given BC version.
    function Convert-BcAppsToRuntimePackages {
        Param($containerName, $artifactUrl, $imageName, $apps, $publishApps, $licenseFile, [switch] $skipVerification, $destinationFolder, [scriptblock] $afterEachRuntimeCreation)
        if (-not $destinationFolder) { $destinationFolder = Join-Path $TestDrive ([Guid]::NewGuid().ToString()) }
        New-Item -Path $destinationFolder -ItemType Directory -Force | Out-Null
        $version, $country = $artifactUrl.Split('/')[-2..-1]
        foreach ($app in $apps) {
            $fileName = "$([System.IO.Path]::GetFileNameWithoutExtension($app)).runtime-$version-$country.app"
            Set-Content -Path (Join-Path $destinationFolder $fileName) -Value "$version $country"
            if ([version]$version -ge [version]'29.0') {
                # BC29: Get-NavAppRuntimePackage output leaks into the returned file name
                $runtimeFile = "$destinationFolder\C:\dest\$fileName\$fileName"
            }
            else {
                $runtimeFile = Join-Path $destinationFolder $fileName
            }
            $afterEachRuntimeCreation.Invoke(@{ appFile = $app; runtimeFile = $runtimeFile })
        }
        $destinationFolder
    }
}

Describe 'GenerateRuntimeAppFiles' {
    It 'returns existing runtime .app files for main and additional countries on <version>' -ForEach @(
        @{ version = '27.13.57301.0' }
        @{ version = '29.0.54011.55407' }
    ) {
        $apps = @('C:\apps\BEYONDIT GmbH_BeyondCues_2026.11.316.0.app', 'C:\apps\BEYONDIT GmbH_BeyondLicense_2026.11.158.1.app')

        $runtimeAppFiles, $countrySpecific = GenerateRuntimeAppFiles -containerName 'bcserver' -type 'onprem' -country 'de' -additionalCountries @('at', 'ch', 'gb') -artifactVersion $version -apps $apps -dependencies @() -licenseFileUrl ''

        foreach ($app in $apps) {
            $appName = [System.IO.Path]::GetFileName($app)
            $runtimeAppFiles.$appName | Should -Exist
            Get-Content $runtimeAppFiles.$appName | Should -Be "$version de"
            foreach ($ct in 'at', 'ch', 'gb') {
                $countrySpecific.$appName.$ct | Should -Exist
                Get-Content $countrySpecific.$appName.$ct | Should -Be "$version $ct"
            }
        }
    }
}
