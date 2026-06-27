#!/bin/bash
set -e

echo "Building Anotate..."
xcodebuild -scheme Anotate build | tail -n 10

echo "Finding build product..."
BUILD_DIR=$(xcodebuild -scheme Anotate -showBuildSettings | grep -m 1 "BUILT_PRODUCTS_DIR" | grep -oE "\/.*")

echo "Deploying to Applications folder..."
rm -rf /Applications/Anotate.app
cp -R "$BUILD_DIR/Anotate.app" /Applications/

echo "Done! You can now launch Anotate from Spotlight."
