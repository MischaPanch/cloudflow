# CloudFlow

This repository contains a framework for gitflow-like CI/CD of AWS Infrastructure and all its dependencies. After initializing
CloudFlow in your AWS account you will be able to create projects. A CloudFlow project will contain a repository that is connected
pipelines for building, deploying, testing, and maintaining CloudFormation stacks together with their dependencies on commits to
the project's repository.

## Why should I use it?

Using CloudFlow is extremely simple and can enormously boost a cloud-developer's productivity!
No overhead and no external tools are needed to set it up - only AWS services like CodeBuild and CodePipeline are used.
Once a project is generated for a developer, the recipient of the project can focus on developing CloudFormation templates, code, scripts for lambda functions and in fact any kind of artifact needed in AWS. The CloudFlow pipelines will take care of packaging the dependencies, deploying and testing the resulting stack and cleaning up.

On top of that the AWS services that CloudFlow uses are essentially free (or at least really cheap)

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

 Using your own generator within your AWS Account is the recommended way for creating CloudFlow projects, since this way you will be benefitting from CI/CD of CI/CD (more on that in the Advanced Topics section).
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

You are done! Enjoy developping infrastructure as code in a modular way benefitting from automatic tests and all the other CI/CD niceties
that you know from usual code ;)

### TL;DR

Call

```bash
./cloudflow/bin/cfl.sh deploy-project --project-name <name>
```

either from this repo after initializing or from your own generator in CodeCommit.

## CloudFlow Roles

A core concept in CloudFlow are two distinct roles of it's users. One is the generator maintainer, lets call him Admin, and the other is the project recipient, lets call him DevOp. 

### The CloudFlow Admin

The Admin manages one or multiple CloudFlow generators. He/she can do the following:

  1) Create and update projects and their deployment pipelines
  2) Control the ressources that can be deployed from the created project by managing permissions
  3) Choose where the project artifacts will uploaded to
  4) Develop the CloudFlow generators which will update themselves on release

### The CloudFlow DevOp

The DevOp is the recipient of a CloudFlow project. He/she has has control over the project's artifacts and the build process. The build process can be customized by adjusting buildspec.yaml, by default the script and
configuration ```build.sh``` and ```build.conf``` are used during the build. On commit to different branches
all artifacts will be build, versioned and uploaded to S3. On commit to branches starting with 
"feature/" the stack parametrized by the develop config will be deployed, tested and deleted. 
On merging to the develop branch, which has to be created at the very beginning, the develop stack will be updated. This way the DevOp will know that an updated can be safely performed on the live stack. Finally, on merging develop to master the live stack is updated. The project version should be changed when performing merges to develop and especially to master, since the latter is a release of the stack and all artifacts within the project.

It is easy to reference artifacts released that were released across all projects. This modularity and code-sharing is one of the main ideas behind CloudFlow.

## Repository Structure

tba

## Advanced Topics

tba