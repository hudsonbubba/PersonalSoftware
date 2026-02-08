# Video Clip Processing Script
# Processes MP4 clips: deletes short clips, trims long clips, adds chirons, and concatenates into 30-second exports

param(
    [string]$Directory = (Get-Location).Path,
    [switch]$AutoAccept
)

# Color coding for output
function Write-Success { param($Message) Write-Host $Message -ForegroundColor Green }
function Write-Info { param($Message) Write-Host $Message -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host $Message -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host $Message -ForegroundColor Red }

# Initialize error log
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$errorLogPath = Join-Path $Directory "error_log_$timestamp.txt"
$exportDir = Join-Path $Directory "Exports_$timestamp"

function Write-ErrorLog {
    param($Message)
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Add-Content -Path $errorLogPath -Value $logMessage
    Write-Error $Message
}

# Check for FFmpeg
function Test-FFmpeg {
    Write-Info "Checking for FFmpeg installation..."
    try {
        $ffmpegVersion = & ffmpeg -version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "[OK] FFmpeg is installed and accessible"
            return $true
        }
    } catch {
        Write-Error "[X] FFmpeg is not installed or not in PATH"
        Write-Host ""
        Write-Host "Please install FFmpeg:" -ForegroundColor Yellow
        Write-Host "1. Download from: https://www.gyan.dev/ffmpeg/builds/" -ForegroundColor White
        Write-Host "2. Extract the archive" -ForegroundColor White
        Write-Host "3. Add the 'bin' folder to your system PATH" -ForegroundColor White
        Write-Host "4. Restart PowerShell and try again" -ForegroundColor White
        Write-Host ""
        Write-Host "Alternative: Use Chocolatey package manager:" -ForegroundColor Yellow
        Write-Host "   choco install ffmpeg" -ForegroundColor White
        return $false
    }
}

# Get video duration in seconds
function Get-VideoDuration {
    param($FilePath)
    try {
        $output = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$FilePath" 2>$null
        return [double]$output
    } catch {
        return -1
    }
}

# Get video frame rate
function Get-VideoFrameRate {
    param($FilePath)
    try {
        $output = & ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$FilePath" 2>$null
        if ($output -match "(\d+)/(\d+)") {
            $num = [double]$matches[1]
            $den = [double]$matches[2]
            return [math]::Round($num / $den, 2)
        }
        return -1
    } catch {
        return -1
    }
}

# Generate chiron text from filename and check if stabilization should be skipped
function Get-ChironInfo {
    param($FileName)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $skipStabilization = $false
    
    # Check if "NoStable" appears after underscore or space
    if ($baseName -match "_(.*NoStable.*)" -or $baseName -match "\s+\((.*NoStable.*)\)") {
        $skipStabilization = $true
    }
    
    # First, try to match underscore pattern (e.g., "Northern-Canada_1")
    if ($baseName -match "^(.+?)_") {
        $text = $matches[1] -replace "-", " "
        return @{
            Text = $text
            SkipStabilization = $skipStabilization
        }
    }
    
    # Then, try to match space with content in parentheses (e.g., "Northern-Canada (1)")
    if ($baseName -match "^(.+?)\s+\(") {
        $text = $matches[1] -replace "-", " "
        return @{
            Text = $text
            SkipStabilization = $skipStabilization
        }
    }
    
    # Fallback: just replace dashes with spaces
    return @{
        Text = $baseName -replace "-", " "
        SkipStabilization = $skipStabilization
    }
}

