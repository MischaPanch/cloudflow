#! /bin/python
import json
import boto3
import logging
import os
from common.codecommit_util import get_record, get_branch_name, get_commit_info

# Lambda function triggering CloudFormation on create or delete of a branch in CodeCommit.
# When a branch is created, CloudFormation deploys a template for a stack,
# which creates a CodePipeline for the created branch.
# When a branch is deleted, CloudFormation is used to delete the branch again.

logging.basicConfig(format='%(levelname)s %(module)s - %(funcName)s: %(message)s')
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

# collect environment variables
BUILD_ARTIFACTS_BUCKET = os.environ["BuildArtifactsBucket"]
PROJECT_NAME = os.environ["ProjectName"]
PIPELINE_TEMPLATE_URL = os.environ["TemplateURL"]

# get clients
CFN_CLIENT = boto3.client('cloudformation')
S3_CLIENT = boto3.client('s3')


def get_stage(branch_name: str, separator="-"):
    stage="feature"
    if branch_name == "master":
        stage = "live"
    if branch_name == "develop":
        stage = "develop"
    return stage


def delete_s3_directory(bucket_name: str, path: str, client=S3_CLIENT):
    s3_list_response = client.list_objects_v2(
            Bucket=bucket_name,
            Prefix=path
        )['Contents']
    s3_keys_dict_list = [{'Key': entry['Key']} for entry in s3_list_response]
    logger.debug(f"received the following object list {s3_keys_dict_list}")
    delete_result = client.delete_objects(
        Bucket=bucket_name,
        Delete={
            'Objects': s3_keys_dict_list,
            'Quiet': True
        }
    )
    logger.debug(delete_result)


def handler(event, context):
    if not PROJECT_NAME:
        raise Exception("Environment variable ProjectName cannot be empty")

    status_code = 200
    response_body = "Nothing to do!"
    record = get_record(event)
    commit_info = get_commit_info(record)
    branch_name = get_branch_name(commit_info['ref'])
    stage = get_stage(branch_name)
    stack_s3_location = f"{PROJECT_NAME}/{branch_name}/latest/cloudformation/stack.zip"

    branch_created = commit_info.get('created')
    branch_deleted = commit_info.get('deleted')

    if branch_created and branch_deleted:
        raise Exception(f"Branch {branch_name} was created and deleted simultaneously")

    if branch_created:
        logger.debug(f'Creating deployment pipeline for {PROJECT_NAME}/{branch_name} from template file {PIPELINE_TEMPLATE_URL}')

        result = CFN_CLIENT.create_stack(
            StackName=f"{PROJECT_NAME}-{branch_name}-DeploymentPipeline",
            TemplateURL=PIPELINE_TEMPLATE_URL,
            Parameters=[
                {'ParameterKey': 'BuildArtifactsBucket', 'ParameterValue': BUILD_ARTIFACTS_BUCKET},
                {'ParameterKey': 'StackS3Location', 'ParameterValue': stack_s3_location},
                {'ParameterKey': 'ProjectName', 'ParameterValue': PROJECT_NAME},
                {'ParameterKey': 'ProjectPolicyArns', 'ParameterValue': f"{PROJECT_NAME}-Policies"},
                {'ParameterKey': 'BranchName', 'ParameterValue': branch_name},
                {'ParameterKey': 'Stage', 'ParameterValue': stage}
            ],
            Capabilities=['CAPABILITY_IAM', 'CAPABILITY_NAMED_IAM', 'CAPABILITY_AUTO_EXPAND'],
            OnFailure='ROLLBACK'
        )

        status_code = result['ResponseMetadata']['HTTPStatusCode']
        response_body = f'Deployment pipeline for branch {PROJECT_NAME}/{branch_name} was successfully created'
        logger.debug(response_body)

    if branch_deleted:
        logger.debug(f'Deleting deployment pipeline for {PROJECT_NAME}/{branch_name} ')
        try:
            result = CFN_CLIENT.delete_stack(
                StackName=f"{PROJECT_NAME}-{branch_name}-DeploymentPipeline"
            )
            status_code = result['ResponseMetadata']['HTTPStatusCode']

            s3_prefix = f"{PROJECT_NAME}/{branch_name}/"
            logger.debug(f"Deleting {BUILD_ARTIFACTS_BUCKET}/{s3_prefix} in s3")
            delete_s3_directory(BUILD_ARTIFACTS_BUCKET, s3_prefix)
            response_body = f'Code pipeline and directories for {PROJECT_NAME}/{branch_name} deleted successfully'
            logger.debug(response_body)

        except Exception as e:
            message = f'Pipeline stack named {PROJECT_NAME}/{branch_name} could not be deleted: {str(e)}'
            logger.warning(message)
            status_code = 500
            response_body = message

    logger.debug(f"Return: (${status_code}) ${response_body}")
    return {
        'status_code': status_code,
        'body': response_body
    }
