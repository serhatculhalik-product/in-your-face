#!/bin/zsh

validate_public_build_configuration() {
    local expected_project_number="66553866962"
    local client_id="${GOOGLE_OAUTH_CLIENT_ID:-}"
    local client_secret="${GOOGLE_OAUTH_CLIENT_SECRET:-}"
    local configured_project_number="${GOOGLE_CLOUD_PROJECT_NUMBER:-${expected_project_number}}"

    if [[ -z "${client_id}" ]]; then
        echo "GOOGLE_OAUTH_CLIENT_ID must be set when packaging the app." >&2
        return 1
    fi
    if [[ -z "${client_secret}" ]]; then
        echo "GOOGLE_OAUTH_CLIENT_SECRET must be set when packaging the app." >&2
        return 1
    fi
    if [[ "${configured_project_number}" != "${expected_project_number}" ]]; then
        echo "GOOGLE_CLOUD_PROJECT_NUMBER does not match Meeting Incoming's pinned public project." >&2
        return 1
    fi
    if [[ "${client_id}" != "${expected_project_number}-"?*.apps.googleusercontent.com ]]; then
        echo "GOOGLE_OAUTH_CLIENT_ID must belong to Meeting Incoming's pinned public project." >&2
        return 1
    fi
}