# Process a single clip (trim and add chiron)
function Process-Clip {
    param(
        [string]$InputPath,
        [string]$OutputPath,
        [double]$Duration,
        [bool]$SkipStabilization = $false
    )
    
    $chironInfo = Get-ChironInfo -FileName (Split-Path $InputPath -Leaf)
    $chironText = $chironInfo.Text
    
    # Calculate trim points for clips longer than 10 seconds
    $startTime = 0
    if ($Duration -gt 10) {
        $trimAmount = ($Duration - 10) / 2
        $startTime = $trimAmount
    }
    
    # Escape text for FFmpeg drawtext filter
    $escapedText = $chironText -replace "\\", "\\\\" -replace ":", "\\:" -replace "'", "''"
    
    # Build FFmpeg command with chiron overlay
    # Font file path - try multiple possible locations
    $possibleFonts = @(
        "C:/Windows/Fonts/OpenSans-Bold.ttf",
        "C:/Windows/Fonts/opensans-bold.ttf",
        "C:/Windows/Fonts/OpenSansBold.ttf",
        "C:/Windows/Fonts/Arial.ttf"
    )
    
    $fontFile = $null
    foreach ($font in $possibleFonts) {
        $testPath = $font -replace "/", "\"
        if (Test-Path $testPath) {
            # Use forward slashes and escape colons for FFmpeg
            $fontFile = $font -replace ":", "\\:"
            break
        }
    }
    
    if (-not $fontFile) {
        Write-ErrorLog "No suitable font found. Please install Open Sans Bold or ensure Arial is available."
        return $false
    }
    
    # Build filter chain
    # Stabilization: vidstabdetect on first pass, vidstabtransform on second pass
    # Or skip stabilization if NoStable in filename
    
    if ($SkipStabilization) {
        # No stabilization - just drawtext, scale, pad, and fps
        $drawTextFilter = "drawtext=fontfile=$fontFile`:text='$escapedText':fontcolor=white:fontsize=100:borderw=2:bordercolor=black:x=w*0.95-tw:y=h*0.95-th"
        $videoFilter = "$drawTextFilter,scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,fps=fps=60000/1001"
        
        try {
            $ffmpegArgs = @(
                "-i", "$InputPath",
                "-ss", "$startTime",
                "-t", "10",
                "-vf", "$videoFilter",
                "-c:v", "libx264",
                "-preset", "medium",
                "-crf", "23",
                "-an",
                "-y",
                "$OutputPath"
            )
            
            # Capture FFmpeg output for error logging
            $errorOutput = & ffmpeg $ffmpegArgs 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                return $true
            } else {
                $errorText = $errorOutput | Select-Object -Last 10 | Out-String
                Write-ErrorLog "FFmpeg failed processing: $(Split-Path $InputPath -Leaf)`nLast 10 lines of output:`n$errorText"
                return $false
            }
        } catch {
            Write-ErrorLog "Exception processing $(Split-Path $InputPath -Leaf): $($_.Exception.Message)"
            return $false
        }
    } else {
        # Two-pass stabilization
        # Use a simple filename in the temp directory to avoid path escaping issues
        $transformFileName = "transform_$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).trf"
        $transformFile = Join-Path $tempDir $transformFileName
        
        try {
            # First pass - detect
            # Convert Windows path to forward slashes and escape for FFmpeg
            $transformFileEscaped = $transformFile -replace "\\", "/" -replace ":", "\\:"
            
            $detectArgs = @(
                "-i", "$InputPath",
                "-ss", "$startTime",
                "-t", "10",
                "-vf", "vidstabdetect=shakiness=5:accuracy=15:result=$transformFileEscaped",
                "-f", "null",
                "-"
            )
            
            $detectOutput = & ffmpeg $detectArgs 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                $errorText = $detectOutput | Select-Object -Last 10 | Out-String
                Write-ErrorLog "FFmpeg stabilization detection failed: $(Split-Path $InputPath -Leaf)`nLast 10 lines of output:`n$errorText"
                if (Test-Path $transformFile) {
                    Remove-Item $transformFile -Force
                }
                return $false
            }
            
            # Second pass - transform with chiron, scale, pad, and fps
            $drawTextFilter = "drawtext=fontfile=$fontFile`:text='$escapedText':fontcolor=white:fontsize=100:borderw=2:bordercolor=black:x=w*0.95-tw:y=h*0.95-th"
            $videoFilter = "vidstabtransform=input=$transformFileEscaped`:zoom=0:smoothing=10,$drawTextFilter,scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,fps=fps=60000/1001"
            
            $transformArgs = @(
                "-i", "$InputPath",
                "-ss", "$startTime",
                "-t", "10",
                "-vf", "$videoFilter",
                "-c:v", "libx264",
                "-preset", "medium",
                "-crf", "23",
                "-an",
                "-y",
                "$OutputPath"
            )
            
            $transformOutput = & ffmpeg $transformArgs 2>&1
            
            # Clean up transform file
            if (Test-Path $transformFile) {
                Remove-Item $transformFile -Force
            }
            
            if ($LASTEXITCODE -eq 0) {
                return $true
            } else {
                $errorText = $transformOutput | Select-Object -Last 10 | Out-String
                Write-ErrorLog "FFmpeg stabilization transform failed: $(Split-Path $InputPath -Leaf)`nLast 10 lines of output:`n$errorText"
                return $false
            }
        } catch {
            if (Test-Path $transformFile) {
                Remove-Item $transformFile -Force
            }
            Write-ErrorLog "Exception processing $(Split-Path $InputPath -Leaf): $($_.Exception.Message)"
            return $false
        }
    }
}

