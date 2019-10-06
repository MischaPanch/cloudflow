# Default CloudFlow Project

This repository is as part of a [CloudFlow](https://github.com/MischaPanch/cloudflow) CI/CD project. It contains a small stack meant for demonstration puproses.

## The CI/CD workflow

On commits to various branches your stack will be automatically built, uploaded, deployed and tested. 

You should always have a master and develop branch and create branches called "feature/*" off develop for new features. 

When a new feature is finished and all tests have passed, increase the ProjectVersion in `develop_config.json` and merge the feature branch to develop. 

For releasing a new version, increase the _ProjectVersion_ in `live_config.json` and merge the develop branch into master.

## Under the hood

Multiple things happen after you commit something to a branch. Here are some details that are relevant for working on a CloudFlow project.

### Build

Builds of each branch are triggered by commits. The build process is defined by the `buildspec.yaml`. By default it will perform a local merge with the develop branch before calling `build.sh`. You should adjust the `build.sh` and `build.conf` files in order to control you the build process. The build artifacts should always land in `./target`.

### Upload and Referencing of Dependencies

The result of the build will be uploaded to the BuildArtifactsBucket under the key `<ProjectName>/<BranchName>/<ProjectVersion>`. Additionally, on each commit the "latest" version on the corresponding branch will be updated. You can reference artifacts within your project by using the corresponding parameters in your `stack.yaml` (an example for such referencing can be found e.g. in the [CloudFlow generator stack](https://github.com/MischaPanch/cloudflow/blob/feature/separate-generator-creation/cloudformation/stack/stack.yaml)).

For referencing artifacts that were released in other CloudFlow projects, simply substitute the corresponding _ProjectName_ and _ProjectVersion_ and use "master" as _BranchName_.

### Deployment

The deployment is triggered by an upload of your stack which in turn is triggered by commits. The resulting stack name will be  called `<ProjectName>-<BranchName>Stack`. The deployment process is slightly different for each branch-type

1) On commits to feature branches the stack will be deployed with the `develop_config.json`, a test will be performed and the stack will be deleted.

2) On commits to the develop and master branches the corresponding stack (with the `develop/live_config.json` config) will be updated and a test will be performed. If the stack cannot be updated, you will have to delete it manually before redeploying.

Thus, if on merging a feature branch on develop leads to a failing update, it means that the new feature cannot be rolled out to the master stack without a downtime.

### Testing

Part of your stack is the Lambda function within the template `ExecuteTest` which will be called by the CI/CD pipelines after deployment. This is a good place to perform integration or smoke tests of your infrastructure.

## Get started

In case you want to execute local builds, you have to make `build.sh` executable, e.g. by calling `chmod +x build.sh`.
