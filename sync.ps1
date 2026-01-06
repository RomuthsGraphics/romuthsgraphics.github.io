$Path = "E:\WEB AND APP DEVELOPMENT\WebSites\Romuths Graphic Designing"
$Filter = "*.*"

$Watcher = New-Object IO.FileSystemWatcher
$Watcher.Path = $Path
$Watcher.Filter = $Filter
$Watcher.IncludeSubdirectories = $true
$Watcher.EnableRaisingEvents = $true

$Action = {
    $Path = $Event.SourceEventArgs.FullPath
    $ChangeType = $Event.SourceEventArgs.ChangeType
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Ignore the .git folder and the sync scripts themselves
    if ($Path -like "*\.git\*" -or $Path -like "*\sync.ps1" -or $Path -like "*\StartSync.bat") {
        return
    }

    Write-Host "[$Timestamp] Change detected: $ChangeType - $Path" -ForegroundColor Cyan
    
    try {
        Set-Location "E:\WEB AND APP DEVELOPMENT\WebSites\Romuths Graphic Designing"
        git add .
        git commit -m "Auto-sync: $Timestamp"
        git push origin master
        Write-Host "[$Timestamp] Successfully pushed to GitHub!" -ForegroundColor Green
    } catch {
        Write-Host "[$Timestamp] Error syncing to GitHub: $_" -ForegroundColor Red
    }
}

Register-ObjectEvent $Watcher "Changed" -Action $Action
Register-ObjectEvent $Watcher "Created" -Action $Action
Register-ObjectEvent $Watcher "Deleted" -Action $Action
Register-ObjectEvent $Watcher "Renamed" -Action $Action

Write-Host "Monitoring $Path for changes... Press Ctrl+C to stop." -ForegroundColor Yellow

while ($true) {
    Start-Sleep -Seconds 5
}
