#!/usr/bin/env sh

# shellcheck disable=SC2034
_DRIVER_REGEX='aws-secretsmanager [A-z0-9][A-z0-9/\-]*\#[A-z0-9][A-z0-9-]*'

# shellcheck source=scripts/drivers/_custom.sh
. "${SCRIPT_DIR}/drivers/_custom.sh"

aws_credentials_guardrails() {
    if [ "${_type}" != "yaml" ]; then
        echo "Only decryption of yaml files are allowed!"
        exit 1
    fi

    if ! aws sts get-caller-identity --output text >/dev/null; then
        if [ -z ${AWS_SECRET_ACCESS_KEY} && -z ${AWS_ACCESS_KEY_ID} ]; then
            if [ -z ${AWS_ROLE_ARN} && -z ${AWS_WEB_IDENTITY_TOKEN_FILE} ]; then
                echo "Missing AWS Credential Environment Variables!"
                exit 1
            fi
        fi
    fi

    if ! aws sts get-caller-identity --output text >/dev/null; then
        if [ -z ${AWS_DEFAULT_REGION} || -z ${AWS_REGION} ]; then
            echo "Missing AWS Region where the Secrets exist"
            exit 1
        fi
    fi

    if ! aws sts get-caller-identity --output text >/dev/null; then
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
}

_custom_driver_get_secret() {
    _type=$1
    _SECRET_ID="${2%#*}"
    _SECRET_KEY="${2#*#}"

    aws_credentials_guardrails

    if ! aws secretsmanager get-secret-value --secret-id ${_SECRET_ID} --output json | jq --raw-output '.SecretString' | jq -r .${_SECRET_KEY}; then
        echo "Error while get secret from aws secrets manager!" >&2
        echo aws secretsmanager get-secret-value --secret-id "${_SECRET_ID}" --output json | jq --raw-output '.SecretString' | jq -r ."${_SECRET_KEY}" >&2
        exit 1
    fi
}

driver_edit_file() {
    echo "Editing files is not supported!"
    exit 1
}

driver_decrypt_file() {
    _type=${1}
    _input=${2}
    _output=${3}

    aws_credentials_guardrails

    export FILE_INPUT_PATH=${_input}
    export FILE_OUTPUT_PATH=${_output}

    python3 <<EOF
import yaml
import boto3
import json
import os

secrets_file_dump = None
parsed_secrets = dict()

with open(os.environ["FILE_INPUT_PATH"]) as file:
    secrets_file_dump = yaml.load(file, Loader=yaml.FullLoader)
    secrets = secrets_file_dump["secrets"]
    for key, value in secrets.items():
        if '!aws-secretsmanager' in value:
            value_list = value.split(" ")
            split_list = value_list[1].split("#")
            secrets_id_name = split_list[0]
            secrets_key_name = split_list[1]
            client = boto3.client('secretsmanager')
            response = client.get_secret_value(
                SecretId=secrets_id_name,
            )
            secrets_string_dict = json.loads(response["SecretString"])
            secrets[key] = secrets_string_dict[secrets_key_name]

    parsed_secrets["secrets"] = secrets

with open(os.environ["FILE_OUTPUT_PATH"], "w") as file:
    documents = yaml.dump(parsed_secrets, file)
EOF

    unset FILE_INPUT_PATH
    unset FILE_OUTPUT_PATH

}
