#!/bin/bash
set -e

# Build the project
echo "Building Anotate..."
xcodebuild build -scheme Anotate -destination 'platform=macOS' -quiet

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Anotate.app" -type d | grep "Products/Debug/Anotate.app" | grep -v "Index.noindex" | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo "Could not find Anotate.app in DerivedData!"
    exit 1
fi

echo "Found built app at: $APP_PATH"

# Copy to Applications
echo "Copying to /Applications..."
rm -rf /Applications/Anotate.app
cp -R "$APP_PATH" /Applications/

# Kill and Restart
echo "Restarting Anotate..."
killall Anotate || true
open /Applications/Anotate.app

echo "Done!"
