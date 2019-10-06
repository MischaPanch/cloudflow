# CloudFlow Project Generator

This repository contains a generator of CI/CD projects and is itself part of a [CloudFlow](https://github.com/MischaPanch/cloudflow) Generator stack. A project generator is itself a CI/CD project, which means that artifacts will be uploaded on commit and stacks will be automatically deployed. There are two main differences between a generator and a normal [CloudFlow project](https://github.com/MischaPanch/cloudflow/blob/master/project-templates/default/README.md):

- The Generator stack is deployed multiple times, as CI/CD projects are generated with it. Therefore, a dedicated deployment mechanism needs to exist for it. By default this mechanism is the "CloudFlow cli", i.e. the script `cloudflow/bin/cfl.sh`.
- While commits to feature branches will create a default project and commits to develop will update a default project, commits to master will __update the generator stack itself__. This means that when a change of the pipelines is commited to master, the existing pipelines of the generator stack will update themselves. Since the generator creates CI/CD projects, this mechanism could be called CI/CD of CI/CD.

## Suggested Development Workflow for Generators

Successful builds and deployments on commits to feature branches are a sign that projects can be successfully created. After a merge to develop, a default project (the develop stack of the generator) will be updated. This is a check, whether your changes can be rolled out to already existing projects.

After committing changes to develop, the pipelines of the default project should be tested manually by commiting changes to it's feature, develop, and master branches. This ensures that your pipelines work as intended. Thus, as a generator developer it might be useful to have a local clone of the developStack repository.

Finally a merge to master will result in an update of the generators CI/CD pipelines. Thereby the generator always uses the latest released version of the pipelines for itself.

## The CloudFlow CLI

By default this repository contains the CloudFlow CLI. You might have to turn it into an executable first by calling

```bash
chmod +x cloudflow/bin/cfl/sh
```

Apart from the `init` and `deploy-project` commands, the cli contains the `deploy-generator` command. This will create a new generator based on the __current generator__, i.e. on this repository. It can be useful to work with different generators when creating projects for mutliple purposes or teams.

## Deployment Policies

As a manager of a project generator, you have the role of a [CloudFlow Admin](https://github.com/MischaPanch/cloudflow#the-cloudflow-admin). Adjust the policies in `cloudflow/project_policies.yaml` according to your needs and control which resources the generated projects are allowed to deploy. Once a project is generated, its deployment policies can be adjusted either by updating the project with the cli or by directly manipulating the corresponding parameter in the ssm parameter store.

## Deleting Projects

Since a project contains a repository with code, by default the deletion prevention for projects is activated. You will have to deactivate it in order to delete a project. Moreover, due to racing conditions the ssm parameter with the project's policies has to be retained when deleting the stack. If you want to get rid of it, delete it manually through the parameter store.

## Additional Information

If you have created a generator in your account, it belongs to you - CloudFlow was just used to give you a headstart into CI/CD. This has the benefits that you have absolute freedom in designing your own pipelines and workflows. However, in case you want to make use of updates to the official version of CloudFlow, it might be a good idea to not depart too much from the its general concepts and technologies.
