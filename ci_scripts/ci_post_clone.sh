#!/bin/bash
set -e

echo "Setting build number to Xcode Cloud build number: $CI_BUILD_NUMBER"
cd "$CI_PRIMARY_REPOSITORY_PATH"
agvtool new-version -all "$CI_BUILD_NUMBER"
