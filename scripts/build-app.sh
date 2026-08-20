#!/bin/zsh
set -euo pipefail

script_directory="${0:A:h}"
repository_directory="${script_directory:h}"
output_directory="${1:-${repository_directory}/.build/app}"
app_path="${output_directory}/In Your Face.app"
dotenv_path="${repository_directory}/.env"

if [[ -f "${dotenv_path}" ]]; then
    source "${dotenv_path}"
fi

if [[ -z "${GOOGLE_OAUTH_CLIENT_ID:-}" ]]; then
    echo "GOOGLE_OAUTH_CLIENT_ID must be set when packaging the app." >&2
    exit 1
fi

if [[ -z "${GOOGLE_OAUTH_CLIENT_SECRET:-}" ]]; then
    echo "GOOGLE_OAUTH_CLIENT_SECRET must be set when packaging the app." >&2
    exit 1
fi

swift build --configuration release --package-path "${repository_directory}"
binary_directory="$(swift build --configuration release --package-path "${repository_directory}" --show-bin-path)"
binary_path="${binary_directory}/InYourFace"

rm -rf -- "${app_path}"
mkdir -p "${app_path}/Contents/MacOS" "${app_path}/Contents/Resources"
cp "${binary_path}" "${app_path}/Contents/MacOS/InYourFace"
cp "${repository_directory}/Resources/InYourFace.app/Contents/Info.plist" "${app_path}/Contents/Info.plist"
/usr/bin/plutil -replace GoogleOAuthClientID -string "${GOOGLE_OAUTH_CLIENT_ID}" "${app_path}/Contents/Info.plist"
/usr/bin/plutil -replace GoogleOAuthClientSecret -string "${GOOGLE_OAUTH_CLIENT_SECRET}" "${app_path}/Contents/Info.plist"

/usr/bin/codesign --force --deep --sign - "${app_path}"

echo "Built ${app_path}"
echo "Launch with: open \"${app_path}\""
