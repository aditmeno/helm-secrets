import yaml
import boto3
import json
import sys

secrets_file_dump = None
parsed_secrets = dict()

with open(sys.argv[1]) as file:
    secrets_file_dump = yaml.load(file, Loader=yaml.FullLoader)
    secrets = secrets_file_dump["secrets"]
    for key, value in secrets.items():
        if 'aws-secretsmanager' in value:
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

with open(sys.argv[2], "w") as file:
    documents = yaml.dump(parsed_secrets, file)
