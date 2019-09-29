#!/usr/bin/env bash
shopt -s nullglob
set -eo pipefail

function usage {
  cat << USAGE >&2
usage:
  ${0##*/}

optional parameters:
  -h help

description:
  Packages cloudformation artifacts like templates, lambdas and archives and puts the result into the target directory.
  Paths to different resources are configured within the build.conf file.

  INFO: This script should be called from the project's root directory during the build phase.

requires:
  aws cli >= 1.16.212
  jq
  zip
USAGE
  exit 1
}

while getopts "h" opt ; do
    case $opt in
        h) usage ;;
        \?) echo "Invalid option: -$OPTARG" >&2 && usage;;
    esac
done

shift $((OPTIND-1))
[[ $# -ne 0 ]] && usage

# Configurations
# shellcheck source=build.conf
source build.conf
CFN_TEMPLATE_SNIPPETS=${CFN_TEMPLATE_SNIPPETS:-"cloudformation/templates"}
STACK=${STACK:-"cloudformation/stack"}
LAMBDAS_PATH=${LAMBDAS_PATH:-"lambda"}

PROJECT_VERSION=$(jq -r .Parameters.ProjectVersion "$STACK/develop_config.json")
if [[ -z "$PROJECT_VERSION" ]]; then
  echo "BUILD_ERROR: provide the paramater $PROJECT_VERSION in  $STACK/develop_config.json" && exit 1
fi


# Target path configuration. These paths are used by CloudFlow pipelines. Do not adjust them unless you know what you're doing
# The target has to be the same as in the buildspec.yaml

PROJECT_ROOTDIR=$(pwd)
TARGET="$PROJECT_ROOTDIR/target/$PROJECT_VERSION"
TARGET_LATEST="$PROJECT_ROOTDIR/target/latest/"
TARGET_CFN_TEMPLATES="$TARGET/cloudformation/templates"
TARGET_STACK="$TARGET/cloudformation"
TARGET_LAMBDA="$TARGET/lambda"

function validate_template() {
    aws cloudformation validate-template --template-body "file://$1" 1>/dev/null 
}

function replace_extension() {
    [[ $# -ne 2 ]] && echo -e "\e[31mBUILD_ERROR: failed to replace extension in $1: need 2 arguments but $# were given" >&2 && exit 2
    [[ -z $2  ]] && echo -e "\e[31mBUILD_ERROR: failed to replace extension in $1:, extension cannot be empty" >&2 && exit 2

    filename="$(basename -- "$1")"
    ext="$2"
    filename="${filename%.*}"
    [[ -z $filename  ]] && echo -e "\e[31mBUILD_ERROR: failed to replace extension in $1:, filename cannot be empty" >&2 && exit 2
    echo "${filename}.$ext"
}

echo "BUILD_INFO: Building current project with version $PROJECT_VERSION"

echo "BUILD_INFO: Preparing the workspace"
rm -rf "${TARGET:?}"/* "${TARGET_LATEST:?}"/*
mkdir -p "$TARGET_LATEST" \
"$TARGET_CFN_TEMPLATES" \
"$TARGET_STACK" \
"$TARGET_LAMBDA" 

# stack
echo "BUILD_INFO: Packaging the stack artifact"
validate_template "$STACK/stack.yaml"
# validate the configuration files
jq empty "$STACK/live_config.json"
jq empty "$STACK/develop_config.json"
zip --junk-paths "$TARGET_STACK/stack.zip" "$STACK"/*

# cfn templates
for template in "$CFN_TEMPLATE_SNIPPETS"/*; do
    echo "BUILD_INFO: Packaging $template"
    validate_template "$template"
    cp "$template"  "$TARGET_CFN_TEMPLATES"
done

# lambda source code
echo "BUILD_INFO: Packaging Lambda artifacts"
( cd "$LAMBDAS_PATH"
for lambda in ./*[^"common"]; do
  artifact_name=$(replace_extension "$lambda" zip)
  zip -r "$TARGET_LAMBDA/$artifact_name" "$lambda" "common"/*
done
)

echo "BUILD_INFO: Updating the latest version "
if [[ "$PROJECT_VERSION" != "latest" ]]; then
  cp -r "$TARGET"/* "$TARGET_LATEST"
fi