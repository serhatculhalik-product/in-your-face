#!/bin/zsh
set -euo pipefail

script_directory="${0:A:h}"
repository_directory="${script_directory:h:h}"
configuration="${repository_directory}/scripts/lib/internal-build-configuration.sh"
build_script="${repository_directory}/scripts/build-internal-app.sh"

typeset -i failure_count=0

expect_success() {
    local name="$1"
    shift
    if env "$@" /bin/zsh -c "source '${configuration}'; validate_internal_build_configuration"; then
        echo "PASS: ${name}"
    else
        echo "FAIL: ${name}" >&2
        failure_count+=1
    fi
}

expect_failure() {
    local name="$1"
    local expected_message="$2"
    shift 2
    local output
    if output="$(env "$@" /bin/zsh -c "source '${configuration}'; validate_internal_build_configuration" 2>&1)"; then
        echo "FAIL: ${name} unexpectedly succeeded" >&2
        failure_count+=1
    elif [[ "${output}" != *"${expected_message}"* ]]; then
        echo "FAIL: ${name} emitted an unexpected error: ${output}" >&2
        failure_count+=1
    else
        echo "PASS: ${name}"
    fi
}

valid_configuration=(
    INTERNAL_GOOGLE_OAUTH_CLIENT_ID="222222222222-internaldesktop.apps.googleusercontent.com"
    INTERNAL_GOOGLE_OAUTH_CLIENT_SECRET="internal-secret"
    GOOGLE_OAUTH_CLIENT_ID="66553866962-publicdesktop.apps.googleusercontent.com"
    GOOGLE_CLOUD_PROJECT_ID="meeting-incoming-public"
    GOOGLE_CLOUD_PROJECT_NUMBER="66553866962"
    INTERNAL_GOOGLE_CLOUD_PROJECT_ID="meeting-incoming-internal"
    INTERNAL_GOOGLE_CLOUD_PROJECT_NUMBER="222222222222"
)

expect_success \
    "Distinct internal Desktop credential configuration is accepted" \
    "${valid_configuration[@]}"

expect_success \
    "The canonical internal bundle identifier is accepted explicitly" \
    "${valid_configuration[@]}" \
    INTERNAL_BUNDLE_IDENTIFIER="com.serhatculhalik.in-your-face.internal"

expect_failure \
    "Alternate internal bundle identifiers are rejected" \
    "must be exactly com.serhatculhalik.in-your-face.internal" \
    "${valid_configuration[@]}" \
    INTERNAL_BUNDLE_IDENTIFIER="com.example.meeting-incoming.internal"

expect_failure \
    "Internal credentials are required" \
    "INTERNAL_GOOGLE_OAUTH_CLIENT_ID must be set" \
    "${valid_configuration[@]}" \
    INTERNAL_GOOGLE_OAUTH_CLIENT_ID=""

expect_failure \
    "Internal Desktop client secret is required" \
    "INTERNAL_GOOGLE_OAUTH_CLIENT_SECRET must be set" \
    "${valid_configuration[@]}" \
    INTERNAL_GOOGLE_OAUTH_CLIENT_SECRET=""

expect_failure \
    "Public OAuth client is required for isolation checks" \
    "GOOGLE_OAUTH_CLIENT_ID must be set" \
    "${valid_configuration[@]}" \
    GOOGLE_OAUTH_CLIENT_ID=""

expect_failure \
    "Public Google Cloud project is required for isolation checks" \
    "GOOGLE_CLOUD_PROJECT_ID must be set" \
    "${valid_configuration[@]}" \
    GOOGLE_CLOUD_PROJECT_ID=""

expect_failure \
    "Internal Google Cloud project is required" \
    "INTERNAL_GOOGLE_CLOUD_PROJECT_ID must be set" \
    "${valid_configuration[@]}" \
    INTERNAL_GOOGLE_CLOUD_PROJECT_ID=""

expect_failure \
    "Public Google Cloud project number is required" \
    "GOOGLE_CLOUD_PROJECT_NUMBER must be set" \
    "${valid_configuration[@]}" \
    GOOGLE_CLOUD_PROJECT_NUMBER=""

expect_failure \
    "Public Google Cloud project number must be numeric" \
    "GOOGLE_CLOUD_PROJECT_NUMBER must contain only decimal digits" \
    "${valid_configuration[@]}" \
    GOOGLE_CLOUD_PROJECT_NUMBER="public-project-number"

expect_failure \
    "Internal Google Cloud project number is required" \
    "INTERNAL_GOOGLE_CLOUD_PROJECT_NUMBER must be set" \
    "${valid_configuration[@]}" \
    INTERNAL_GOOGLE_CLOUD_PROJECT_NUMBER=""

expect_failure \
    "Internal Google Cloud project number must be numeric" \
    "INTERNAL_GOOGLE_CLOUD_PROJECT_NUMBER must contain only decimal digits" \
    "${valid_configuration[@]}" \
    INTERNAL_GOOGLE_CLOUD_PROJECT_NUMBER="internal-project-number"

