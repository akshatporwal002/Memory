$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Enter-SwiftEnvironment.ps1')
$learnerRepo = Split-Path $PSScriptRoot -Parent
$learnerOutput = Join-Path $learnerRepo '.build/learner-model-validation.exe'
New-Item -ItemType Directory -Path (Join-Path $learnerRepo '.build') -Force | Out-Null
$learnerSources = @(
    'Sources/PersistenceAdapters/LearnerModelRepository.swift',
    'Sources/PersistenceAdapters/Repositories.swift',
    'Sources/SchedulingAdapters/FSRSScheduler.swift'
) | ForEach-Object { Join-Path $learnerRepo $_ }
$learnerSources = @(Get-ChildItem -LiteralPath (Join-Path $learnerRepo 'Sources/LearningCore') -Filter '*.swift' -File | ForEach-Object FullName) + $learnerSources
$learnerSources += @(Get-ChildItem -LiteralPath (Join-Path $learnerRepo 'Sources/StudyApplication') -Filter '*.swift' -File | ForEach-Object FullName)
$learnerSources += @(Get-ChildItem -LiteralPath (Join-Path $learnerRepo 'Tools/LearnerModelValidation') -Filter '*.swift' -File | ForEach-Object FullName)
$learnerFSRSOutput = Join-Path $learnerRepo '.build/learner-model-validation-fsrs.dll'
$learnerModuleFiles = @('FSRS.swiftmodule', 'FSRS.swiftdoc', 'FSRS.swiftsourceinfo', 'FSRS.abi.json') | ForEach-Object { Join-Path $learnerRepo ".build/$_" }
$learnerCoreModuleFiles = @('LearningCore.swiftmodule', 'LearningCore.swiftdoc', 'LearningCore.swiftsourceinfo', 'LearningCore.abi.json') | ForEach-Object { Join-Path $learnerRepo ".build/$_" }
$learnerStudyModuleFiles = @('StudyApplication.swiftmodule', 'StudyApplication.swiftdoc', 'StudyApplication.swiftsourceinfo', 'StudyApplication.abi.json') | ForEach-Object { Join-Path $learnerRepo ".build/$_" }
$learnerPersistenceModuleFiles = @('PersistenceAdapters.swiftmodule', 'PersistenceAdapters.swiftdoc', 'PersistenceAdapters.swiftsourceinfo', 'PersistenceAdapters.abi.json') | ForEach-Object { Join-Path $learnerRepo ".build/$_" }
$learnerModuleFiles += $learnerCoreModuleFiles
$learnerModuleFiles += $learnerStudyModuleFiles + $learnerPersistenceModuleFiles
foreach ($learnerModuleFile in $learnerModuleFiles) {
    if (Test-Path -LiteralPath $learnerModuleFile) { throw "Preserving pre-existing output: $learnerModuleFile" }
}
$learnerFSRSSources = @(Get-ChildItem -LiteralPath (Join-Path $learnerRepo 'Vendor/FSRS/Sources') -Filter '*.swift' -File -Recurse | ForEach-Object FullName)
# Importing LearningCore from the same module is ignored by Swift. Production files are compiled unchanged.
try {
    & swiftc -emit-library -emit-module -module-name FSRS @learnerFSRSSources -o $learnerFSRSOutput -emit-module-path $learnerModuleFiles[0]
    if ($LASTEXITCODE -ne 0) { throw 'Existing vendored FSRS compilation failed.' }
    $learnerCoreSources = @(Get-ChildItem -LiteralPath (Join-Path $learnerRepo 'Sources/LearningCore') -Filter '*.swift' -File | ForEach-Object FullName)
    & swiftc -emit-module -parse-as-library -module-name LearningCore @learnerCoreSources -emit-module-path $learnerCoreModuleFiles[0]
    if ($LASTEXITCODE -ne 0) { throw 'LearningCore module compilation failed.' }
    $learnerStudySources = @(Get-ChildItem -LiteralPath (Join-Path $learnerRepo 'Sources/StudyApplication') -Filter '*.swift' -File | ForEach-Object FullName)
    & swiftc -emit-module -parse-as-library -module-name StudyApplication @learnerStudySources -I (Join-Path $learnerRepo '.build') -emit-module-path $learnerStudyModuleFiles[0]
    if ($LASTEXITCODE -ne 0) { throw 'StudyApplication module boundary validation failed.' }
    $learnerPersistenceSources = @('Sources/PersistenceAdapters/Repositories.swift', 'Sources/PersistenceAdapters/LearnerModelRepository.swift') | ForEach-Object { Join-Path $learnerRepo $_ }
    & swiftc -emit-module -parse-as-library -module-name PersistenceAdapters @learnerPersistenceSources -I (Join-Path $learnerRepo '.build') -emit-module-path $learnerPersistenceModuleFiles[0]
    if ($LASTEXITCODE -ne 0) { throw 'Learner persistence module boundary validation failed.' }
    & swiftc -swift-version 6 -typecheck -module-name Features (Join-Path $learnerRepo 'Sources/Features/UnderstandingController.swift') (Join-Path $learnerRepo 'Tools/UnderstandingControllerValidation/BoundaryStubs.swift') -I (Join-Path $learnerRepo '.build')
    if ($LASTEXITCODE -ne 0) { throw 'Understanding controller module boundary validation failed.' }
    $learnerQuestionUISources = @('Sources/Features/NotebookAnalyticsView.swift', 'Sources/Features/QuestionFamilyRow.swift', 'Sources/Features/DeckOverviewView.swift', 'Sources/Features/ContextualAssistant.swift', 'Sources/Features/AssistantController.swift', 'Sources/Features/UnderstandingController.swift', 'Sources/Features/UnderstandingPracticeView.swift', 'Sources/Features/UnderstandingSettingsView.swift', 'Sources/Features/EngramModel.swift', 'Sources/Features/EngramRootView.swift', 'Sources/Features/SettingsView.swift') | ForEach-Object { Join-Path $learnerRepo $_ }
    & swiftc -frontend -parse @learnerQuestionUISources
    if ($LASTEXITCODE -ne 0) { throw 'Question carousel Swift syntax validation failed.' }
    & swiftc -suppress-warnings -parse-as-library -module-name LearningCore @learnerSources -I (Join-Path $learnerRepo '.build') -L (Join-Path $learnerRepo '.build') -llearner-model-validation-fsrs -o $learnerOutput
    if ($LASTEXITCODE -ne 0) { throw 'Learner backend compilation failed.' }
    & $learnerOutput
    if ($LASTEXITCODE -ne 0) { throw 'Learner backend validation failed.' }
} finally {
    foreach ($learnerExtension in @('.exe', '.pdb', '.ilk', '.exp', '.lib')) {
        $learnerDisposable = [System.IO.Path]::ChangeExtension($learnerOutput, $learnerExtension)
        if (Test-Path -LiteralPath $learnerDisposable) { Remove-Item -LiteralPath $learnerDisposable -Force }
    }
    foreach ($learnerExtension in @('.dll', '.pdb', '.ilk', '.exp', '.lib')) {
        $learnerDisposable = [System.IO.Path]::ChangeExtension($learnerFSRSOutput, $learnerExtension)
        if (Test-Path -LiteralPath $learnerDisposable) { Remove-Item -LiteralPath $learnerDisposable -Force }
    }
    foreach ($learnerModuleFile in $learnerModuleFiles) {
        if (Test-Path -LiteralPath $learnerModuleFile) { Remove-Item -LiteralPath $learnerModuleFile -Force }
    }
}
