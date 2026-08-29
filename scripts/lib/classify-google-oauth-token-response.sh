#!/bin/zsh
set +x
set -euo pipefail

if (( $# != 2 )); then
    echo "Usage: classify-google-oauth-token-response.sh <response-file> <http-status>" >&2
    exit 64
fi

response_file="$1"
http_status="$2"

if [[ ! -f "${response_file}" || ! "${http_status}" =~ '^[0-9]{3}$' ]]; then
    echo "Google OAuth credential check failed: Google's token endpoint returned an unexpected response. Confirm both Desktop app credential values and retry with network access." >&2
    exit 1
fi

error_code=""
error_description=""

error_code="$(/usr/bin/plutil -extract error raw -o - "${response_file}" 2>/dev/null || true)"
error_description="$(/usr/bin/plutil -extract error_description raw -o - "${response_file}" 2>/dev/null || true)"

normalized_description="${(L)error_description}"

if [[ "${error_code}" == "invalid_client" \
    || "${normalized_description}" == *"client_secret"* \
    || "${normalized_description}" == *"client secret"* \
    || "${normalized_description}" == *"client-secret"* ]]; then
    echo "Google OAuth credential check failed: Google did not accept the configured client ID and client secret. Download the Desktop app credential again, update both values, and rebuild." >&2
    exit 1
fi

if [[ "${error_code}" == "redirect_uri_mismatch" || "${error_code}" == "unauthorized_client" ]]; then
    echo "Google OAuth credential check failed: this credential does not support the Desktop app loopback authorization flow. Download a Desktop app credential, update both values, and rebuild." >&2
    exit 1
fi

# Google rejects the deliberately invalid authorization code only after it has
# accepted the configured client ID and client secret pair. No token can be
# issued by this probe. This verifies the pair, not the OAuth application type.
if [[ "${http_status}" == "400" && "${error_code}" == "invalid_grant" ]]; then
    echo "Google OAuth credential pair check passed."
    exit 0
fi

echo "Google OAuth credential check failed: Google's token endpoint returned an unexpected response. Confirm both Desktop app credential values and retry with network access." >&2
exit 1
