#!/bin/bash
set -e

# Build the project
echo "Building Mac Annotate..."
xcodebuild build -scheme "Mac Annotate" -destination 'platform=macOS' -quiet

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Mac Annotate.app" -type d | grep "Products/Debug/Mac Annotate.app" | grep -v "Index.noindex" | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo "Could not find Mac Annotate.app in DerivedData!"
    exit 1
fi

echo "Found built app at: $APP_PATH"

# Copy to Applications
echo "Copying to /Applications..."
rm -rf "/Applications/Mac Annotate.app"
cp -R "$APP_PATH" /Applications/

# Kill and Restart
echo "Restarting Mac Annotate..."
killall "Mac Annotate" || true
open "/Applications/Mac Annotate.app"

echo "Done!"
