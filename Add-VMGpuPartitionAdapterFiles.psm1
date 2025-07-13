Function Add-VMGpuPartitionAdapterFiles {
    param(
    [string]$hostname = $ENV:COMPUTERNAME,
    [string]$DriveLetter,
    [string]$GPUName
    )
    
    # Initialize array to track failed file copies
    $FailedFiles = @()
    
    If (!($DriveLetter -like "*:*")) {
        $DriveLetter = $Driveletter + ":"
        }
    
    If ($GPUName -eq "AUTO") {
        $PartitionableGPUList = Get-WmiObject -Class "Msvm_PartitionableGpu" -ComputerName $env:COMPUTERNAME -Namespace "ROOT\virtualization\v2"
        $DevicePathName = $PartitionableGPUList.Name | Select-Object -First 1
        $GPU = Get-PnpDevice | Where-Object {($_.DeviceID -like "*$($DevicePathName.Substring(8,16))*") -and ($_.Status -eq "OK")} | Select-Object -First 1
        $GPUName = $GPU.Friendlyname
        $GPUServiceName = $GPU.Service 
        }
    Else {
        $GPU = Get-PnpDevice | Where-Object {($_.Name -eq "$GPUName") -and ($_.Status -eq "OK")} | Select-Object -First 1
        $GPUServiceName = $GPU.Service
        }
    # Get Third Party drivers used, that are not provided by Microsoft and presumably included in the OS
    
    Write-Host "INFO   : Finding and copying driver files for $GPUName to VM. This could take a while..."
    
    $Drivers = Get-WmiObject Win32_PNPSignedDriver | where {$_.DeviceName -eq "$GPUName"}
    
    New-Item -ItemType Directory -Path "$DriveLetter\windows\system32\HostDriverStore" -Force | Out-Null
    
    #copy directory associated with sys file 
    $servicePath = (Get-WmiObject Win32_SystemDriver | Where-Object {$_.Name -eq "$GPUServiceName"}).Pathname
                    $ServiceDriverDir = $servicepath.split('\')[0..5] -join('\')
                    $ServicedriverDest = ("$driveletter" + "\" + $($servicepath.split('\')[1..5] -join('\'))).Replace("DriverStore","HostDriverStore")
                    if (!(Test-Path $ServicedriverDest)) {
                    Copy-item -path "$ServiceDriverDir" -Destination "$ServicedriverDest" -Recurse
                    }
    
    # Initialize the list of detected driver packages as an array
    $DriverFolders = @()
    foreach ($d in $drivers) {
    
        $DriverFiles = @()
        $ModifiedDeviceID = $d.DeviceID -replace "\\", "\\"
        $Antecedent = "\\" + $hostname + "\ROOT\cimv2:Win32_PNPSignedDriver.DeviceID=""$ModifiedDeviceID"""
        $DriverFiles += Get-WmiObject Win32_PNPSignedDriverCIMDataFile | where {$_.Antecedent -eq $Antecedent}
        $DriverName = $d.DeviceName
        $DriverID = $d.DeviceID
        if ($DriverName -like "NVIDIA*") {
            New-Item -ItemType Directory -Path "$driveletter\Windows\System32\drivers\Nvidia Corporation\" -Force | Out-Null
            }
        foreach ($i in $DriverFiles) {
                $path = $i.Dependent.Split("=")[1] -replace '\\\\', '\'
                $path2 = $path.Substring(1,$path.Length-2)
                $InfItem = Get-Item -Path $path2
                $Version = $InfItem.VersionInfo.FileVersion
                If ($path2 -like "c:\windows\system32\driverstore\*") {
                    $DriverDir = $path2.split('\')[0..5] -join('\')
                    $driverDest = ("$driveletter" + "\" + $($path2.split('\')[1..5] -join('\'))).Replace("driverstore","HostDriverStore")
                    if (!(Test-Path $driverDest)) {
                    Copy-item -path "$DriverDir" -Destination "$driverDest" -Recurse
                    }
                }
                Else {
                    $ParseDestination = $path2.Replace("c:", "$driveletter")
                    $Destination = $ParseDestination.Substring(0, $ParseDestination.LastIndexOf('\'))
                    if (!$(Test-Path -Path $Destination)) {
                        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
                        }
                    
                    # Enhanced file copying with better error handling and permission management
                    $FileName = Split-Path $path2 -Leaf
                    $DestinationFile = Join-Path $Destination $FileName
                    
                    try {
                        # First attempt: Standard copy with force
                        Copy-Item $path2 -Destination $Destination -Force -ErrorAction Stop
                        Write-Host "SUCCESS: Copied $FileName to $Destination"
                    }
                    catch [System.UnauthorizedAccessException] {
                        Write-Host "WARNING: Access denied for $FileName, trying alternative method..."
                        try {
                            # Second attempt: Use robocopy for system files that may be locked
                            $robocopySource = Split-Path $path2 -Parent
                            $robocopyResult = Start-Process -FilePath "robocopy.exe" -ArgumentList "`"$robocopySource`" `"$Destination`" `"$FileName`" /R:3 /W:1 /NFL /NDL /NJH /NJS" -Wait -PassThru -WindowStyle Hidden
                            
                            if ($robocopyResult.ExitCode -le 1) {
                                Write-Host "SUCCESS: Used robocopy to copy $FileName"
                            } else {
                                $exitCode = $robocopyResult.ExitCode
                                Write-Host "WARNING: Robocopy failed for $FileName (Exit Code: $exitCode)"
                                # Third attempt: Try to take ownership and copy using icacls method
                                try {
                                    Write-Host "INFO: Attempting to take ownership of $FileName..."
                                    # Take ownership of source file
                                    $takeownResult = Start-Process -FilePath "takeown.exe" -ArgumentList "/f `"$path2`"" -Wait -PassThru -WindowStyle Hidden
                                    # Grant full permissions to current user
                                    $currentUser = $env:USERNAME
                                    $icaclsResult = Start-Process -FilePath "icacls.exe" -ArgumentList "`"$path2`" /grant `"$currentUser`:F`"" -Wait -PassThru -WindowStyle Hidden
                                    # Use copy command instead of Copy-Item for better compatibility
                                    $copyResult = Start-Process -FilePath "cmd.exe" -ArgumentList "/c copy `"$path2`" `"$DestinationFile`"" -Wait -PassThru -WindowStyle Hidden
                                    
                                    if ($copyResult.ExitCode -eq 0) {
                                        Write-Host "SUCCESS: Copied $FileName after taking ownership using copy command"
                                    } else {
                                        throw "Copy command failed with exit code: $($copyResult.ExitCode)"
                                    }
                                }
                                catch {
                                    $errorMessage = $_.Exception.Message
                                    Write-Host "ERROR: Failed to copy $FileName after all attempts: $errorMessage"
                                    Write-Host "INFO: Skipping $FileName - this may not be critical for VM operation"
                                    $FailedFiles += @{
                                        SourcePath = $path2
                                        DestinationPath = $DestinationFile
                                        FileName = $FileName
                                    }
                                }
                            }
                        }
                        catch {
                            $errorMessage = $_.Exception.Message
                            Write-Host "ERROR: Alternative copy method failed for $FileName - $errorMessage"
                            Write-Host "INFO: Skipping $FileName - this may not be critical for VM operation"
                            $FailedFiles += @{
                                SourcePath = $path2
                                DestinationPath = $DestinationFile
                                FileName = $FileName
                            }
                        }
                    }
                    catch {
                        $errorMessage = $_.Exception.Message
                        Write-Host "ERROR: Unexpected error copying $FileName - $errorMessage"
                        Write-Host "INFO: Skipping $FileName - this may not be critical for VM operation"
                        $FailedFiles += @{
                            SourcePath = $path2
                            DestinationPath = $DestinationFile
                            FileName = $FileName
                        }
                    }
                }
        }
        }
    
    # Handle failed files summary and manual copy request
    if ($FailedFiles.Count -gt 0) {
        Write-Host ""
        Write-Host "============================================" -ForegroundColor Yellow
        Write-Host "SUMMARY: $($FailedFiles.Count) files failed to copy automatically" -ForegroundColor Yellow
        Write-Host "============================================" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Failed files that need manual copying:" -ForegroundColor Red
        foreach ($file in $FailedFiles) {
            Write-Host "  $($file.FileName): $($file.SourcePath) -> $($file.DestinationPath)" -ForegroundColor White
        }
        Write-Host ""
        Write-Host "Waiting 1 minute before opening file explorer..." -ForegroundColor Cyan
        Start-Sleep -Seconds 60
        
        # Open explorer to the source drivers folder and destination folder
        $sourceFolder = Split-Path $FailedFiles[0].SourcePath -Parent
        $destFolder = Split-Path $FailedFiles[0].DestinationPath -Parent
        Write-Host "Opening source folder: $sourceFolder" -ForegroundColor Green
        Start-Process "explorer.exe" -ArgumentList $sourceFolder
        Start-Sleep -Seconds 2
        Write-Host "Opening destination folder: $destFolder" -ForegroundColor Green
        Start-Process "explorer.exe" -ArgumentList $destFolder
        
        Write-Host ""
        Write-Host "Please manually copy the failed files from source to destination folders." -ForegroundColor Yellow
        Write-Host "Files to copy:" -ForegroundColor White
        foreach ($file in $FailedFiles) {
            Write-Host "  Copy: $($file.FileName)" -ForegroundColor White
            Write-Host "  From: $($file.SourcePath)" -ForegroundColor Gray
            Write-Host "  To:   $($file.DestinationPath)" -ForegroundColor Gray
            Write-Host ""
        }
        
        # Wait for user confirmation
        do {
            $confirmation = Read-Host "Have you completed the manual file copying? Type 'yes' to continue"
        } while ($confirmation -ne "yes")
        
        Write-Host "Manual copying confirmed. Continuing with next steps..." -ForegroundColor Green
    } else {
        Write-Host "SUCCESS: All files copied successfully!" -ForegroundColor Green
    }
    
    }