# Concatenate clips into final export
function Merge-Clips {
    param(
        [array]$ClipPaths,
        [string]$OutputPath
    )
    
    # Create concat file
    $concatFile = Join-Path $Directory "concat_temp_$timestamp.txt"
    $ClipPaths | ForEach-Object {
        "file '$_'" | Add-Content -Path $concatFile
    }
    
    try {
        $ffmpegArgs = @(
            "-f", "concat",
            "-safe", "0",
            "-i", "$concatFile",
            "-c", "copy",
            "-y",
            "$OutputPath"
        )
        
        & ffmpeg $ffmpegArgs 2>&1 | Out-Null
        
        Remove-Item $concatFile -Force
        
        if ($LASTEXITCODE -eq 0) {
            return $true
        } else {
            Write-ErrorLog "FFmpeg failed merging clips for: $(Split-Path $OutputPath -Leaf)"
            return $false
        }
    } catch {
        Write-ErrorLog "Exception merging clips: $($_.Exception.Message)"
        if (Test-Path $concatFile) {
            Remove-Item $concatFile -Force
        }
        return $false
    }
}

# Main execution
Write-Host ""
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "  Video Clip Processing Script" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta
Write-Host ""

# Check FFmpeg
if (-not (Test-FFmpeg)) {
    exit 1
}

Write-Host ""
Write-Info "Working Directory: $Directory"
Write-Info "Output Directory: $exportDir"
Write-Info "Error Log: $errorLogPath"
Write-Host ""

# Get all MP4 files
$mp4Files = Get-ChildItem -Path $Directory -Filter "*.mp4" | Sort-Object Name

if ($mp4Files.Count -eq 0) {
    Write-Error "No MP4 files found in directory"
    exit 1
}

Write-Info "Found $($mp4Files.Count) MP4 files"
Write-Host ""

# Analyze all clips
Write-Info "Analyzing clips..."
$clipAnalysis = @()
$toDelete = @()
$nonStandardFPS = @()

foreach ($file in $mp4Files) {
    $duration = Get-VideoDuration -FilePath $file.FullName
    $fps = Get-VideoFrameRate -FilePath $file.FullName
    
    if ($duration -lt 0) {
        Write-ErrorLog "Could not read duration for: $($file.Name)"
        continue
    }
    
    if ($duration -lt 5) {
        $toDelete += $file
        Write-Warning "  [X] $($file.Name) - Too short ($([math]::Round($duration, 2))s) - Will be deleted"
        continue
    }
    
    # Check FPS (59.94 is represented as 60000/1001 ≈ 59.94)
    if ($fps -ne -1 -and [math]::Abs($fps - 59.94) -gt 0.1) {
        $nonStandardFPS += @{
            File = $file
            FPS = $fps
            Duration = $duration
        }
    }
    
    $clipAnalysis += @{
        File = $file
        Duration = $duration
        FPS = $fps
    }
    
    $statusSymbol = if ($duration -le 10) { "[OK]" } else { "[TRIM]" }
    Write-Host "  $statusSymbol $($file.Name) - $([math]::Round($duration, 2))s @ ${fps}fps"
}

Write-Host ""

