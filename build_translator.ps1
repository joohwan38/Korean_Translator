# Simple Build Script (English version)
Write-Host "==== Korean Translator Windows Build Script ====" -ForegroundColor Cyan
Write-Host ""

# Check working directory
Write-Host "Current working directory: $((Get-Location).Path)" -ForegroundColor Yellow
Write-Host "Checking paths..." -ForegroundColor Yellow

# Check iconimage folder
if (-not (Test-Path -Path "iconimage" -PathType Container)) {
    Write-Host "[ERROR] iconimage folder not found!" -ForegroundColor Red
    Write-Host "Please create the iconimage folder and add app_icon.png file." -ForegroundColor Red
    Read-Host "Press any key to continue..."
    exit 1
}

# Check icon file
if (-not (Test-Path -Path "iconimage\app_icon.png" -PathType Leaf)) {
    Write-Host "[ERROR] iconimage\app_icon.png file not found!" -ForegroundColor Red
    Write-Host "Please add app_icon.png file to the iconimage folder." -ForegroundColor Red
    Read-Host "Press any key to continue..."
    exit 1
}

# Convert icon
Write-Host "Converting PNG icon to ICO..." -ForegroundColor Green
try {
    python -c "from PIL import Image; img = Image.open('iconimage/app_icon.png'); img.save('app_icon.ico', sizes=[(16,16), (32,32), (48,48), (64,64), (128,128)])"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Icon conversion failed! Using default icon." -ForegroundColor Yellow
    } else {
        Write-Host "Icon conversion successful!" -ForegroundColor Green
    }
} catch {
    Write-Host "Icon conversion failed! Using default icon. $_" -ForegroundColor Yellow
}

# Clean build cache
Write-Host "Cleaning existing build cache..." -ForegroundColor Green
if (Test-Path -Path "build") { Remove-Item -Path "build" -Recurse -Force }
if (Test-Path -Path "dist") { Remove-Item -Path "dist" -Recurse -Force }
if (Test-Path -Path "__pycache__") { Remove-Item -Path "__pycache__" -Recurse -Force }
Get-ChildItem -Path "*.spec" -ErrorAction SilentlyContinue | Remove-Item -Force

# Run PyInstaller
Write-Host "Building executable with PyInstaller..." -ForegroundColor Green
try {
    # Run as Python module to prevent errors
    python -m PyInstaller --clean --onefile --windowed --icon=app_icon.ico --add-data "iconimage\app_icon.png;iconimage" --name KoreanTranslator test.py
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error during build process!" -ForegroundColor Red
        Read-Host "Press any key to continue..."
        exit 1
    }
} catch {
    Write-Host "Error during build process! $_" -ForegroundColor Red
    Read-Host "Press any key to continue..."
    exit 1
}

Write-Host ""
Write-Host "Build completed successfully!" -ForegroundColor Green
Write-Host "Executable location: dist\KoreanTranslator.exe" -ForegroundColor Cyan
Read-Host "Press any key to continue..."