#!/bin/zsh
set -euo pipefail

script_directory="${0:A:h}"
repository_directory="${script_directory:h:h}"
classifier="${repository_directory}/scripts/lib/classify-google-oauth-token-response.sh"
validator="${repository_directory}/scripts/validate-google-oauth-client.sh"
fixtures="${script_directory}/fixtures"

typeset -i failure_count=0

record_failure() {
    echo "FAIL: $1" >&2
    failure_count+=1
}

expect_success() {
    local name="$1"
    local fixture="$2"
    local http_status="$3"
    local output

    if output="$(/bin/zsh "${classifier}" "${fixture}" "${http_status}" 2>&1)"; then
        if [[ "${output}" != *"credential pair"* ]]; then
            record_failure "${name} did not emit the curated success message"
            return
        fi
        echo "PASS: ${name}"
    else
        record_failure "${name} unexpectedly failed: ${output}"
    fi
}

expect_failure() {
    local name="$1"
    local fixture="$2"
    local http_status="$3"
    local expected_message="$4"
    local output

    if output="$(/bin/zsh "${classifier}" "${fixture}" "${http_status}" 2>&1)"; then
        record_failure "${name} unexpectedly succeeded"
        return
    fi

    if [[ "${output}" != *"${expected_message}"* ]]; then
        record_failure "${name} did not emit the expected curated error: ${output}"
        return
    fi

    if [[ "${output}" == *"fixture-client-id"* || "${output}" == *"fixture-client-secret"* ]]; then
        record_failure "${name} leaked fixture credentials"
        return
    fi

    echo "PASS: ${name}"
}

expect_success \
    "Recognized credential pair is accepted only on Google's invalid_grant probe response" \
    "${fixtures}/invalid-grant.json" \
    "400"

expect_failure \
    "Missing or rejected client secret fails closed" \
    "${fixtures}/client-secret-required.json" \
    "400" \
    "did not accept"

expect_failure \
    "Mismatched client ID and secret fail closed" \
    "${fixtures}/invalid-client.json" \
    "401" \
    "did not accept"

expect_failure \
    "Redirect-incompatible client is rejected" \
    "${fixtures}/redirect-uri-mismatch.json" \
    "400" \
    "Desktop app"

expect_failure \
    "Unknown provider error fails closed" \
    "${fixtures}/unknown-error.json" \
    "400" \
    "unexpected response"

expect_failure \
    "Successful token response is never accepted as a probe" \
    "${fixtures}/unexpected-success.json" \
    "200" \
    "unexpected response"

expect_failure \
    "Malformed provider response fails closed" \
    "${fixtures}/malformed-response.txt" \
    "502" \
    "unexpected response"

validator_output=""
if validator_output="$(GOOGLE_OAUTH_CLIENT_ID="fixture-client-id.apps.googleusercontent.com" \
    GOOGLE_OAUTH_CLIENT_SECRET="fixture-client-secret" \
    /bin/zsh "${validator}" "${fixtures}/invalid-grant.json" 2>&1)"; then
    record_failure "Production validator accepted a fixture argument"
elif [[ "${validator_output}" != *"does not accept fixture files or endpoint overrides"* ]]; then
    record_failure "Production validator fixture guard emitted an unexpected error: ${validator_output}"
elif [[ "${validator_output}" == *"fixture-client-id"* ]]; then
    record_failure "Production validator fixture guard leaked the client ID"
else
    echo "PASS: Production validator cannot be switched into fixture mode"
fi

validator_output=""
if validator_output="$(GOOGLE_OAUTH_CLIENT_ID="fixture-client-id" \
    GOOGLE_OAUTH_CLIENT_SECRET="fixture-client-secret" \
    /bin/zsh "${validator}" 2>&1)"; then
    record_failure "Production validator accepted a malformed client ID"
elif [[ "${validator_output}" != *"not a valid Google OAuth client ID"* ]]; then
    record_failure "Malformed client ID emitted an unexpected error: ${validator_output}"
elif [[ "${validator_output}" == *"fixture-client-id"* ]]; then
    record_failure "Malformed client ID error leaked the client ID"
else
    echo "PASS: Production validator rejects malformed client IDs without printing them"
fi

validator_output=""
if validator_output="$(GOOGLE_OAUTH_CLIENT_ID="fixture-client-id" \
    GOOGLE_OAUTH_CLIENT_SECRET="fixture-client-secret" \
    /bin/zsh -x "${validator}" 2>&1)"; then
    record_failure "Production validator accepted a malformed client ID under shell tracing"
elif [[ "${validator_output}" == *"fixture-client-id"* \
    || "${validator_output}" == *"fixture-client-secret"* ]]; then
    record_failure "Production validator leaked OAuth credentials under shell tracing"
else
    echo "PASS: Production validator disables shell tracing before handling credentials"
fi

validator_output=""
if validator_output="$(GOOGLE_OAUTH_CLIENT_ID="fixture-client-id.apps.googleusercontent.com" \
    /bin/zsh "${validator}" 2>&1)"; then
    record_failure "Production validator accepted a missing client secret"
elif [[ "${validator_output}" != *"GOOGLE_OAUTH_CLIENT_SECRET must be set"* ]]; then
    record_failure "Missing client secret emitted an unexpected error: ${validator_output}"
elif [[ "${validator_output}" == *"fixture-client-id"* ]]; then
    record_failure "Missing client secret error leaked the client ID"
else
    echo "PASS: Production validator requires both credential values"
fi

if (( failure_count > 0 )); then
    echo "${failure_count} OAuth preflight test(s) failed." >&2
    exit 1
fi

echo "All OAuth preflight tests passed."
