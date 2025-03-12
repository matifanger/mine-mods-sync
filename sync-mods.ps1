# Configuration file path
$configPath = Join-Path $PSScriptRoot "sync-config.json"

#####################################################
# START CONFIGURATION
$DEV_URL = "http://localhost:8000" # Local server url for testing
$PROD_URL = "YOUR SERVER URL" # Your app.py server url
$READ_ONLY = $true # Switch to disable upload (use true for download only, not sync the mods to the server)
$FORCE_PROD = $false # Switch to force production mode (use true when not testing)
# END CONFIGURATION
#####################################################

# (DO NOT EDIT BELOW THIS LINE)
# (DO NOT EDIT BELOW THIS LINE)
# (DO NOT EDIT BELOW THIS LINE)

if (-not $PROD_URL) {
    throw "SYNC_SERVER_URL environment variable is required for production mode"
}

# Function to load or create config
function Get-SyncConfig {
    try {
        if (Test-Path $configPath) {
            $config = Get-Content $configPath | ConvertFrom-Json
            # Ensure properties exist
            if (-not (Get-Member -InputObject $config -Name "modsPath")) {
                Add-Member -InputObject $config -MemberType NoteProperty -Name "modsPath" -Value ""
            }
            if (-not (Get-Member -InputObject $config -Name "isDev")) {
                Add-Member -InputObject $config -MemberType NoteProperty -Name "isDev" -Value (-not $FORCE_PROD)
            }
        } else {
            $config = [PSCustomObject]@{
                modsPath = ""
                isDev = (-not $FORCE_PROD)
            }
        }
        
        # Ask for mods path
        $defaultPath = if ($config.modsPath) { 
            $config.modsPath 
        } else { 
            Join-Path $env:APPDATA ".minecraft\mods"
        }
        
        Write-Host "Current mods path: [$defaultPath]"
        $modsPath = Read-Host "Enter mods path (press Enter to keep current)"
        
        if ([string]::IsNullOrWhiteSpace($modsPath)) {
            $modsPath = $defaultPath
        }
        
        # Ask for environment only if not forced to production
        if (-not $FORCE_PROD) {
            $isDev = if ($config.isDev) { "y" } else { "n" }
            $devMode = Read-Host "Development mode? (y/N) [$isDev]"
            
            if ([string]::IsNullOrWhiteSpace($devMode)) {
                $devMode = $isDev
            }
            
            $config.isDev = $devMode -eq "y"
        } else {
            $config.isDev = $false
        }
        
        $config.modsPath = $modsPath
        
        # Save config
        $config | ConvertTo-Json | Set-Content $configPath -Force
        
        return $config
    }
    catch {
        Write-Host "Error handling configuration: $_" -ForegroundColor Red
        throw
    }
}

