# Git Auto Push Script
# Changes to current directory, sets remote, commits with timestamp, and pushes

# Change to script directory
Set-Location -Path $PSScriptRoot
Write-Host "Working directory changed to: $(Get-Location)" -ForegroundColor Green

# Set git remote origin
Write-Host "Setting git remote origin..." -ForegroundColor Yellow
try {
    # Remove existing remote if exists
    git remote remove origin 2>$null
    # Add new remote
    git remote add origin git@github.com:accountbelongstox/Easy-GPU-PV.git
    Write-Host "Git remote origin set to: git@github.com:accountbelongstox/Easy-GPU-PV.git" -ForegroundColor Green
}
catch {
    Write-Host "Warning: Failed to set remote origin - $($_.Exception.Message)" -ForegroundColor Red
}

# Add all files
Write-Host "Adding all files to git..." -ForegroundColor Yellow
git add .
Write-Host "Files added successfully" -ForegroundColor Green

# Create commit with timestamp
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$commitMessage = "Auto commit - $timestamp"
Write-Host "Creating commit with message: $commitMessage" -ForegroundColor Yellow
git commit -m $commitMessage

# Check if commit was successful
if ($LASTEXITCODE -eq 0) {
    Write-Host "Commit created successfully" -ForegroundColor Green
    
    # Push with confirmation
    Write-Host ""
    Write-Host "Ready to push to remote repository..." -ForegroundColor Cyan
    Write-Host "Press 'Y' within 5 seconds to force push, or any other key to cancel" -ForegroundColor Yellow
    
    # 5-second timeout for user input
    $timeout = 5
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $keyPressed = $false
    $choice = ""
    
    while ($timer.Elapsed.TotalSeconds -lt $timeout -and -not $keyPressed) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            $choice = $key.KeyChar.ToString().ToUpper()
            $keyPressed = $true
        }
        Start-Sleep -Milliseconds 100
    }
    
    $timer.Stop()
    
    if (-not $keyPressed) {
        Write-Host "No input received within 5 seconds, defaulting to force push..." -ForegroundColor Yellow
        $choice = "Y"
    }
    
    if ($choice -eq "Y") {
        Write-Host "Force pushing to remote repository..." -ForegroundColor Red
        git push origin main --force
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Successfully pushed to remote repository!" -ForegroundColor Green
        } else {
            Write-Host "Failed to push to remote repository" -ForegroundColor Red
            Write-Host "Trying to push to master branch..." -ForegroundColor Yellow
            git push origin master --force
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Successfully pushed to master branch!" -ForegroundColor Green
            } else {
                Write-Host "Failed to push to both main and master branches" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "Push cancelled by user" -ForegroundColor Yellow
    }
} else {
    Write-Host "Commit failed - nothing to commit or error occurred" -ForegroundColor Red
}

Write-Host ""
Write-Host "Git auto push script completed" -ForegroundColor Cyan
