import logging
logger = logging.getLogger(__name__)

def get_branch_name(ref: str, ref_prefix='refs/heads/', clean=True, max_len=15):
    """
    Get and preprocess the branch name from the reference within a CodeCommit event.

    :param ref: As obtained from the CodeCommit event
    :param ref_prefix:
    :param clean:
    :param max_len: Maximal length of the resulting branch_name. If None, the returned string will not be shortened 
    :return : Branch name. If clean is set to True replaces "/" by "-" in the branch name
    """
    if ref.startswith(ref_prefix):
        branch_name = ref[len(ref_prefix):]
    else:
        raise Exception(f"Expected reference {ref} to start with ${ref_prefix}")
    if clean:
        branch_name = branch_name.replace('/', '-').lower()
    if max_len is not None:
        branch_name = branch_name[:max_len]
    return branch_name

def get_record(event: dict):
    records = event['Records']
    if len(records) != 1:
        raise Exception(f"Expected exactly one record instead of the records {records}")
    return records[0]


def get_commit_info(record: dict) -> dict:
    codecommit_refs = record['codecommit']['references']
    logger.debug(f"Obtained the following codecommit references: {codecommit_refs}")
    if len(codecommit_refs) != 1:
        raise Exception(f"Expected exactly one commit references in record {record['eventTriggerName']} triggered "
                           f"by {record['eventSourceARN']}. Instead got {codecommit_refs}")
    return codecommit_refs[0]