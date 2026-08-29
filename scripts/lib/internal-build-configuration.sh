#!/bin/zsh

validate_internal_build_configuration() {
    local expected_public_project_number="66553866962"
    local required_bundle_identifier="com.serhatculhalik.in-your-face.internal"
    local configured_bundle_identifier="${INTERNAL_BUNDLE_IDENTIFIER:-${required_bundle_identifier}}"
    local public_client_id="${GOOGLE_OAUTH_CLIENT_ID:-}"
    local internal_client_id="${INTERNAL_GOOGLE_OAUTH_CLIENT_ID:-}"
    local client_secret="${INTERNAL_GOOGLE_OAUTH_CLIENT_SECRET:-}"
    local public_project_id="${GOOGLE_CLOUD_PROJECT_ID:-}"
    local internal_project_id="${INTERNAL_GOOGLE_CLOUD_PROJECT_ID:-}"
    local public_project_number="${GOOGLE_CLOUD_PROJECT_NUMBER:-}"
    local internal_project_number="${INTERNAL_GOOGLE_CLOUD_PROJECT_NUMBER:-}"

    if [[ "${configured_bundle_identifier}" != "${required_bundle_identifier}" ]]; then
        echo "The internal app bundle identifier must be exactly com.serhatculhalik.in-your-face.internal." >&2
        return 1
    fi
    if [[ -z "${internal_client_id}" ]]; then
        echo "INTERNAL_GOOGLE_OAUTH_CLIENT_ID must be set when packaging the internal app." >&2
        return 1
    fi
    if [[ -z "${client_secret}" ]]; then
        echo "INTERNAL_GOOGLE_OAUTH_CLIENT_SECRET must be set when packaging the internal app." >&2
        return 1
    fi
    if [[ -z "${public_client_id}" ]]; then
        echo "GOOGLE_OAUTH_CLIENT_ID must be set to verify public/internal OAuth isolation." >&2
        return 1
    fi
    if [[ -z "${public_project_id//[[:space:]]/}" ]]; then
        echo "GOOGLE_CLOUD_PROJECT_ID must be set when packaging the internal app." >&2
        return 1
    fi
    if [[ -z "${internal_project_id//[[:space:]]/}" ]]; then
        echo "INTERNAL_GOOGLE_CLOUD_PROJECT_ID must be set when packaging the internal app." >&2
        return 1
    fi
    if [[ -z "${public_project_number}" ]]; then
        echo "GOOGLE_CLOUD_PROJECT_NUMBER must be set when packaging the internal app." >&2
        return 1
    fi
    if [[ ! "${public_project_number}" =~ '^[0-9]+$' ]]; then
        echo "GOOGLE_CLOUD_PROJECT_NUMBER must contain only decimal digits." >&2
        return 1
    fi
    if [[ "${public_project_number}" != "${expected_public_project_number}" ]]; then
        echo "GOOGLE_CLOUD_PROJECT_NUMBER does not match Meeting Incoming's pinned public project." >&2
        return 1
    fi
    if [[ -z "${internal_project_number}" ]]; then
        echo "INTERNAL_GOOGLE_CLOUD_PROJECT_NUMBER must be set when packaging the internal app." >&2
        return 1
    fi
    if [[ ! "${internal_project_number}" =~ '^[0-9]+$' ]]; then
        echo "INTERNAL_GOOGLE_CLOUD_PROJECT_NUMBER must contain only decimal digits." >&2
        return 1
    fi
    if [[ "${internal_project_id}" == "${public_project_id}" ]]; then
        echo "The internal app must use a different Google Cloud project from the public app." >&2
        return 1
    fi
    if [[ "${internal_project_number}" == "${public_project_number}" ]]; then
        echo "The internal app must use a different Google Cloud project number from the public app." >&2
        return 1
    fi
    if [[ "${internal_client_id}" == "${public_client_id}" ]]; then
        echo "The internal app must use a different Google OAuth client ID from the public app." >&2
        return 1
    fi
    if [[ "${public_client_id}" != "${public_project_number}-"?*.apps.googleusercontent.com ]]; then
        echo "GOOGLE_OAUTH_CLIENT_ID must belong to GOOGLE_CLOUD_PROJECT_NUMBER." >&2
        return 1
    fi
    if [[ "${internal_client_id}" != "${internal_project_number}-"?*.apps.googleusercontent.com ]]; then
        echo "INTERNAL_GOOGLE_OAUTH_CLIENT_ID must belong to INTERNAL_GOOGLE_CLOUD_PROJECT_NUMBER." >&2
        return 1
    fi

    return 0
}
