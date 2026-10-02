param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*$')][string]$View,
    [Parameter(Mandatory = $true)][string]$Image
)

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$sourcePath = (Resolve-Path -LiteralPath $Image).Path
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Screenshot does not exist: $Image"
}

$snapshotRoot = Join-Path $repoRoot 'current_ui'
$viewDirectory = Join-Path $snapshotRoot $View
New-Item -ItemType Directory -Force -Path $viewDirectory | Out-Null
$currentPath = Join-Path $viewDirectory 'current.png'
$previousPath = Join-Path $viewDirectory 'previous.png'
if ([System.IO.Path]::GetFullPath($sourcePath) -eq [System.IO.Path]::GetFullPath($currentPath)) {
    throw 'The source image is already the current capture.'
}
if ([System.IO.Path]::GetExtension($sourcePath) -ne '.png') {
    throw 'The source capture must be a PNG.'
}
$incomingPath = Join-Path $viewDirectory 'incoming.png'
Copy-Item -LiteralPath $sourcePath -Destination $incomingPath -Force

if (Test-Path -LiteralPath $currentPath) {
    if (Test-Path -LiteralPath $previousPath) { Remove-Item -LiteralPath $previousPath }
    Move-Item -LiteralPath $currentPath -Destination $previousPath
}
Move-Item -LiteralPath $incomingPath -Destination $currentPath
Write-Output $currentPath
