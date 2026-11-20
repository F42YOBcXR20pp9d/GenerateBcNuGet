BeforeAll {
    . (Join-Path $PSScriptRoot '..\RuntimeAppFiles.ps1')
}

Describe 'ResolveRuntimeAppFile' {
    BeforeEach {
        $destinationFolder = Join-Path $TestDrive ([Guid]::NewGuid().ToString())
        New-Item -Path $destinationFolder -ItemType Directory | Out-Null
        $fileName = 'BEYONDIT GmbH_BeyondCues_2026.11.316.0.runtime-29.0.54011.55407-de.app'
        $expected = Join-Path $destinationFolder $fileName
        Set-Content -Path $expected -Value 'runtime'
    }

    It 'returns the runtime file reported by BcContainerHelper when it exists (BC27/28)' {
        ResolveRuntimeAppFile -destinationFolder $destinationFolder -runtimeFile $expected | Should -Be $expected
    }

    It 'finds the runtime file when BC29 output leaks the container path into the reported path' {
        $reported = "$destinationFolder\C:\dest\$fileName\$fileName"
        ResolveRuntimeAppFile -destinationFolder $destinationFolder -runtimeFile $reported | Should -Be $expected
    }

    It 'finds the runtime file when the reported path is an array of container output and file name' {
        $reported = @("C:\dest\$fileName", $fileName)
        ResolveRuntimeAppFile -destinationFolder $destinationFolder -runtimeFile $reported | Should -Be $expected
    }

    It 'fails when no runtime package was generated' {
        { ResolveRuntimeAppFile -destinationFolder $destinationFolder -runtimeFile $null } | Should -Throw '*Could not generate runtime package*'
    }

    It 'fails when the runtime file does not exist in the destination folder' {
        Remove-Item $expected
        { ResolveRuntimeAppFile -destinationFolder $destinationFolder -runtimeFile $expected } | Should -Throw '*Could not generate runtime package*'
    }
}
