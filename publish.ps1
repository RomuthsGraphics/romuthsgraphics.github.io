Add-Type -AssemblyName System.Drawing

$ProjectRoot = "E:\WEB AND APP DEVELOPMENT\WebSites\Romuths Graphic Designing"
$ProjectsFile = Join-Path $ProjectRoot "projects.js"

Set-Location $ProjectRoot

# Fix git safe directory (prevents ownership errors)
git config --global --add safe.directory 'E:/WEB AND APP DEVELOPMENT/WebSites/Romuths Graphic Designing' 2>$null

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Romuths Graphics - Publish New Works  " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# STEP 1: Find new images not yet in projects.js
# ============================================================
$projectsContent = Get-Content $ProjectsFile -Raw

$recentImages = Get-ChildItem "$ProjectRoot\works\recent" -File | Where-Object { $_.Extension -match '\.(jpg|jpeg|png|webp)$' }
$showcaseImages = Get-ChildItem "$ProjectRoot\works\showcase" -File | Where-Object { $_.Extension -match '\.(jpg|jpeg|png|webp)$' }

$newRecent = @()
$newShowcase = @()

foreach ($img in $recentImages) {
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
    Write-Host "No new images found. Checking if there are unpushed changes..." -ForegroundColor Yellow

    $unpushed = git status --short
    if ($unpushed) {
        Write-Host "Found unpushed changes. Pushing to GitHub..." -ForegroundColor Cyan
        git add .
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        git commit -m "Sync update - $timestamp"
        git push origin main
        Write-Host ""
        Write-Host "Pushed successfully!" -ForegroundColor Green
    } else {
        Write-Host "Everything is up to date!" -ForegroundColor Green
    }
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
Write-Host "--- Step 1/3: Compressing images ---" -ForegroundColor Cyan

function Compress-Image {
    param([string]$InputPath, [int]$MaxWidth = 1920, [int]$Quality = 65)
    try {
        $originalSize = (Get-Item $InputPath).Length
        if ($originalSize -lt 500KB) {
            Write-Host "  SKIP (already small): $(Split-Path $InputPath -Leaf)" -ForegroundColor DarkGray
            return
        }
        $img = [System.Drawing.Image]::FromFile($InputPath)
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
Write-Host "--- Step 2/3: Adding to projects.js ---" -ForegroundColor Cyan

function Get-TitleFromFilename {
    param([string]$Filename)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Filename)
    $name = $name -replace '_', ' '
    $name = $name -replace ' copy$', ''
    $name = $name -replace ' \(\d+\)$', ''
    $words = $name -split ' '
    $titled = ($words | ForEach-Object {
        if ($_.Length -gt 0) { $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower() }
    }) -join ' '
    return $titled
}

# Re-read the file in case it changed
$projectsContent = Get-Content $ProjectsFile -Raw
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
    $joined = ($newEntries -join ",`n") + ","
    $projectsContent = $projectsContent -replace '\];(\s*)$', "$joined`n];`$1"
    Set-Content -Path $ProjectsFile -Value $projectsContent -NoNewline
    Write-Host ""
    Write-Host "$($newEntries.Count) project(s) added to projects.js!" -ForegroundColor Green
}

# ============================================================
# STEP 4: Push everything to GitHub
# ============================================================
Write-Host ""
Write-Host "--- Step 3/3: Pushing to GitHub ---" -ForegroundColor Cyan

git add .
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
git commit -m "Added $totalNew new project(s) - $timestamp"
git push origin main

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  SUCCESS! $totalNew new work(s) published!" -ForegroundColor Green
    Write-Host "  Live at: https://romuthsgraphics.github.io/" -ForegroundColor Green
    Write-Host "  (Wait 1-2 minutes for GitHub to update)" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "  Push failed! Check your internet connection." -ForegroundColor Red
    Write-Host "  You can try again by double-clicking Publish.bat" -ForegroundColor Yellow
}

Write-Host ""
Read-Host "Press Enter to exit"
