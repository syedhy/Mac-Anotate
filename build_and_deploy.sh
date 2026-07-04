#!/bin/bash
set -e

APP_NAME="Mac Annotate"
DERIVED_DATA_PATH="${TMPDIR:-/tmp}/mac-annotate-derived-data"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/$APP_NAME.app"

# Build the project
echo "Building $APP_NAME..."
rm -rf "$DERIVED_DATA_PATH"
xcodebuild build -scheme "$APP_NAME" -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA_PATH" -quiet

if [ ! -d "$APP_PATH" ]; then
    echo "Could not find $APP_NAME.app at expected path: $APP_PATH"
    exit 1
fi

echo "Found built app at: $APP_PATH"

# Copy to Applications
echo "Copying to /Applications..."
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP_PATH" /Applications/

# Kill and Restart
echo "Restarting $APP_NAME..."
killall "$APP_NAME" || true
sleep 0.5
open -n "/Applications/$APP_NAME.app"

echo "Done!"
