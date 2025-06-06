#!/bin/bash

# Build script for Jimmy iOS app
# This script builds the app and shows manual installation steps for a connected iOS device

echo "🚀 Building Jimmy for iOS device..."

# Clean build folder
echo "🧹 Cleaning build folder..."
xcodebuild -project Jimmy.xcodeproj clean

# Build for device
echo "🔨 Building for iOS device..."
xcodebuild -project Jimmy.xcodeproj \
  -scheme Jimmy \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_IDENTITY="Apple Development" \
  DEVELOPMENT_TEAM="DPF8459C2J" \
  build

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo ""
    echo "📱 To install on your iPhone:"
    echo "1. Connect your iPhone via USB"
    echo "2. Open Jimmy.xcodeproj in Xcode"
    echo "3. Select your iPhone as destination"
    echo "4. Press ⌘+R to run"
    echo ""
    echo "🎯 Your new image caching system is ready to test!"
else
    echo "❌ Build failed!"
    exit 1
fi 