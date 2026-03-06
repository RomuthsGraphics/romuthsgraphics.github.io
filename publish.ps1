Add-Type -AssemblyName System.Drawing

$ProjectRoot = "E:\WEB AND APP DEVELOPMENT\WebSites\Romuths Graphic Designing"
$ProjectsFile = Join-Path $ProjectRoot "projects.js"

# ============================================================
# STEP 1: Find new images not yet in projects.js
# ============================================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Romuths Graphics - Publish New Works  " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$projectsContent = Get-Content $ProjectsFile -Raw

# Scan both folders for image files
$recentImages = Get-ChildItem "$ProjectRoot\works\recent" -File | Where-Object { $_.Extension -match '\.(jpg|jpeg|png|webp)$' }
$showcaseImages = Get-ChildItem "$ProjectRoot\works\showcase" -File | Where-Object { $_.Extension -match '\.(jpg|jpeg|png|webp)$' }

$newRecent = @()
$newShowcase = @()

foreach ($img in $recentImages) {
    $searchPath = "works/recent/$($img.Name)"
    if ($projectsContent -notmatch [regex]::Escape($img.Name)) {
        $newRecent += $img
    }
}

foreach ($img in $showcaseImages) {
    if ($projectsContent -notmatch [regex]::Escape($img.Name)) {
        $newShowcase += $img
    }
}

$totalNew = $newRecent.Count + $newShowcase.Count

if ($totalNew -eq 0) {
    Write-Host "No new images found. Everything is already in projects.js!" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit
}

Write-Host "Found $totalNew new image(s):" -ForegroundColor Green
foreach ($img in $newRecent) { Write-Host "  [RECENT]   $($img.Name)" -ForegroundColor White }
foreach ($img in $newShowcase) { Write-Host "  [SHOWCASE] $($img.Name)" -ForegroundColor White }
Write-Host ""

# ============================================================
# STEP 2: Compress new images
# ============================================================
Write-Host "--- Compressing new images ---" -ForegroundColor Cyan

function Compress-Image {
    param([string]$InputPath, [int]$MaxWidth = 1920, [int]$Quality = 65)
    try {
        $img = [System.Drawing.Image]::FromFile($InputPath)
        $originalSize = (Get-Item $InputPath).Length
        if ($originalSize -lt 500KB) {
            $img.Dispose()
            Write-Host "  SKIP (already small): $(Split-Path $InputPath -Leaf)" -ForegroundColor DarkGray
            return
        }
        $ratio = if ($img.Width -gt $MaxWidth) { $MaxWidth / $img.Width } else { 1.0 }
        $newW = [int]($img.Width * $ratio)
        $newH = [int]($img.Height * $ratio)
        $bmp = New-Object System.Drawing.Bitmap($newW, $newH)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.DrawImage($img, 0, 0, $newW, $newH)

        $ext = [System.IO.Path]::GetExtension($InputPath).ToLower()
        $tmp = "$InputPath.tmp"
        if ($ext -eq ".png") {
            $bmp.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
        } else {
            $enc = [System.Drawing.Imaging.Encoder]::Quality
            $ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
            $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter($enc, [long]$Quality)
            $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
            $bmp.Save($tmp, $codec, $ep)
        }
        $g.Dispose(); $bmp.Dispose(); $img.Dispose()
        Remove-Item $InputPath -Force
        Rename-Item $tmp -NewName (Split-Path $InputPath -Leaf) -Force
        $nz = (Get-Item $InputPath).Length
        $pct = [math]::Round((1 - $nz / $originalSize) * 100, 1)
        Write-Host "  OK: $(Split-Path $InputPath -Leaf): $([math]::Round($originalSize/1KB,0))KB -> $([math]::Round($nz/1KB,0))KB (saved ${pct}%)" -ForegroundColor Green
    } catch {
        Write-Host "  ERROR: $(Split-Path $InputPath -Leaf): $_" -ForegroundColor Red
        if (Test-Path "$InputPath.tmp") { Remove-Item "$InputPath.tmp" -Force }
    }
}

foreach ($img in $newRecent) { Compress-Image -InputPath $img.FullName }
foreach ($img in $newShowcase) { Compress-Image -InputPath $img.FullName }

# ============================================================
# STEP 3: Add new entries to projects.js
# ============================================================
Write-Host ""
Write-Host "--- Adding to projects.js ---" -ForegroundColor Cyan

function Get-TitleFromFilename {
    param([string]$Filename)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Filename)
    # Clean up common patterns
    $name = $name -replace '_', ' '
    $name = $name -replace ' copy$', ''
    $name = $name -replace ' \(\d+\)$', ''
    # Title case
    $words = $name -split ' '
    $titled = ($words | ForEach-Object {
        if ($_.Length -gt 0) {
            $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower()
        }
    }) -join ' '
    return $titled
}

$newEntries = @()

foreach ($img in $newRecent) {
    $title = Get-TitleFromFilename $img.Name
    $entry = "    {`n        title: `"$title`",`n        category: `"Graphic Design`",`n        image: `"works/recent/$($img.Name)`",`n        isRecent: true,`n        isFeatured: false`n    }"
    $newEntries += $entry
    Write-Host "  + [RECENT] $title" -ForegroundColor Green
}

foreach ($img in $newShowcase) {
    $title = Get-TitleFromFilename $img.Name
    $entry = "    {`n        title: `"$title`",`n        category: `"Graphic Design`",`n        image: `"works/showcase/$($img.Name)`",`n        isRecent: false,`n        isFeatured: true,`n        featuredCategory: `"Graphic Design`"`n    }"
    $newEntries += $entry
    Write-Host "  + [SHOWCASE] $title" -ForegroundColor Green
}

if ($newEntries.Count -gt 0) {
    # Insert new entries before the closing ];
    $joined = ($newEntries -join ",`n") + ","
    $projectsContent = $projectsContent -replace '\];(\s*)$', "$joined`n];`$1"
    Set-Content -Path $ProjectsFile -Value $projectsContent -NoNewline
    Write-Host ""
    Write-Host "$($newEntries.Count) project(s) added to projects.js!" -ForegroundColor Green
}

# ============================================================
# STEP 4: Push to GitHub
# ============================================================
Write-Host ""
Write-Host "--- Pushing to GitHub ---" -ForegroundColor Cyan

Set-Location $ProjectRoot
git add .
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
git commit -m "Added $totalNew new project(s) - $timestamp"
git push origin main

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Done! $totalNew new work(s) published! " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Read-Host "Press Enter to exit"
