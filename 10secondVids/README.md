# Video Clip Processing Script - README

## Overview
This PowerShell script processes MP4 video clips by:
- Deleting clips shorter than 5 seconds
- Trimming clips longer than 10 seconds to exactly 10 seconds (from the middle)
- Adding chiron/subtitle overlays based on filenames
- Concatenating clips into 30-second exports

## Prerequisites

### FFmpeg Installation (REQUIRED)

The script requires FFmpeg to be installed. Choose one method:

#### Method 1: Direct Download (Recommended)
1. Download FFmpeg from: https://www.gyan.dev/ffmpeg/builds/
   - Get the "ffmpeg-release-essentials.zip" file
2. Extract the ZIP file to a location (e.g., `C:\ffmpeg`)
3. Add FFmpeg to your system PATH:
   - Open System Properties → Environment Variables
   - Under "System variables", find and edit "Path"
   - Add a new entry: `C:\ffmpeg\bin` (adjust path if different)
4. Restart PowerShell

#### Method 2: Using Chocolatey
If you have Chocolatey package manager installed:
```powershell
choco install ffmpeg
```

#### Method 3: Using Winget
```powershell
winget install ffmpeg
```

### Verify Installation
Open a new PowerShell window and run:
```powershell
ffmpeg -version
```
You should see version information. If you get an error, FFmpeg is not properly installed.

### Font Requirement
The script uses **Open Sans Bold** font. Windows should have this font by default. If chirons don't appear:
1. Download Open Sans from: https://fonts.google.com/specimen/Open+Sans
2. Install the Bold variant to `C:\Windows\Fonts\`

## Usage

### Basic Usage
1. Place the `process-clips.ps1` script in the same directory as your MP4 files
2. Open PowerShell in that directory (Shift + Right-click → "Open PowerShell window here")
3. Run the script:
   ```powershell
   .\process-clips.ps1
   ```

### Alternative: Specify Directory
```powershell
.\process-clips.ps1 -Directory "C:\path\to\your\videos"
```

### Auto-Accept Frame Rate Conversion
To automatically convert non-standard frame rates without prompting:
```powershell
.\process-clips.ps1 -AutoAccept
```

### File Naming Convention
Your MP4 files should follow one of these naming patterns:
- Format 1: `Name-With-Dashes_number.mp4` (underscore separator)
- Format 2: `Name-With-Dashes (number).mp4` (space with parentheses)
- Examples: 
  - `Northern-Canada_1.mp4` → Chiron displays: "Northern Canada"
  - `Northern-Canada (1).mp4` → Chiron displays: "Northern Canada"
  - `Some-Place_3.mp4` → Chiron displays: "Some Place"

The chiron will display everything before the underscore OR before a space followed by parentheses, with dashes converted to spaces.

### Skipping Stabilization
By default, all clips are stabilized to reduce camera shake. To skip stabilization for specific clips, include `NoStable` in the filename after the underscore or in the parentheses:
- Examples:
  - `Northern-Canada_1NoStable.mp4` → No stabilization applied
  - `Northern-Canada (1NoStable).mp4` → No stabilization applied
  - `Shaky-Footage_2.mp4` → Stabilization applied
  
This is useful for clips that are already stable or where stabilization causes unwanted effects (like tripod shots or intentional camera movement).

## What the Script Does

### Step 1: Analysis
- Checks all MP4 files in the directory
- Identifies clips shorter than 5 seconds (will be deleted)
- Identifies clips with non-standard frame rates
- Displays analysis results

### Step 2: Frame Rate Check
If clips with non-59.94fps are found, you'll be prompted:
- **Y**: Include them and convert to 59.94fps
- **N**: Skip them entirely

### Step 3: Deletion
Clips shorter than 5 seconds are permanently deleted.

### Step 4: Processing
For each valid clip:
- Trims to exactly 10 seconds (from the middle if longer)
- Applies video stabilization (unless "NoStable" in filename):
  - Uses FFmpeg's vidstab filter (2-pass process)
  - Reduces camera shake and jitter
  - Smoothing level: 10, Shakiness detection: 5
- Adds chiron overlay:
  - Font: Open Sans Bold, size 100
  - Color: White with black stroke (2px)
  - Position: Bottom-right corner with 5% padding
  - Duration: Entire 10-second clip
- Removes audio
- Outputs at 1920x1080, 59.94fps, H.264

### Step 5: Export
- Groups processed clips into sets of 3
- Creates 30-second exports (3 clips × 10 seconds)
- Remaining clips create shorter exports (10s or 20s)
- Names: `Export1.mp4`, `Export2.mp4`, etc.

## Output

### Exports Folder
Final videos are saved to: `Exports_YYYYMMDD_HHMMSS\`

### Error Log
Any issues are logged to: `error_log_YYYYMMDD_HHMMSS.txt`

## Example

**Input files:**
- Amazing-Beach_1.mp4 (3 seconds) → Deleted
- Cool-Mountain_2.mp4 (8 seconds) → Processed to 8s with chiron "Cool Mountain" + stabilization
- Some-Place_3NoStable.mp4 (12 seconds) → Trimmed to 10s with chiron "Some Place" (no stabilization)
- Another-Spot (4).mp4 (10 seconds) → Processed to 10s with chiron "Another Spot" + stabilization
- Final-View_5.mp4 (15 seconds) → Trimmed to 10s with chiron "Final View" + stabilization

**Output:**
- `Exports_20250207_143022\Export1.mp4` (30 seconds: clips 2, 3, 4)
- `Exports_20250207_143022\Export2.mp4` (10 seconds: clip 5)

## Troubleshooting

### "FFmpeg is not installed"
- Follow the FFmpeg installation instructions above
- Ensure FFmpeg is in your system PATH
- Restart PowerShell after installation

### "Cannot run scripts" / Execution Policy Error
PowerShell's execution policy may block the script. Run:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```
Then try running the script again.

### Font Not Found
If chirons don't appear:
- Verify Open Sans Bold is installed in `C:\Windows\Fonts\`
- Download and install from: https://fonts.google.com/specimen/Open+Sans

### Clips Not Processing
- Check the error log file for specific issues
- Ensure clips are valid MP4 files
- Verify filenames follow the `Name_number.mp4` pattern

### Processing is Slow
- Video processing is CPU-intensive
- Processing time depends on:
  - Number and length of clips
  - Computer performance
  - Source video quality

## Technical Specifications

**Output Video Specifications:**
- Resolution: 1920x1080
- Frame Rate: 59.94fps (60000/1001)
- Codec: H.264
- Audio: Removed
- Stabilization: FFmpeg vidstab filter (2-pass, shakiness=5, smoothing=10) unless "NoStable" in filename
- Chiron: White text, 100pt, black 2px stroke, bottom-right with 5% padding

## Notes

- Original files are modified (short clips deleted)
- Processed clips are 10 seconds each
- Audio is completely removed from all clips
- Clips are sorted alphabetically before grouping
- Video stabilization is applied by default (adds processing time)
- Use "NoStable" in filename to skip stabilization for specific clips
- Temporary files are automatically cleaned up
- Safe to re-run on the same directory (won't reprocess exports)

## Support

If you encounter issues:
1. Check the error log file
2. Verify FFmpeg installation: `ffmpeg -version`
3. Ensure input files are valid MP4 format
4. Check that filenames follow the naming convention
