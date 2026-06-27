#!/bin/bash
set -e

BUILD_DIR="/tmp/AnotateBuild"

echo "Building Anotate..."
xcodebuild -scheme Anotate CONFIGURATION_BUILD_DIR="$BUILD_DIR" build | tail -n 10

echo "Deploying to Applications folder..."
rm -rf /Applications/Anotate.app
cp -R "$BUILD_DIR/Anotate.app" /Applications/

echo "Done! You can now launch Anotate from Spotlight."
