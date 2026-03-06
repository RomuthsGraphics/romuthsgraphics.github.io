Add-Type -AssemblyName System.Drawing

$ProjectRoot = "E:\WEB AND APP DEVELOPMENT\WebSites\Romuths Graphic Designing"
$ProjectsFile = Join-Path $ProjectRoot "projects.js"

Set-Location $ProjectRoot

# Fix git safe directory
git config --global --add safe.directory 'E:/WEB AND APP DEVELOPMENT/WebSites/Romuths Graphic Designing' 2>$null

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Romuths Graphics - Publish New Works  " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Define folders and their display categories
$categoryMap = @{
    "recent"       = @{ Name = "Graphic Design"; IsRecent = $true; IsFeatured = $false }
    "showcase"     = @{ Name = "Graphic Design"; IsRecent = $false; IsFeatured = $true }
    "branding"     = @{ Name = "Logo Design & Branding"; IsRecent = $false; IsFeatured = $false }
    "ui-ux"        = @{ Name = "Web & UI/UX Design"; IsRecent = $false; IsFeatured = $false }
    "print"        = @{ Name = "Print Design"; IsRecent = $false; IsFeatured = $false }
    "illustration" = @{ Name = "Illustration"; IsRecent = $false; IsFeatured = $false }
    "packaging"    = @{ Name = "Packaging Design"; IsRecent = $false; IsFeatured = $false }
    "marketing"    = @{ Name = "Marketing Materials"; IsRecent = $false; IsFeatured = $false }
}

# ============================================================
# STEP 1: Compress uncompressed images first
# ============================================================
Write-Host "--- Step 1/3: Checking for uncompressed images ---" -ForegroundColor Cyan

function Compress-Image {
    param([string]$InputPath, [int]$MaxWidth = 1920, [int]$Quality = 65)
    try {
        $originalSize = (Get-Item $InputPath).Length
        if ($originalSize -lt 600KB) { return } # Skip already small files
        
        Write-Host "  Compressing: $(Split-Path $InputPath -Leaf)..." -NoNewline
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
        Write-Host " OK ($([math]::Round($originalSize/1KB,0))KB -> $([math]::Round($nz/1KB,0))KB)" -ForegroundColor Green
    } catch {
        Write-Host " ERROR: $_" -ForegroundColor Red
        if (Test-Path "$InputPath.tmp") { Remove-Item "$InputPath.tmp" -Force }
    }
}

foreach ($folder in $categoryMap.Keys) {
    if (Test-Path "$ProjectRoot\works\$folder") {
        Get-ChildItem "$ProjectRoot\works\$folder" -File | Where-Object { $_.Extension -match '\.(jpg|jpeg|png|webp)$' } | ForEach-Object {
            Compress-Image -InputPath $_.FullName
        }
    }
}

# ============================================================
# STEP 2: Rebuild projects.js with dimensions
# ============================================================
Write-Host ""
Write-Host "--- Step 2/3: Generating projects.js with dimensions ---" -ForegroundColor Cyan

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

$allProjects = @()

foreach ($folder in $categoryMap.Keys) {
    if (-not (Test-Path "$ProjectRoot\works\$folder")) { continue }
    
    $images = Get-ChildItem "$ProjectRoot\works\$folder" -File | Where-Object { $_.Extension -match '\.(jpg|jpeg|png|webp)$' }
    if ($images.Count -gt 0) { Write-Host "  Found $($images.Count) image(s) in works/$folder/" -ForegroundColor Gray }

    foreach ($img in $images) {
        try {
            # Get dimensions
            $bmp = New-Object System.Drawing.Bitmap($img.FullName)
            $width = $bmp.Width
            $height = $bmp.Height
            $bmp.Dispose()

            $title = Get-TitleFromFilename $img.Name
            $catData = $categoryMap[$folder]

            # Replace backslashes with forward slashes for webpaths
            $webPath = "works/$folder/$($img.Name)" -replace "\\", "/"
            
            $isRecent = if ($catData.IsRecent) { "true" } else { "false" }
            $isFeatured = if ($catData.IsFeatured) { "true" } else { "false" }
            
            # Format object
            $entry = @"
    {
        title: "$title",
        category: "$($catData.Name)",
        folder: "$folder",
        image: "$webPath",
        width: $width,
        height: $height,
        isRecent: $isRecent,
        isFeatured: $isFeatured,
        featuredCategory: "$($catData.Name)"
    }
"@
            $allProjects += $entry
        } catch {
            Write-Host "  Error processing $($img.Name): $_" -ForegroundColor Red
        }
    }
}

$jsContent = "// Auto-generated by publish.ps1`nconst portfolioProjects = [`n" + ($allProjects -join ",`n") + "`n];`n"
Set-Content -Path $ProjectsFile -Value $jsContent -Encoding UTF8
Write-Host "  Successfully wrote $($allProjects.Count) projects to projects.js!" -ForegroundColor Green

# ============================================================
# STEP 3: Push everything to GitHub
# ============================================================
Write-Host ""
Write-Host "--- Step 3/3: Syncing and Pushing to GitHub ---" -ForegroundColor Cyan

$status = git status --short
if (-not $status) {
    Write-Host "  Everything is up to date! No changes to push." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit
}

git add .
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
git commit -m "Auto-publish new works - $timestamp"
git push origin main

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  SUCCESS! Website updated!" -ForegroundColor Green
    Write-Host "  Live at: https://romuthsgraphics.github.io/" -ForegroundColor Green
    Write-Host "  (Wait 1-2 minutes for GitHub to rebuild)" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "  Push failed! Check your internet connection." -ForegroundColor Red
    Write-Host "  You can try again by double-clicking Publish.bat" -ForegroundColor Yellow
}

Write-Host ""
Read-Host "Press Enter to exit"
