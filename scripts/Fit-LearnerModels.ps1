param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Enter-SwiftEnvironment.ps1')
$learnerFitRepo = Split-Path $PSScriptRoot -Parent
$learnerFitExecutable = Join-Path $learnerFitRepo '.build/learner-model-fit.exe'
New-Item -ItemType Directory -Path (Join-Path $learnerFitRepo '.build') -Force | Out-Null
$learnerFitSources = @(Get-ChildItem -LiteralPath (Join-Path $learnerFitRepo 'Sources/LearningCore') -Filter '*.swift' -File | ForEach-Object FullName)
$learnerFitSources += Join-Path $learnerFitRepo 'Tools/LearnerModelFit/main.swift'
try {
    & swiftc -parse-as-library -module-name LearningCore @learnerFitSources -o $learnerFitExecutable
    if ($LASTEXITCODE -ne 0) { throw 'Learner fitter compilation failed.' }
    & $learnerFitExecutable ([System.IO.Path]::GetFullPath($InputPath)) ([System.IO.Path]::GetFullPath($OutputPath))
    if ($LASTEXITCODE -ne 0) { throw 'Learner fitting rejected the dataset or failed. No model was activated.' }
} finally {
    foreach ($learnerFitExtension in @('.exe', '.pdb', '.ilk', '.exp', '.lib')) {
        $learnerFitDisposable = [System.IO.Path]::ChangeExtension($learnerFitExecutable, $learnerFitExtension)
        if (Test-Path -LiteralPath $learnerFitDisposable) { Remove-Item -LiteralPath $learnerFitDisposable -Force }
    }
}
