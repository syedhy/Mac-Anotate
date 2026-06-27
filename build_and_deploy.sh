#!/bin/bash
set -e

echo "Building Anotate..."
xcodebuild -scheme Anotate CONFIGURATION_BUILD_DIR="$(pwd)/build" build | tail -n 10

echo "Deploying to Applications folder..."
rm -rf /Applications/Anotate.app
cp -R build/Anotate.app /Applications/

echo "Done! You can now launch Anotate from Spotlight."
