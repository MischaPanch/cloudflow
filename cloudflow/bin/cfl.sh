#!/usr/bin/env bash
shopt -s nullglob
set -e

function usage {
  cat << USAGE >&2
usage:
  ${0##*/} [options] <command [command_options]> 
description:
  The command line tool for CloudFlow
commands:
  init                Initialize resources necessary for CloudFlow and create a new generator from the current repository.
  deploy-project      Create or update a CI/CD project
  configure           Set essential configuration

options:
  --help | -h help    Show this message

requirements:
  aws cli >= 1.16.212
  zip
  jq
  yq
USAGE
  exit 1
}

# Default/pre-existing configuration
# shellcheck source=../../build.conf
source build.conf
STACK=${STACK:-"cloudformation/stack"}
PROJECT_TEMPLATES=${PROJECT_TEMPLATES:-"project-templates"}

CLOUDFLOW_CONFIG="cloudflow/config.conf"
# shellcheck source=../config.conf
source $CLOUDFLOW_CONFIG

# error handling
function check_nonempty_value() {
  key=$1
  value=$(eval "echo \$$key")
  if [[ -z "$value" ]]; then echo -e "\e[31mERROR: <$key> cannot be empty\e[0m" && exit 1; fi
}

function abort() {
  echo -e "\e[31mABORT: Exit on user request\e[0m"
  exit 1
}

function try-except() {
  command=$1
  caught_error_code=$2
  except=$3
  error_code=0
  error_message=$($command 2>&1 ) || error_code=$?
  error_message=${error_message:-"Unknown Error: Check your connection"}
  if [[  $error_code -eq 0 ]]; then return; fi
  if [[ $error_code -eq $caught_error_code ]]; then 
    eval "$except"
  else
    echo -e "\e[31m$error_message\e[0m" && exit $error_code
  fi
}

# user input management
function prompt_configuration_entry() {
  default_value="$(eval "echo \${$1}")"
  read -rp "$1 [$default_value]: " new_value
  new_value=${new_value:-$default_value}
  # save the choice to the config file
  replace_or_add_config "$1" "$new_value"
  # and set the environment variable to its new value
  eval "$1=\$new_value"
}

# runtime configuration management
function replace_or_add_config() {
  if grep -q "^$1=" "$CLOUDFLOW_CONFIG"; then
    # update the configuration line
    sed -i'.original' "s/$1=.*/$1=$2/" "$CLOUDFLOW_CONFIG" && rm "$CLOUDFLOW_CONFIG".original
  else
    echo "$1=$2">>"$CLOUDFLOW_CONFIG"
  fi
}

function add_cfn_config_parameter() {
  config_file=$1
  key=$2
  value=\"$3\"
  jq ".Parameters.$key = $value" "$config_file" > tmp.$$.json && mv tmp.$$.json "$config_file"
}

function delete_cfn_config_parameter() {
  config_file=$1
  key=$2
  jq "del(.Parameters.$key)" "$config_file" > tmp.$$.json && mv tmp.$$.json "$config_file"
}

function setup_aws_profile() {
  # shellcheck source=../config.conf
  source $CLOUDFLOW_CONFIG
  export AWS_PROFILE="$AWS_PROFILE"
  export AWS_DEFAULT_REGION="$AWS_REGION"
  export AWS_DEFAULT_OUTPUT="json"
}

# bootstrapping a generator is needed within the init function
function bootstrap_generator_artifacts() {
  echo -e "\e[34mBOOTSTRAP_INFO: Creating the project template: ${CLOUDFLOW_GENERATOR_NAME} \e[0m"

  # adding runtime parameters to stack configuration
  add_cfn_config_parameter "$STACK/live_config.json" "ProjectTemplate" "$CLOUDFLOW_GENERATOR_NAME"


  # packaging the current repository into ./tmp
  mkdir -p $PROJECT_TEMPLATES "tmp/$CLOUDFLOW_GENERATOR_NAME"
  rm -rf "tmp/$CLOUDFLOW_GENERATOR_NAME"/*
  cp -r ./*[^tmp] "tmp/$CLOUDFLOW_GENERATOR_NAME/" && cp .gitignore "tmp/$CLOUDFLOW_GENERATOR_NAME/"
  # replacing the readme
  mv "tmp/$CLOUDFLOW_GENERATOR_NAME/GENERATOR_README.md" "tmp/$CLOUDFLOW_GENERATOR_NAME/README.md"
  # preparing the workspace
  cleanup="Y"
  try-except "mkdir $PROJECT_TEMPLATES/$CLOUDFLOW_GENERATOR_NAME" \
  1 \
  "read -rp \"The file $PROJECT_TEMPLATES/$CLOUDFLOW_GENERATOR_NAME already exists, overwrite it? Y/[n] \" \"cleanup\" "
  if [[ "$cleanup" != "Y" ]]; then abort; fi
  rm -rf "$PROJECT_TEMPLATES/${CLOUDFLOW_GENERATOR_NAME:?}"
  mv "tmp/$CLOUDFLOW_GENERATOR_NAME" "$PROJECT_TEMPLATES"
  
  echo -e "\e[34mBOOTSTRAP_INFO: Building code-artifacts locally\e[0m"
  ./build.sh

  echo -e "\e[34mBOOTSTRAP_INFO: Uploading code-artifacts\e[0m"
  aws s3 sync target "s3://$BUILD_ARTIFACTS_BUCKET/$CLOUDFLOW_GENERATOR_NAME/master"

  echo -e "\e[34mBOOTSTRAP_INFO: Performing cleanup\e[0m"
  rm -rf "$PROJECT_TEMPLATES/${CLOUDFLOW_GENERATOR_NAME:?}"
  rm -rf tmp/*
  rm -rf target/*
  delete_cfn_config_parameter "$STACK/live_config.json" "ProjectTemplate"
}

# cloudflow cli commands
function configure() {
  # Previously configured options are default
  # shellcheck source=../config.conf
  source $CLOUDFLOW_CONFIG
  AWS_PROFILE=${AWS_PROFILE:-"default"}
  prompt_configuration_entry AWS_PROFILE
  new_default_region=$(aws --profile "$AWS_PROFILE" configure get region)
  AWS_REGION=${AWS_REGION:-"$new_default_region"}
  AWS_ACCOUNT=$(aws --profile "$AWS_PROFILE" sts get-caller-identity | jq -r .Account)

  prompt_configuration_entry AWS_REGION
  # updating default names before prompting
  BUILD_ARTIFACTS_BUCKET=${BUILD_ARTIFACTS_BUCKET:-"cloudflow-artifacts-$AWS_ACCOUNT-$AWS_REGION"}
  CLOUDFLOW_ARTIFACTS_BUCKET=${CLOUDFLOW_ARTIFACTS_BUCKET:-"codepipeline-artifact-store-$AWS_ACCOUNT-$AWS_REGION"}
  CLOUDFLOW_CLOUDTRAIL=${CLOUDFLOW_CLOUDTRAIL:-"cloudflow-cloudtrail-$AWS_REGION"}
  CLOUDFLOW_GENERATOR_NAME=${CLOUDFLOW_GENERATOR_NAME:-"cloudflow-generator"}
  prompt_configuration_entry BUILD_ARTIFACTS_BUCKET
  prompt_configuration_entry CLOUDFLOW_ARTIFACTS_BUCKET
  prompt_configuration_entry CLOUDFLOW_CLOUDTRAIL
  prompt_configuration_entry CLOUDFLOW_GENERATOR_NAME
}


function deploy_usage {
cat << USAGE >&2
usage:
  ${0##*/} deploy-project --project-name <name>

description:
  Creates/updates a CloudFlow CI/CD project based on a project template. 

options:
  --generator-version | -v <version>    Version of the project generator to use for deploying. Default is latest
  --project-template <name>             The name of a template-dir within the project-templates directory. Default is "default"
  --project-is-generator                Use this flag when the created project is a project-generator itself. See the cloudflow docu
                                        for more details on generators.
  --project-policies <key>              A key that is present in the file cloudflow/project_policies.yaml. The default key is "default"             
  --help | -h
USAGE
  exit 1
}

