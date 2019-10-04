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
  deploy-generator    Create a project generator based on the current repository.
  configure           Set essential deployment and init configuration. 
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

# Path configuration
# shellcheck source=../../build.conf
source build.conf
STACK=${STACK:-"cloudformation/stack"}
PROJECT_TEMPLATES=${PROJECT_TEMPLATES:-"project-templates"}

CLOUDFLOW_CONFIG="cloudflow/config.conf"
# shellcheck source=../config.conf
source $CLOUDFLOW_CONFIG

# hardcoded constant names
BOOTSTRAP_GENERATOR="cfl-bootstrap"
CFL_INITIAL_STACK_NAME="cloudflow-init"

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
  replace_or_add_cfl_config "$1" "$new_value"
  # and set the environment variable to its new value
  eval "$1=\$new_value"
}

# runtime configuration management
function replace_or_add_cfl_config() {
  if grep -q "^$1=" "$CLOUDFLOW_CONFIG"; then
    # update the configuration line
    sed -i'.original' "s/$1=.*/$1=$2/" "$CLOUDFLOW_CONFIG" && rm "$CLOUDFLOW_CONFIG".original
  else
    echo "$1=$2">>"$CLOUDFLOW_CONFIG"
  fi
}

function add_stack_config_parameter() {
  config_file=$1
  key=$2
  value=\"$3\"
  jq ".Parameters.$key = $value" "$config_file" > tmp.$$.json && mv tmp.$$.json "$config_file"
}

function delete_stack_config_parameter() {
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

# used for bootstrapping a cloudflow generator
function bootstrap_generator_artifacts() {
  setup_aws_profile
  bootstrap_generator_name="$1"
  echo -e "\e[34mBOOTSTRAP_INFO: Creating the project template: $bootstrap_generator_name \e[0m"

  # adding runtime parameters to stack configuration
  add_stack_config_parameter "$STACK/live_config.json" "ProjectTemplate" "$bootstrap_generator_name"

  # packaging the current repository into ./tmp
  mkdir -p $PROJECT_TEMPLATES "tmp/$bootstrap_generator_name"
  rm -rf "tmp/$bootstrap_generator_name"/*
  rsync --recursive --exclude=tmp --exclude=images \
  ./* "tmp/$bootstrap_generator_name/" && cp .gitignore "tmp/$bootstrap_generator_name/"

  ( 
    # preparing the generator
    cd "tmp/$bootstrap_generator_name"
    replace_or_add_cfl_config "GENERATOR_NAME" "$1" 
    mv "GENERATOR_README.md" "README.md"
  )
  # preparing the workspace
  cleanup="Y"
  try-except "mkdir $PROJECT_TEMPLATES/$bootstrap_generator_name" \
  1 \
  "read -rp \"The file $PROJECT_TEMPLATES/$bootstrap_generator_name already exists, overwrite it? Y/[n] \" \"cleanup\" "
  if [[ "$cleanup" != "Y" ]]; then abort; fi
  rm -rf "$PROJECT_TEMPLATES/${bootstrap_generator_name:?}"
  mv "tmp/$bootstrap_generator_name" "$PROJECT_TEMPLATES"
  
  echo -e "\e[34mBOOTSTRAP_INFO: Building code-artifacts locally\e[0m"
  ./build.sh

  echo -e "\e[34mBOOTSTRAP_INFO: Uploading code-artifacts\e[0m"
  aws s3 sync target "s3://$BUILD_ARTIFACTS_BUCKET/$bootstrap_generator_name/master"

  echo -e "\e[34mBOOTSTRAP_INFO: Performing cleanup\e[0m"
  delete_stack_config_parameter  "$STACK/live_config.json" "ProjectTemplate"
  rm -rf "$PROJECT_TEMPLATES/${bootstrap_generator_name:?}"
  rm -rf tmp/*
  rm -rf target/*
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
  BUILD_ARTIFACTS_BUCKET=${BUILD_ARTIFACTS_BUCKET:-"cfl-build-artifacts-$AWS_ACCOUNT-$AWS_REGION"}
  CLOUDFLOW_ARTIFACTS_BUCKET=${CLOUDFLOW_ARTIFACTS_BUCKET:-"cfl-artifact-store-$AWS_ACCOUNT-$AWS_REGION"}
  CLOUDFLOW_CLOUDTRAIL=${CLOUDFLOW_CLOUDTRAIL:-"cfl-cloudtrail-$AWS_REGION"}
  prompt_configuration_entry BUILD_ARTIFACTS_BUCKET
  prompt_configuration_entry CLOUDFLOW_ARTIFACTS_BUCKET
  prompt_configuration_entry CLOUDFLOW_CLOUDTRAIL
}


function deploy_usage {
cat << USAGE >&2
usage:
  ${0##*/} deploy-project --project-name <name>

description:
  Creates/updates a CloudFlow CI/CD project based on a project template. 

options:
  --project-template <name>             The name of a template-dir within the project-templates directory. Default is "default"
  --generator-version | -v <version>    Version of the present project generator to use for deploying. Default is latest
  --project-is-generator                Use this flag when the created project is a project-generator itself. 
                                        See the cloudflow documentation for more details on generators.
  --project-policies <key>              A key that exists in the file cloudflow/project_policies.yaml. Default is "default"             
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

  generator_name=${GENERATOR_NAME:-$BOOTSTRAP_GENERATOR}

  check_nonempty_value project_name

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
                        "ProjectName=$generator_name" \
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
  --default-config | -d         Use previously created configuration. You should have called the init or configure command before using this flag
  --help | -h                   
USAGE
  exit 1
}

function init() {
  configure=true
  while [[ "$1" == -* ]]; do
    case "$1" in
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

  echo -e "\e[32mINIT_INFO: Deploying initial resources\e[0m"
  aws cloudformation deploy \
    --no-fail-on-empty-changeset \
    --stack-name "$CFL_INITIAL_STACK_NAME" \
    --template-file cloudflow/initial_resources.yaml \
    --parameter-overrides "BuildArtifactsBucket=$BUILD_ARTIFACTS_BUCKET" \
                          "CloudflowArtifactsBucket=$CLOUDFLOW_ARTIFACTS_BUCKET" \
                          "CloudTrail=$CLOUDFLOW_CLOUDTRAIL"
  aws cloudformation update-termination-protection --enable-termination-protection --stack-name "$CFL_INITIAL_STACK_NAME"

  bootstrap_generator_artifacts "$BOOTSTRAP_GENERATOR"
}

function deploy_generator_usage {
cat << USAGE >&2
usage:
  ${0##*/} deploy-generator --generator-name <name>

description:
  Creates a CloudFlow CI/CD project generator based on the current repository. 

options:            
  --help | -h
USAGE
  exit 1
}

function deploy-generator() {
  while [[ "$1" == -* ]]; do
    case "$1" in
      --generator-name)
        generator_name="$2"
        shift 2 ;;
      -h | --help)
        init_usage ;;
      *) 
        echo "ERROR: Unknown option $1"
        init_usage
    esac
  done

  check_nonempty_value generator_name

  # This env variable is needed within the deploy-project command
  GENERATOR_NAME="$generator_name"
  bootstrap_generator_artifacts "$generator_name"
  deploy-project --project-name "$generator_name" --project-template "$generator_name"  --project-is-generator --project-policies "generator"
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
  deploy-generator)
  shift
  deploy-generator "$@"
  ;;
  *) 
    echo "ERROR: unknown command $1"
    usage
esac