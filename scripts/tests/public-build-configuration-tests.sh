#!/bin/zsh
set +x
set -euo pipefail

script_directory="${0:A:h}"
repository_directory="${script_directory:h:h}"
configuration="${repository_directory}/scripts/lib/public-build-configuration.sh"
build_script="${repository_directory}/scripts/build-app.sh"
failure_count=0

expect_success() {
    local name="$1"
    shift
    if env "$@" /bin/zsh -c "source '${configuration}'; validate_public_build_configuration"; then
        echo "PASS: ${name}"
    else
        echo "FAIL: ${name}" >&2
        failure_count=$((failure_count + 1))
    fi
}

expect_failure() {
    local name="$1"
    local expected="$2"
    shift 2
    local output
    if output="$(env "$@" /bin/zsh -c "source '${configuration}'; validate_public_build_configuration" 2>&1)"; then
        echo "FAIL: ${name}" >&2
        failure_count=$((failure_count + 1))
    elif [[ "${output}" == *"${expected}"* ]]; then
        echo "PASS: ${name}"
    else
        echo "FAIL: ${name} (unexpected diagnostic)" >&2
        failure_count=$((failure_count + 1))
    fi
}

base=(
    GOOGLE_OAUTH_CLIENT_ID="66553866962-public.apps.googleusercontent.com"
    GOOGLE_OAUTH_CLIENT_SECRET="public-secret"
    GOOGLE_CLOUD_PROJECT_NUMBER="66553866962"
)

expect_success "Public OAuth client is bound to its declared project" "${base[@]}"
expect_failure "Public client is required" "GOOGLE_OAUTH_CLIENT_ID" \
    GOOGLE_OAUTH_CLIENT_ID="" GOOGLE_OAUTH_CLIENT_SECRET="public-secret" \
    GOOGLE_CLOUD_PROJECT_NUMBER="66553866962"
expect_failure "Public secret is required" "GOOGLE_OAUTH_CLIENT_SECRET" \
    GOOGLE_OAUTH_CLIENT_ID="66553866962-public.apps.googleusercontent.com" \
    GOOGLE_OAUTH_CLIENT_SECRET="" GOOGLE_CLOUD_PROJECT_NUMBER="66553866962"
expect_failure "Configured project number must match the pinned public project" "pinned public project" \
    GOOGLE_OAUTH_CLIENT_ID="66553866962-public.apps.googleusercontent.com" \
    GOOGLE_OAUTH_CLIENT_SECRET="public-secret" GOOGLE_CLOUD_PROJECT_NUMBER="123456"
expect_failure "Public client must match the pinned public project" "must belong" \
    GOOGLE_OAUTH_CLIENT_ID="654321-public.apps.googleusercontent.com" \
    GOOGLE_OAUTH_CLIENT_SECRET="public-secret" GOOGLE_CLOUD_PROJECT_NUMBER="66553866962"

if /usr/bin/grep -Eq \
    '^[[:space:]]*/usr/bin/codesign --verify --deep --strict "\$\{app_path\}"[[:space:]]*$' \
    "${build_script}"; then
    echo "PASS: Public packaging verifies the completed app signature"
else
    echo "FAIL: Public packaging does not verify the completed app signature" >&2
    failure_count=$((failure_count + 1))
fi

if (( failure_count > 0 )); then
    echo "${failure_count} public build configuration test(s) failed." >&2
    exit 1
fi

echo "All public build configuration tests passed."