function deploy-project() {
  project_template="default"
  generator_version="latest"
  project_is_generator="False"
  project_policies_id="default"
  while [[ "$1" == -* ]]; do
    case "$1" in 
      --project-name)
        project_name="$2"
        check_nonempty_value project_name
        shift 2 ;;
      --project-template)
        project_template="$2"
        check_nonempty_value project_template
        shift 2 ;;
      --project-policies)
        project_policies_id="$2"
        check_nonempty_value project_policies_id
        shift 2 ;;
      --project-is-generator)
        project_is_generator="True"
        shift 1;;
      --generator-version | -v)
        generator_version="$2"        
        check_nonempty_value generator_version
        shift 2 ;;
      --help | -h)
        deploy_usage;;
      *) 
        echo "ERROR: Unknown option $1"
        deploy_usage
    esac
  done

  if [[ -z $project_name ]]; then "DEPLOY_ERROR: project-name cannot be empty" && exit 1; fi

  project_policy_arns=$(yq -r ".$project_policies_id" cloudflow/project_policies.yaml)
  if [[ -z $project_policy_arns ]]; then 
    echo "DEPLOY_ERROR: empty project policies under key $project_policies_id in cloudflow/project_policies.yaml"
    exit 1
  fi

  setup_aws_profile

  aws cloudformation deploy \
  --template-file $STACK/stack.yaml \
  --stack-name "$project_name" \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --no-fail-on-empty-changeset \
  --parameter-overrides "BuildArtifactsBucket=$BUILD_ARTIFACTS_BUCKET" \
                        "ProjectName=$CLOUDFLOW_GENERATOR_NAME" \
                        "ProjectTemplate=$project_template" \
                        "ProjectPolicyArns=$project_policy_arns" \
                        "ProjectIsGenerator=$project_is_generator" \
                        "ProjectVersion=$generator_version" \
                        "BranchName=master" \
                        "Stage=master"
  aws cloudformation update-termination-protection --enable-termination-protection --stack-name "$project_name" 
}

