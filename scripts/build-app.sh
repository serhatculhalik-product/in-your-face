#!/bin/zsh
set -euo pipefail

script_directory="${0:A:h}"
repository_directory="${script_directory:h}"
output_directory="${1:-${repository_directory}/.build/app}"
app_path="${output_directory}/In Your Face.app"

binary_directory="$(swift build --configuration release --package-path "${repository_directory}" --show-bin-path)"
binary_path="${binary_directory}/InYourFace"

rm -rf -- "${app_path}"
mkdir -p "${app_path}/Contents/MacOS" "${app_path}/Contents/Resources"
cp "${binary_path}" "${app_path}/Contents/MacOS/InYourFace"
cp "${repository_directory}/Resources/InYourFace.app/Contents/Info.plist" "${app_path}/Contents/Info.plist"

/usr/bin/codesign --force --deep --sign - "${app_path}"

echo "Built ${app_path}"
echo "Launch with: open \"${app_path}\""