expect_failure \
    "Public and internal Google Cloud project IDs must differ" \
    "must use a different Google Cloud project from the public app" \
    "${valid_configuration[@]}" \
    INTERNAL_GOOGLE_CLOUD_PROJECT_ID="meeting-incoming-public"

expect_failure \
    "Public and internal Google Cloud project numbers must differ" \
    "must use a different Google Cloud project number" \
    "${valid_configuration[@]}" \
    INTERNAL_GOOGLE_CLOUD_PROJECT_NUMBER="66553866962"

expect_failure \
    "Public and internal OAuth clients must differ" \
    "must use a different Google OAuth client ID" \
    "${valid_configuration[@]}" \
    INTERNAL_GOOGLE_OAUTH_CLIENT_ID="66553866962-publicdesktop.apps.googleusercontent.com"

expect_failure \
    "Public OAuth client must be bound to its declared project number" \
    "GOOGLE_OAUTH_CLIENT_ID must belong to GOOGLE_CLOUD_PROJECT_NUMBER" \
    "${valid_configuration[@]}" \
    GOOGLE_OAUTH_CLIENT_ID="333333333333-publicdesktop.apps.googleusercontent.com"

expect_failure \
    "Internal OAuth client must be bound to its declared project number" \
    "INTERNAL_GOOGLE_OAUTH_CLIENT_ID must belong to INTERNAL_GOOGLE_CLOUD_PROJECT_NUMBER" \
    "${valid_configuration[@]}" \
    INTERNAL_GOOGLE_OAUTH_CLIENT_ID="333333333333-internaldesktop.apps.googleusercontent.com"

entrypoint_output=""
if entrypoint_output="$( \
    INTERNAL_BUNDLE_IDENTIFIER="com.example.meeting-incoming" \
    INTERNAL_GOOGLE_OAUTH_CLIENT_ID="222222222222-internaldesktop.apps.googleusercontent.com" \
    INTERNAL_GOOGLE_OAUTH_CLIENT_SECRET="internal-secret" \
    GOOGLE_OAUTH_CLIENT_ID="66553866962-publicdesktop.apps.googleusercontent.com" \
    GOOGLE_CLOUD_PROJECT_ID="meeting-incoming-public" \
    GOOGLE_CLOUD_PROJECT_NUMBER="66553866962" \
    INTERNAL_GOOGLE_CLOUD_PROJECT_ID="meeting-incoming-internal" \
    INTERNAL_GOOGLE_CLOUD_PROJECT_NUMBER="222222222222" \
    INTERNAL_BUILD_DOTENV_PATH="/dev/null" \
    /bin/zsh "${build_script}" 2>&1 \
)"; then
    echo "FAIL: Internal build entrypoint bypassed bundle validation" >&2
    failure_count+=1
elif [[ "${entrypoint_output}" != *"must be exactly com.serhatculhalik.in-your-face.internal"* ]]; then
    echo "FAIL: Internal build entrypoint emitted an unexpected validation error" >&2
    failure_count+=1
else
    echo "PASS: Internal build entrypoint validates before OAuth or packaging"
fi

entrypoint_output=""
if entrypoint_output="$( \
    INTERNAL_GOOGLE_OAUTH_CLIENT_ID="not-a-google-client-id" \
    INTERNAL_GOOGLE_OAUTH_CLIENT_SECRET="internal-secret" \
    GOOGLE_OAUTH_CLIENT_ID="66553866962-publicdesktop.apps.googleusercontent.com" \
    GOOGLE_CLOUD_PROJECT_ID="meeting-incoming-public" \
    GOOGLE_CLOUD_PROJECT_NUMBER="66553866962" \
    INTERNAL_GOOGLE_CLOUD_PROJECT_ID="meeting-incoming-internal" \
    INTERNAL_GOOGLE_CLOUD_PROJECT_NUMBER="222222222222" \
    INTERNAL_BUILD_DOTENV_PATH="/dev/null" \
    /bin/zsh "${build_script}" 2>&1 \
)"; then
    echo "FAIL: Internal build entrypoint bypassed OAuth project binding" >&2
    failure_count+=1
elif [[ "${entrypoint_output}" != *"INTERNAL_GOOGLE_OAUTH_CLIENT_ID must belong to INTERNAL_GOOGLE_CLOUD_PROJECT_NUMBER"* ]]; then
    echo "FAIL: Internal build entrypoint did not enforce OAuth project binding" >&2
    failure_count+=1
elif [[ "${entrypoint_output}" == *"internal-secret"* ]]; then
    echo "FAIL: Internal build entrypoint leaked its OAuth client secret" >&2
    failure_count+=1
else
    echo "PASS: Internal build entrypoint validates internal OAuth project binding before compiling"
fi

if (( failure_count > 0 )); then
    echo "${failure_count} internal build configuration test(s) failed." >&2
    exit 1
fi

echo "All internal build configuration tests passed."
