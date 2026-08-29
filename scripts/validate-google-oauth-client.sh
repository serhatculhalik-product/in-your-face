#!/bin/zsh
set +x
set -euo pipefail

if (( $# != 0 )); then
    echo "Google OAuth credential validation does not accept fixture files or endpoint overrides." >&2
    exit 64
fi

script_directory="${0:A:h}"
classifier="${script_directory}/lib/classify-google-oauth-token-response.sh"
token_endpoint="https://oauth2.googleapis.com/token"

client_id="${GOOGLE_OAUTH_CLIENT_ID:-}"
client_secret="${GOOGLE_OAUTH_CLIENT_SECRET:-}"
if [[ -z "${client_id}" ]]; then
    echo "GOOGLE_OAUTH_CLIENT_ID must be set before validating Google OAuth." >&2
    exit 1
fi

if [[ -z "${client_secret}" ]]; then
    echo "GOOGLE_OAUTH_CLIENT_SECRET must be set before validating Google OAuth." >&2
    exit 1
fi

if [[ "${client_id}" != *.apps.googleusercontent.com ]]; then
    echo "Google OAuth credential check failed: GOOGLE_OAUTH_CLIENT_ID is not a valid Google OAuth client ID. Download the Desktop app credential, update both values, and rebuild." >&2
    exit 1
fi

response_file="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/meeting-incoming-oauth-preflight.XXXXXX")"
cleanup() {
    /bin/rm -f -- "${response_file}"
}
trap cleanup EXIT HUP INT TERM

# A syntactically valid PKCE verifier and a deliberately invalid authorization
# code let Google validate the configured credential pair without authorizing
# or persisting access. A recognized pair reaches invalid_grant. Application
# type is configured separately in Google Cloud and is not inferred here.
dummy_code="meeting-incoming-invalid-authorization-code"
dummy_verifier="MeetingIncomingOAuthPreflightVerifier0123456789abcdefghijklmnopqrstuvwxyz"
redirect_uri="http://127.0.0.1:49152/oauth/callback"

http_status=""
if ! http_status="$(/usr/bin/curl \
    --silent \
    --show-error \
    --connect-timeout 10 \
    --max-time 20 \
    --proto '=https' \
    --tlsv1.2 \
    --request POST \
    --header 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "client_id=${client_id}" \
    --data-urlencode "client_secret=${client_secret}" \
    --data-urlencode "code=${dummy_code}" \
    --data-urlencode "code_verifier=${dummy_verifier}" \
    --data-urlencode 'grant_type=authorization_code' \
    --data-urlencode "redirect_uri=${redirect_uri}" \
    --output "${response_file}" \
    --write-out '%{http_code}' \
    "${token_endpoint}")"; then
    echo "Google OAuth credential check failed: Google's token endpoint could not be reached. Check the network connection and rebuild; the app was not packaged." >&2
    exit 1
fi

/bin/zsh "${classifier}" "${response_file}" "${http_status}"
