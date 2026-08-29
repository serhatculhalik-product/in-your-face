#!/bin/zsh
set +x
set -euo pipefail

script_directory="${0:A:h}"
repository_directory="${script_directory:h}"
output_directory="${1:-${repository_directory}/.build/internal-app}"
scratch_directory="${INTERNAL_BUILD_SCRATCH_PATH:-${repository_directory}/.build/internal}"
app_path="${output_directory}/Meeting Incoming Internal.app"
dotenv_path="${INTERNAL_BUILD_DOTENV_PATH:-${repository_directory}/.env}"

if [[ -f "${dotenv_path}" ]]; then
    source "${dotenv_path}"
fi

source "${script_directory}/lib/internal-build-configuration.sh"

internal_bundle_identifier="com.serhatculhalik.in-your-face.internal"
code_sign_identity="${INTERNAL_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}"

validate_internal_build_configuration

echo "Validating internal Google OAuth credential pair..."
GOOGLE_OAUTH_CLIENT_ID="${INTERNAL_GOOGLE_OAUTH_CLIENT_ID}" \
    GOOGLE_OAUTH_CLIENT_SECRET="${INTERNAL_GOOGLE_OAUTH_CLIENT_SECRET}" \
    /bin/zsh "${script_directory}/validate-google-oauth-client.sh"

swift_build_arguments=(
    --configuration release
    --arch arm64
    --package-path "${repository_directory}"
    --scratch-path "${scratch_directory}"
    -Xswiftc -DINTERNAL_BUILD
)

swift build "${swift_build_arguments[@]}" --product InYourFace
swift build "${swift_build_arguments[@]}" --product MeetingIncomingInternalResetHelper
swift build "${swift_build_arguments[@]}" --product MeetingIncomingRelaunchHelper
swift build "${swift_build_arguments[@]}" --product MeetingIncomingAppDataResetHelper
binary_directory="$(swift build "${swift_build_arguments[@]}" --show-bin-path)"

app_binary_path="${binary_directory}/InYourFace"
internal_reset_helper_path="${binary_directory}/MeetingIncomingInternalResetHelper"
relaunch_helper_path="${binary_directory}/MeetingIncomingRelaunchHelper"
app_data_reset_helper_path="${binary_directory}/MeetingIncomingAppDataResetHelper"
for binary_path in \
    "${app_binary_path}" \
    "${internal_reset_helper_path}" \
    "${relaunch_helper_path}" \
    "${app_data_reset_helper_path}"; do
    if [[ "$(/usr/bin/lipo -archs "${binary_path}")" != "arm64" ]]; then
        echo "Internal app binaries must contain only arm64: ${binary_path:t}" >&2
        exit 1
    fi
done

rm -rf -- "${app_path}"
mkdir -p \
    "${app_path}/Contents/MacOS" \
    "${app_path}/Contents/Helpers" \
    "${app_path}/Contents/Resources"
cp "${app_binary_path}" "${app_path}/Contents/MacOS/InYourFace"
cp \
    "${internal_reset_helper_path}" \
    "${app_path}/Contents/Helpers/MeetingIncomingInternalResetHelper"
cp \
    "${relaunch_helper_path}" \
    "${app_path}/Contents/Helpers/MeetingIncomingRelaunchHelper"
cp \
    "${app_data_reset_helper_path}" \
    "${app_path}/Contents/Helpers/MeetingIncomingAppDataResetHelper"
cp \
    "${repository_directory}/Resources/InYourFace.app/Contents/Info.plist" \
    "${app_path}/Contents/Info.plist"

/usr/bin/plutil -replace CFBundleIdentifier \
    -string "${internal_bundle_identifier}" \
    "${app_path}/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleDisplayName \
    -string "Meeting Incoming Internal" \
    "${app_path}/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleName \
    -string "Meeting Incoming Internal" \
    "${app_path}/Contents/Info.plist"
/usr/bin/plutil -replace GoogleOAuthClientID \
    -string "${INTERNAL_GOOGLE_OAUTH_CLIENT_ID}" \
    "${app_path}/Contents/Info.plist"
/usr/bin/plutil -replace GoogleOAuthClientSecret \
    -string "${INTERNAL_GOOGLE_OAUTH_CLIENT_SECRET}" \
    "${app_path}/Contents/Info.plist"
/usr/bin/plutil -insert MeetingIncomingInternalBuild \
    -bool true \
    "${app_path}/Contents/Info.plist"

sign_path() {
    local path="$1"
    if [[ "${code_sign_identity}" == "-" ]]; then
        /usr/bin/codesign --force --sign - "${path}"
    else
        /usr/bin/codesign \
            --force \
            --options runtime \
            --timestamp \
            --sign "${code_sign_identity}" \
            "${path}"
    fi
}

sign_path "${app_path}/Contents/Helpers/MeetingIncomingInternalResetHelper"
sign_path "${app_path}/Contents/Helpers/MeetingIncomingRelaunchHelper"
sign_path "${app_path}/Contents/Helpers/MeetingIncomingAppDataResetHelper"
sign_path "${app_path}"
/usr/bin/codesign --verify --deep --strict "${app_path}"

echo "Built ${app_path}"
echo "Launch with: open \"${app_path}\""