# Handle non-standard FPS clips
if ($nonStandardFPS.Count -gt 0) {
    Write-Warning "Found $($nonStandardFPS.Count) clip(s) with non-standard frame rate:"
    foreach ($clip in $nonStandardFPS) {
        Write-Host "  - $($clip.File.Name) @ $($clip.FPS)fps" -ForegroundColor Yellow
    }
    Write-Host ""
    
    if ($AutoAccept) {
        Write-Info "Auto-accept enabled: Converting all clips to 59.94fps"
        $response = "Y"
    } else {
        $response = Read-Host "Include these clips and convert to 59.94fps? (Y/N)"
    }
    
    if ($response -notmatch "^[Yy]") {
        Write-Info "Excluding non-standard FPS clips from processing"
        $clipAnalysis = $clipAnalysis | Where-Object { 
            $file = $_.File
            $nonStandardFPS.File -notcontains $file
        }
    } else {
        Write-Info "Will convert all clips to 59.94fps"
    }
    Write-Host ""
}

# Delete short clips
if ($toDelete.Count -gt 0) {
    Write-Info "Deleting $($toDelete.Count) short clip(s)..."
    foreach ($file in $toDelete) {
        try {
            Remove-Item $file.FullName -Force
            Write-Success "  [OK] Deleted: $($file.Name)"
        } catch {
            Write-ErrorLog "Failed to delete: $($file.Name) - $($_.Exception.Message)"
        }
    }
    Write-Host ""
}

if ($clipAnalysis.Count -eq 0) {
    Write-Error "No valid clips remaining to process"
    exit 1
}

# Create export directory
New-Item -ItemType Directory -Path $exportDir -Force | Out-Null

# Process clips (trim and add chirons)
Write-Info "Processing clips (trimming, adding chirons, and stabilizing)..."
$processedClips = @()
$tempDir = Join-Path $Directory "temp_processed_$timestamp"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$clipNumber = 1
foreach ($clip in $clipAnalysis) {
    $outputPath = Join-Path $tempDir "processed_$($clipNumber.ToString('000')).mp4"
    $chironInfo = Get-ChironInfo -FileName $clip.File.Name
    
    if ($chironInfo.SkipStabilization) {
        Write-Host "  Processing: $($clip.File.Name) [No Stabilization]..."
    } else {
        Write-Host "  Processing: $($clip.File.Name) [With Stabilization]..."
    }
    
    if (Process-Clip -InputPath $clip.File.FullName -OutputPath $outputPath -Duration $clip.Duration -SkipStabilization $chironInfo.SkipStabilization) {
        $processedClips += $outputPath
        Write-Success "    [OK] Complete"
    } else {
        Write-Warning "    [X] Failed (see error log)"
    }
    
    $clipNumber++
}

Write-Host ""

if ($processedClips.Count -eq 0) {
    Write-Error "No clips were successfully processed"
    Remove-Item $tempDir -Recurse -Force
    exit 1
}

Write-Info "Successfully processed $($processedClips.Count) clip(s)"
Write-Host ""

# Group clips into 30-second exports
Write-Info "Creating final exports..."
$exportNumber = 1
$i = 0

while ($i -lt $processedClips.Count) {
    $clipsToMerge = $processedClips[$i..[math]::Min($i + 2, $processedClips.Count - 1)]
    $outputPath = Join-Path $exportDir "Export$exportNumber.mp4"
    
    $duration = $clipsToMerge.Count * 10
    Write-Host "  Creating Export$exportNumber.mp4 ($duration seconds, $($clipsToMerge.Count) clips)..."
    
    if (Merge-Clips -ClipPaths $clipsToMerge -OutputPath $outputPath) {
        Write-Success "    [OK] Complete"
    } else {
        Write-Warning "    [X] Failed (see error log)"
    }
    
    $exportNumber++
    $i += 3
}

# Cleanup temp directory
Write-Host ""
Write-Info "Cleaning up temporary files..."
Remove-Item $tempDir -Recurse -Force

Write-Host ""
Write-Host "========================================" -ForegroundColor Magenta
Write-Success "Processing Complete!"
Write-Host "========================================" -ForegroundColor Magenta
Write-Info "Exports saved to: $exportDir"
Write-Info "Error log saved to: $errorLogPath"
Write-Host ""
