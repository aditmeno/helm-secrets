#!/usr/bin/env sh

# shellcheck disable=SC2034
_DRIVER_REGEX='!aws-secretsmanager [A-z0-9][A-z0-9/\-]*\#[A-z0-9][A-z0-9-]*'

# shellcheck source=scripts/drivers/_custom.sh
. "${SCRIPT_DIR}/drivers/_custom.sh"

_custom_driver_get_secret() {
    _type=$1
    _SECRET_ID="${2%#*}"
    _SECRET_KEY="${2#*#}"

    if [ "${_type}" != "yaml" ]; then
        echo "Only decryption of yaml files are allowed!"
        exit 1
    fi

    if ! aws sts get-caller-identity --output text; then
        if [ -z ${AWS_SECRET_ACCESS_KEY} && -z ${AWS_ACCESS_KEY_ID} ]; then
            if [ -z ${AWS_ROLE_ARN} && -z ${AWS_WEB_IDENTITY_TOKEN_FILE} ]; then
                echo "Missing AWS Credential Environment Variables!"
                exit 1
            fi
        fi
    fi

    if ! aws sts get-caller-identity --output text; then
        if [ -z ${AWS_DEFAULT_REGION} || -z ${AWS_REGION} ]; then
            echo "Missing AWS Region where the Secrets exist"
            exit 1
        fi
    fi

    if ! aws sts get-caller-identity --output text; then
        if [ ! -z ${AWS_ROLE_ARN} || ! -z ${AWS_WEB_IDENTITY_TOKEN_FILE} ]; then
            aws sts assume-role-with-web-identity \
                --role-arn $AWS_ROLE_ARN \
                --role-session-name x-account \
                --web-identity-token file://$AWS_WEB_IDENTITY_TOKEN_FILE \
                --duration 1500 >/tmp/temp_creds.txt

            export AWS_ACCESS_KEY_ID="$(cat /tmp/temp_creds.txt | jq -r ".Credentials.AccessKeyId")"
            export AWS_SECRET_ACCESS_KEY="$(cat /tmp/temp_creds.txt | jq -r ".Credentials.SecretAccessKey")"
            export AWS_SESSION_TOKEN="$(cat /tmp/temp_creds.txt | jq -r ".Credentials.SessionToken")"

            rm /tmp/temp_creds.txt

        fi
    fi

    if ! aws secretsmanager get-secret-value --secret-id ${_SECRET_ID} | jq --raw-output '.SecretString' | jq -r .${_SECRET_KEY}; then
        echo "Error while get secret from aws secrets manager!" >&2
        echo aws secretsmanager get-secret-value --secret-id "${_SECRET_ID}" | jq --raw-output '.SecretString' | jq -r ."${_SECRET_KEY}" >&2
        exit 1
    fi
}

driver_edit_file() {
    echo "Editing files is not supported!"
    exit 1
}
