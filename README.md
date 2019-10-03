# CloudFlow

This repository contains a framework for gitflow-like CI/CD of AWS Infrastructure and all its dependencies. After initializing
CloudFlow in your AWS account you will be able to create projects. A CloudFlow CI/CD project is represented by the diagram below.
![](images/project_architecture.png)

It contains a CodeCommit repository that is connected to
pipelines for building, deploying, testing, and maintaining CloudFormation stacks together with their dependencies on commits.

## Why should I use it?

Using CloudFlow is extremely simple and can enormously boost a cloud-developer's productivity! Some of the advantages of CloudFlow over other approaches are the following:

1) No overhead and no external tools are needed to set it up. Only AWS services are used.
2) Nested stacks are supported.
3) All artifacts needed in a stack can be kept in a single repository.
4) It is easy to share artifacts across projects.
5) Build, deployment and testing happen on commit.
6) You have the option to create and customize your own project generator

Once a project is generated, the recipient of the project can focus on developing CloudFormation templates, code, scripts for lambda functions and in fact any kind of artifact needed for the stack. The CloudFlow pipelines will take care of packaging the dependencies, deploying and testing the resulting stack and cleaning up, all triggered by commits.

On top of that the AWS services that CloudFlow uses are essentially free (or at least really cheap).

## Initializing CloudFlow

Clone this repository, cd into it and call

```bash
./cloudflow/bin/cfl.sh init
```

After receiving the prompted input, CloudFlow will create its initial resources and a project generator in your account. If you
do not wish to use your own CloudFlow generator, you can use the command

```bash
./cloudflow/bin/cfl.sh init --no-generator
```

instead.

## Creating CloudFlow projects

 Using your own generator within your AWS Account is the recommended way to create CloudFlow projects, since this way you will be benefitting from CI/CD of CI/CD (more on that in [Advanced Topics](#advanced-topics)).
A generator can be created either directly through the init command or by calling

```bash
./cloudflow/bin/cfl.sh init --generator-only
```

The latter command will only succeed if you have initialized the necessary resources before. If you have created a project generator, clone it and call

```bash
./cloudflow/bin/cfl.sh deploy-project --project-name <name>
```

You might want to add a list of policies for your project in ```cloudflow/project_policies.yaml``` and pass the key to them through the ```--project-policies``` flag when creating the project.

If you do not wish to work on your own generator, feel free to manage the policies and call the same command from this repository instead.

You are done! Enjoy developing infrastructure as code in a modular way benefitting from automatic tests and all the other CI/CD niceties
that you know from usual code ;)

### TL;DR

Call

```bash
./cloudflow/bin/cfl.sh deploy-project --project-name <name>
```

either from this repo after initializing or from your own generator in CodeCommit.

## CloudFlow Roles

One of the goals of CloudFlow is the separation of concern and responsibility. For that CloudFlow offers two distinct roles. One is the generator maintainer, let's call it the Admin, and the other is the project recipient, let's call it the DevOp.

### The CloudFlow Admin

The Admin manages one or multiple CloudFlow generators. They can do the following:

  1) Create and update projects and their deployment pipelines
  2) Control the ressources that can be deployed from the created project by managing permissions
  3) Choose where the project artifacts will be uploaded to
  4) Develop the CloudFlow generators which will update themselves on release

### The CloudFlow DevOp

The DevOp is the recipient of a CloudFlow project. They have control over the project's artifacts and the build process. The build process can be customized by adjusting ```buildspec.yaml```. By default the script and
configuration ```build.sh``` and ```build.conf``` are used during the build. On commit to different branches
all artifacts will be built, versioned and uploaded to S3. On commit to branches starting with
"feature/" the stack parametrized by the develop config will be deployed, tested and deleted.
On merging to the develop branch, which has to be created at the very beginning, the develop stack will be updated. This way the DevOp will know that an update can be safely performed on the live stack. Finally, on merging develop to master the live stack is updated. The project version should be changed when performing merges to develop and especially to master, since the latter is a release of the stack and all artifacts within the project.

It is easy to reference released artifacts across all projects. This modularity and code-sharing is one of the main ideas behind CloudFlow. For more information on referencing artifacts see [Advanced Topics](#advanced-topics)

## Repository Structure

tba

## Advanced Topics

tba
