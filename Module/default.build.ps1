<%
    $buildParams = @("task . Clean", "Build")
    if ($PLASTER_PARAM_Pester -eq "Yes")
    {
        $buildParams += "Tests"
    }

    $buildParams += "Stats"

    $buildParams -join ", "
%>
<%
    if ($PLASTER_PARAM_Pester -eq "Yes")
    {
        "task Tests ImportCompiledModule, Pester"
    }
    
%>
<%
    $tasks = @("task CreateManifest CopyPSD, UpdatePublicFunctionsToExport")
    if ($PLASTER_PARAM_FunctionFolders -contains 'DSCResources')
    {
        $tasks += "UpdateDSCResourceToExport"
    }
    ($tasks -join ", ")
%>
task Build Compile, CreateManifest
task Stats RemoveStats, WriteStats

$script:ModuleName = Split-Path -Path $PSScriptRoot -Leaf
$script:ModuleRoot = $PSScriptRoot
$script:OutPutFolder = "$PSScriptRoot/Output"
<%
    $folders = @()
    if ($PLASTER_PARAM_FunctionFolders -contains 'Public')
    {
        $folders += "'Public'"
    }

    if ($PLASTER_PARAM_FunctionFolders -contains 'Internal')
    {
        $folders += "'Internal'"
    }

    if ($PLASTER_PARAM_FunctionFolders -contains 'Classes')
    {
        $folders += "'Classes'"
    }

    if ($PLASTER_PARAM_FunctionFolders -contains 'DSCResources')
    {
        $folders += "'DSCResources'"
    }

    $importfolders = $folders -join ", "
    
    '$script:ImportFolders = @({0})' -f $importfolders
%>
$script:PsmPath = Join-Path -Path $PSScriptRoot -ChildPath "Output/$($script:ModuleName)/$($script:ModuleName).psm1"
$script:PsdPath = Join-Path -Path $PSScriptRoot -ChildPath "Output/$($script:ModuleName)/$($script:ModuleName).psd1"

$script:PublicFolder = 'Public'
$script:DSCResourceFolder = 'DSCResources'


task Clean {
    if (-not(Test-Path $script:OutPutFolder))
    {
        New-Item -ItemType Directory -Path $script:OutPutFolder > $null
    } else {
      $resolvedOutputContents = Resolve-Path $script:OutPutFolder;
      if ($resolvedOutputContents) {
        Remove-Item -Path (Resolve-Path $resolvedOutputContents) -Force -Recurse
      }
    }
}

$compileParams = @{
    Inputs = {
        foreach ($folder in $script:ImportFolders)
        {
            Get-ChildItem -Path $folder -Recurse -File -Filter '*.ps1'
        }
    }

    Output = {
        $script:PsmPath
    }
}

task Compile @compileParams {
    if (Test-Path -Path $script:PsmPath)
    {
        Remove-Item -Path (Resolve-Path $script:PsmPath) -Recurse -Force
    }
    New-Item -Path $script:PsmPath -Force > $null

    foreach ($folder in $script:ImportFolders)
    {
        $currentFolder = Join-Path -Path $script:ModuleRoot -ChildPath $folder
        Write-Verbose -Message "Checking folder [$currentFolder]"

        if (Test-Path -Path $currentFolder)
        {
            $files = Get-ChildItem -Path $currentFolder -File -Filter '*.ps1'
            foreach ($file in $files)
            {
                Write-Verbose -Message "Adding $($file.FullName)"
                Get-Content -Path (Resolve-Path $file.FullName) >> $script:PsmPath
            }
        }
    }
}

task CopyPSD {
    New-Item -Path (Split-Path $script:PsdPath) -ItemType Directory -ErrorAction 0
    $copy = @{
        Path        = "$($script:ModuleName).psd1"
        Destination = $script:PsdPath
        Force       = $true
        Verbose  = $true
    }
    Copy-Item @copy
}

task UpdatePublicFunctionsToExport -if (Test-Path -Path $script:PublicFolder) {
    $publicFunctions = (Get-ChildItem -Path $script:PublicFolder |
            Select-Object -ExpandProperty BaseName) -join "', '"

    $publicFunctions = "FunctionsToExport = @('{0}')" -f $publicFunctions

    (Get-Content -Path $script:PsdPath) -replace "FunctionsToExport = '/*'", $publicFunctions |
        Set-Content -Path $script:PsdPath
}

<%
    if ($PLASTER_PARAM_FunctionFolders -contains 'DSCResources')
    {
        @'
task UpdateDSCResourceToExport -if (Test-Path -Path $script:DSCResourceFolder) {
    $resources = (Get-ChildItem -Path $script:DSCResourceFolder |
            Select-Object -ExpandProperty BaseName) -join "', '"

    $resources = "'{0}'" -f $resources

    (Get-Content -Path $script:PsdPath) -replace "'_ResourcesToExport_'", $resources |
        Set-Content -Path $script:PsdPath   
}     
'@
    }
%>

task ImportCompiledModule -if (Test-Path -Path $script:PsmPath) {
    Get-Module -Name $script:ModuleName |
        Remove-Module -Force
    Import-Module -Name $script:PsdPath -Force
}

<%
    if ($PLASTER_PARAM_Pester -eq "Yes")
    {
        @'
task Pester {
    $resultFile = "{0}/testResults{1}.xml" -f $script:OutPutFolder, (Get-date -Format 'yyyyMMdd_hhmmss')
    $testFolder = Join-Path -Path $PSScriptRoot -ChildPath 'Tests/*'
    Invoke-Pester -Path $testFolder -OutputFile $resultFile -OutputFormat NUnitxml
}     
'@
    }
%>

task RemoveStats -if (Test-Path -Path "$($script:OutPutFolder)/stats.json") {
    Remove-Item -Force -Verbose -Path (Resolve-Path "$($script:OutPutFolder)/stats.json") 
}

task WriteStats {
    $folders = Get-ChildItem -Directory | 
        Where-Object {$PSItem.Name -ne 'Output'}
    
    $stats = foreach ($folder in $folders)
    {
        $files = Get-ChildItem "$($folder.FullName)/*" -File
        if($files)
        {
            Get-Content -Path (Resolve-Path $files) | 
            Measure-Object -Word -Line -Character | 
            Select-Object -Property @{N = "FolderName"; E = {$folder.Name}}, Words, Lines, Characters
        }
    }
    $stats | ConvertTo-Json > "$script:OutPutFolder/stats.json"
}