# Function to download a file
function Download-File {
    param (
        [string]$url,
        [string]$outFile
    )
    
    try {
        Invoke-WebRequest -Uri $url -OutFile $outFile
        Write-Host "Downloaded: $outFile" -ForegroundColor Green
    } catch {
        Write-Host "Failed to download: $outFile" -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
}

# Main sync function
function Sync-Mods {
    param (
        [string]$modsPath,
        [bool]$isDev,
        [switch]$upload
    )
    
    $serverUrl = if ($isDev) { $DEV_URL } else { $PROD_URL }
    
    # Create mods directory if it doesn't exist
    if (-not (Test-Path $modsPath)) {
        New-Item -ItemType Directory -Path $modsPath
        Write-Host "Created mods directory: $modsPath" -ForegroundColor Yellow
    }
    
    if ($upload) {
        # Upload and sync all local mods
        try {
            Write-Host "Preparing to sync mods with server..." -ForegroundColor Cyan
            
            # Get all local mods
            $localMods = Get-ChildItem -Path $modsPath -Filter "*.jar"
            
            if ($localMods.Count -eq 0) {
                Write-Host "No mods found in local directory" -ForegroundColor Yellow
                return
            }
            
            Write-Host "Found $($localMods.Count) local mods" -ForegroundColor Cyan
            
            # Get server mods first
            $serverMods = Invoke-RestMethod -Uri "$serverUrl/mods" -Method Get
            $serverModsDict = @{}
            foreach ($mod in $serverMods) {
                $serverModsDict[$mod.name] = $mod
            }

            # Find which mods are new (for logging)
            $newMods = $localMods | Where-Object {
                -not $serverModsDict.ContainsKey($_.Name)
            }

            if ($newMods.Count -gt 0) {
                Write-Host "`nFound $($newMods.Count) new mods to upload..." -ForegroundColor Cyan
            }

            $uploadedCount = 0
            $failedCount = 0
            $maxRetries = 3

            foreach ($mod in $localMods) {
                $retryCount = 0
                $success = $false

                while (-not $success -and $retryCount -lt $maxRetries) {
                    try {
                        Write-Host "Uploading: $($mod.Name)" -ForegroundColor $(if (-not $serverModsDict.ContainsKey($mod.Name)) { "Yellow" } else { "Gray" })
                        
                        $fileBytes = [System.IO.File]::ReadAllBytes($mod.FullName)
                        $fileContent = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetString($fileBytes)
                        
                        $boundary = [System.Guid]::NewGuid().ToString()
                        $LF = "`r`n"
                        $bodyLines = New-Object System.Collections.ArrayList
                        
                        [void]$bodyLines.Add("--$boundary")
                        [void]$bodyLines.Add("Content-Disposition: form-data; name=`"file`"; filename=`"$($mod.Name)`"")
                        [void]$bodyLines.Add("Content-Type: application/java-archive$LF")
                        [void]$bodyLines.Add($fileContent)
                        [void]$bodyLines.Add("--$boundary--$LF")

                        $response = Invoke-RestMethod -Uri "$serverUrl/mods/upload" `
                            -Method Post `
                            -ContentType "multipart/form-data; boundary=$boundary" `
                            -Body ($bodyLines -join $LF) `
                            -TimeoutSec 0

                        $uploadedCount++
                        $success = $true
                        Write-Host "  Success!" -ForegroundColor Green
                    } catch {
                        $retryCount++
                        if ($retryCount -lt $maxRetries) {
                            Write-Host "  Retry $retryCount/$maxRetries..." -ForegroundColor Yellow
                            Start-Sleep -Seconds 2
                        } else {
                            Write-Host "  Failed to upload after $maxRetries attempts" -ForegroundColor Red
                            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
                            $failedCount++
                        }
                    }
                }
            }

            Write-Host "`nSync completed!" -ForegroundColor Green
            Write-Host "Successfully uploaded: $uploadedCount mods" -ForegroundColor Green
            if ($failedCount -gt 0) {
                Write-Host "Failed to upload: $failedCount mods" -ForegroundColor Red
            }
            
        } catch {
            Write-Host "Failed to sync mods with server" -ForegroundColor Red
            Write-Host $_.Exception.Message
        }
    } else {
        # Download mods from server
        try {
            Write-Host "Connecting to $serverUrl..." -ForegroundColor Cyan
            $serverMods = Invoke-RestMethod -Uri "$serverUrl/mods" -Method Get
            
            if ($serverMods.Count -eq 0) {
                Write-Host "No mods found on server" -ForegroundColor Yellow
                return
            }
            
            Write-Host "Found $($serverMods.Count) mods on server" -ForegroundColor Cyan
            
            # Get local mods
            $localMods = @{}
            Get-ChildItem -Path $modsPath -Filter "*.jar" | ForEach-Object {
                $localMods[$_.Name] = $_
            }
            
            # Track mods to keep
            $modsToKeep = @{}
            
            # Download new/updated mods
            foreach ($mod in $serverMods) {
                $modPath = Join-Path $modsPath $mod.name
                $needsUpdate = $false
                $modsToKeep[$mod.name] = $true
                
                if (-not $localMods.ContainsKey($mod.name)) {
                    $needsUpdate = $true
                } elseif ($localMods[$mod.name].LastWriteTime.ToFileTimeUtc() -lt $mod.modified) {
                    $needsUpdate = $true
                }
                
                if ($needsUpdate) {
                    Write-Host "Downloading: $($mod.name)"
                    Download-File -url "$serverUrl/mods/$($mod.name)" -outFile $modPath
                } else {
                    Write-Host "Keeping: $($mod.name)" -ForegroundColor Green
                }
            }
            
            # Delete local mods that don't exist on server
            foreach ($localMod in $localMods.Keys) {
                if (-not $modsToKeep.ContainsKey($localMod)) {
                    $modPath = Join-Path $modsPath $localMod
                    Write-Host "Removing: $localMod" -ForegroundColor Yellow
                    Remove-Item -Path $modPath -Force
                }
            }
            
            Write-Host "Sync completed!" -ForegroundColor Green
        } catch {
            Write-Host "Failed to get mod list from server" -ForegroundColor Red
            Write-Host $_.Exception.Message
        }
    }
}

# Main script
$config = Get-SyncConfig

Write-Host "`nUsing configuration:" -ForegroundColor Cyan
Write-Host "Mods Path: $($config.modsPath)" -ForegroundColor Cyan
Write-Host "Environment: $(if ($config.isDev) { 'Development' } else { 'Production' })" -ForegroundColor Cyan
Write-Host "Server URL: $(if ($config.isDev) { $DEV_URL } else { $PROD_URL })`n" -ForegroundColor Cyan

if ($READ_ONLY) {
    Write-Host "Mode: Read-only (download only)" -ForegroundColor Yellow
    Write-Host "`nDownloading mods from server..."
    Sync-Mods -modsPath $config.modsPath -isDev $config.isDev
} else {
    Write-Host "Select an action:" -ForegroundColor Yellow
    Write-Host "1. Download mods from server"
    Write-Host "2. Upload my mods to server"
    $choice = Read-Host "`nEnter your choice (1-2)"

    switch ($choice) {
        "2" { 
            Sync-Mods -modsPath $config.modsPath -isDev $config.isDev -upload 
        }
        default { 
            Sync-Mods -modsPath $config.modsPath -isDev $config.isDev 
        }
    }
} 