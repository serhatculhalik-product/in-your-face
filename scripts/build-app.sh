#!/bin/zsh
set +x
set -euo pipefail

script_directory="${0:A:h}"
repository_directory="${script_directory:h}"
output_directory="${1:-${repository_directory}/.build/app}"
app_path="${output_directory}/Meeting Incoming.app"
legacy_app_path="${output_directory}/In Your Face.app"
default_legacy_app_path="${repository_directory}/.build/app/In Your Face.app"
dotenv_path="${repository_directory}/.env"

if [[ -f "${dotenv_path}" ]]; then
    source "${dotenv_path}"
fi

source "${script_directory}/lib/public-build-configuration.sh"

code_sign_identity="${CODE_SIGN_IDENTITY:--}"
validate_public_build_configuration

echo "Validating Google OAuth credential pair..."
GOOGLE_OAUTH_CLIENT_ID="${GOOGLE_OAUTH_CLIENT_ID}" \
    GOOGLE_OAUTH_CLIENT_SECRET="${GOOGLE_OAUTH_CLIENT_SECRET}" \
    /bin/zsh "${script_directory}/validate-google-oauth-client.sh"

swift build \
    --configuration release \
    --arch arm64 \
    --package-path "${repository_directory}" \
    --product InYourFace
swift build \
    --configuration release \
    --arch arm64 \
    --package-path "${repository_directory}" \
    --product MeetingIncomingRelaunchHelper
swift build \
    --configuration release \
    --arch arm64 \
    --package-path "${repository_directory}" \
    --product MeetingIncomingAppDataResetHelper
binary_directory="$(swift build --configuration release --arch arm64 --package-path "${repository_directory}" --show-bin-path)"
binary_path="${binary_directory}/InYourFace"
relaunch_helper_path="${binary_directory}/MeetingIncomingRelaunchHelper"
app_data_reset_helper_path="${binary_directory}/MeetingIncomingAppDataResetHelper"

for packaged_binary in \
    "${binary_path}" \
    "${relaunch_helper_path}" \
    "${app_data_reset_helper_path}"; do
    if [[ "$(/usr/bin/lipo -archs "${packaged_binary}")" != "arm64" ]]; then
        echo "Release binaries must contain only arm64: ${packaged_binary:t}" >&2
        exit 1
    fi
done

rm -rf -- "${app_path}" "${legacy_app_path}" "${default_legacy_app_path}"
mkdir -p \
    "${app_path}/Contents/MacOS" \
    "${app_path}/Contents/Helpers" \
    "${app_path}/Contents/Resources"
cp "${binary_path}" "${app_path}/Contents/MacOS/InYourFace"
cp \
    "${relaunch_helper_path}" \
    "${app_path}/Contents/Helpers/MeetingIncomingRelaunchHelper"
cp \
    "${app_data_reset_helper_path}" \
    "${app_path}/Contents/Helpers/MeetingIncomingAppDataResetHelper"
cp "${repository_directory}/Resources/InYourFace.app/Contents/Info.plist" "${app_path}/Contents/Info.plist"
/usr/bin/plutil -replace GoogleOAuthClientID -string "${GOOGLE_OAUTH_CLIENT_ID}" "${app_path}/Contents/Info.plist"
/usr/bin/plutil -replace GoogleOAuthClientSecret -string "${GOOGLE_OAUTH_CLIENT_SECRET}" "${app_path}/Contents/Info.plist"

if [[ "${code_sign_identity}" == "-" ]]; then
    /usr/bin/codesign \
        --force \
        --sign - \
        "${app_path}/Contents/Helpers/MeetingIncomingRelaunchHelper"
    /usr/bin/codesign \
        --force \
        --sign - \
        "${app_path}/Contents/Helpers/MeetingIncomingAppDataResetHelper"
    /usr/bin/codesign --force --deep --sign - "${app_path}"
else
    /usr/bin/codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "${code_sign_identity}" \
        "${app_path}/Contents/Helpers/MeetingIncomingRelaunchHelper"
    /usr/bin/codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "${code_sign_identity}" \
        "${app_path}/Contents/Helpers/MeetingIncomingAppDataResetHelper"
    /usr/bin/codesign \
        --force \
        --deep \
        --options runtime \
        --timestamp \
        --sign "${code_sign_identity}" \
        "${app_path}"
fi
/usr/bin/codesign --verify --deep --strict "${app_path}"

echo "Built ${app_path}"
echo "Launch with: open \"${app_path}\""