function init_usage {
cat << USAGE >&2
usage:
  ${0##*/} init [options]

description:
  Configure and initialize CloudFlow and create a CI/CD projects generator.
  Executing this will create an AWS CloudTrail and S3 Buckets if they don't already exist in the configured account.

options:
  --generator-only              Don't deploy the initial resources. 
                                Use this option if you already initialized the configured cloudflow resources in your account.
  --no-generator                Don't deploy a cloudglow generator to your account. 
                                Use this option if you want to manage projects directly from this repository 
  --default-config | -d         Use previously created configuration. You should have called the init or configure command before using this flag
  --help | -h                   
USAGE
  exit 1
}

function init() {
  configure=true
  deploy_initial_resources=true
  deploy_generator=true
  while [[ "$1" == -* ]]; do
    case "$1" in
      --generator-only)
        shift
        deploy_initial_resources=false;;     
      --no-generator)
        shift
        deploy_generator=false;;
      -d | --default-config)
        shift
        configure=false ;; 
      -h | --help)
        init_usage ;;
      *) 
        echo "ERROR: Unknown option $1"
        init_usage
    esac
  done

  if $configure; then configure; fi
  setup_aws_profile

  if $deploy_initial_resources; then
    CFL_INITIAL_STACK_NAME="cloudflow-init"
    echo -e "\e[32mINIT_INFO: Deploying initial resources\e[0m"
    aws cloudformation deploy \
      --no-fail-on-empty-changeset \
      --stack-name "$CFL_INITIAL_STACK_NAME" \
      --template-file cloudflow/initial_resources.yaml \
      --parameter-overrides "BuildArtifactsBucket=$BUILD_ARTIFACTS_BUCKET" \
                            "CloudflowArtifactsBucket=$CLOUDFLOW_ARTIFACTS_BUCKET" \
                            "CloudTrail=$CLOUDFLOW_CLOUDTRAIL"
    aws cloudformation update-termination-protection --enable-termination-protection --stack-name "$CFL_INITIAL_STACK_NAME" 
  fi

  if $deploy_generator; then
    bootstrap_generator_artifacts
    
    echo -e "\e[32mINIT_INFO: Deploying the generator $CLOUDFLOW_GENERATOR_NAME\e[0m"
    deploy-project --project-name "$CLOUDFLOW_GENERATOR_NAME" --project-template "$CLOUDFLOW_GENERATOR_NAME"  --project-is-generator
  fi
}

# main entry point
case "$1" in
  init)
    shift
    init "$@" 
    ;;
  configure)
    shift
    configure "$@"
    ;;
  deploy-project)
    shift
    deploy-project "$@"
    ;;
  *) 
    echo "ERROR: unknown command $1"
    usage
esac