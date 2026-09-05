param([switch]$ForceDownload)
$ErrorActionPreference = 'Stop'
$bl6Root = Split-Path $PSScriptRoot -Parent
$bl6Tools = Join-Path $bl6Root '.tools'
$bl6EditorDir = Join-Path $bl6Tools 'godot'
$bl6TemplateDir = Join-Path $bl6Tools 'templates'
New-Item -ItemType Directory -Force -Path $bl6Tools, $bl6EditorDir, $bl6TemplateDir | Out-Null
$bl6Base = 'https://github.com/godotengine/godot-builds/releases/download/4.5.2-stable/'
$bl6ChecksumFile = Join-Path $bl6Tools 'SHA512-SUMS.txt'
Invoke-WebRequest -Uri ($bl6Base + 'SHA512-SUMS.txt') -OutFile $bl6ChecksumFile
$bl6Sums = Get-Content -LiteralPath $bl6ChecksumFile
$bl6Downloads = @{
    'Godot_v4.5.2-stable_win64.exe.zip' = 'godot-editor.zip'
    'Godot_v4.5.2-stable_export_templates.tpz' = 'godot-templates.tpz'
}
foreach ($bl6Entry in $bl6Downloads.GetEnumerator()) {
    $bl6ArchivePath = Join-Path $bl6Tools $bl6Entry.Value
    if ($ForceDownload -or -not (Test-Path -LiteralPath $bl6ArchivePath)) {
        Write-Host ('Downloading ' + $bl6Entry.Key)
        & curl.exe -L --fail --retry 3 ($bl6Base + $bl6Entry.Key) -o $bl6ArchivePath
        if ($LASTEXITCODE -ne 0) { throw ('Download failed: ' + $bl6Entry.Key) }
    }
    $bl6Line = $bl6Sums | Where-Object { $_.EndsWith($bl6Entry.Key) } | Select-Object -First 1
    if (-not $bl6Line) { throw ('Missing official checksum for ' + $bl6Entry.Key) }
    $bl6Expected = ($bl6Line -split '\s+')[0]
    $bl6Actual = (Get-FileHash -LiteralPath $bl6ArchivePath -Algorithm SHA512).Hash
    if ($bl6Actual -ne $bl6Expected) { throw ('SHA512 mismatch: ' + $bl6Entry.Key) }
    Write-Host ($bl6Entry.Key + ' SHA512 verified')
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
Expand-Archive -LiteralPath (Join-Path $bl6Tools 'godot-editor.zip') -DestinationPath $bl6EditorDir -Force
$bl6Archive = [System.IO.Compression.ZipFile]::OpenRead((Join-Path $bl6Tools 'godot-templates.tpz'))
try {
    foreach ($bl6Name in @('version.txt', 'windows_debug_x86_64.exe', 'windows_release_x86_64.exe', 'windows_debug_x86_64_console.exe', 'windows_release_x86_64_console.exe')) {
        $bl6Entry = $bl6Archive.GetEntry('templates/' + $bl6Name)
        if (-not $bl6Entry) { throw ('Template not present: ' + $bl6Name) }
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($bl6Entry, (Join-Path $bl6TemplateDir $bl6Name), $true)
    }
} finally { $bl6Archive.Dispose() }
& (Join-Path $bl6EditorDir 'Godot_v4.5.2-stable_win64_console.exe') --version
Write-Host 'Godot 4.5.2 editor and Windows x64 release templates are ready in .tools.'
