import boto3
import os
import logging
import json
from common.codecommit_util import get_record, get_branch_name, get_commit_info


logging.basicConfig(format='%(levelname)s %(module)s - %(funcName)s: %(message)s')
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

def handler(event, context):
    logger.debug(os.environ.get('BuildArtifactsBucket'))

    record = get_record(event)
    
    commit_info = record.get('codecommit').get('references')[0]

    branch_deleted = commit_info.get('deleted')
    if branch_deleted:
        logger.info('ignoring branch deleted event')
        return 

    branch_name = get_branch_name(commit_info['ref'])

    branch_name_clean = branch_name.replace('/', '-')
    commit_id = commit_info.get('commit')
    build_artifacts_bucket = os.environ.get('BuildArtifactsBucket')
    project_name = os.environ.get('ProjectName')

    client = boto3.client('codebuild')
    logger.debug(f'Starting CodeBuild for {project_name}/{branch_name_clean} for commit {commit_id}')
    response = client.start_build(
        projectName=project_name,
        sourceVersion=commit_id,
        environmentVariablesOverride=[
            {
                'name': 'branch_name',
                'value': branch_name_clean,
                'type': 'PLAINTEXT'
            },
            {
                'name': 'build_artifacts_bucket',
                'value': build_artifacts_bucket,
                'type': 'PLAINTEXT'
            },
        ],
        artifactsOverride={
            'type': 'S3',
            'location': build_artifacts_bucket,
            'path': f"{project_name}/{branch_name_clean}",  # outer directory name(s)
            'namespaceType': 'NONE',  # inner directory name
            'name': '/',
            'overrideArtifactName': True,
            'packaging': 'NONE',
        }
    )
    logger.debug(response)

    return {
        'statusCode': 200,
        'body': f'Successfully triggered CodeBuild for branch {branch_name} on commit {commit_id}'
    }
