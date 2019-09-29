# CLOUDFLOW

This repository contains a framework for gitflow-like CI/CD of AWS Infrastructure and all its dependencies. After initializing
CloudFlow in your AWS account you will get a stack containing a CloudFlow project generator. A generated project will contain
pipelines for building, deploying, testing, and maintaining CloudFormation stacks together with their dependencies on commits to
the project's repository.

## Why should I use it'?'

Using CloudFlow is extremely simple and can enormously boost a cloud-developers productivity!
No overhead and no external tools are needed to set it up. Once a project is generated for a developer, the recipient can
focus on developing CloudFormation templates, code, scripts for lambda functions and in fact any kind of artifact needed in AWS. The CloudFlow pipelines will take care of packaging the dependencies, deploying and testing the resulting stack and cleaning up.

On top of that the AWS services that CloudFlow uses are essentially free (or at least really cheap)

## Initializing CloudFlow

Clone this repository, cd into it and call

```bash
./cloudflow/bin/cfl.sh init
```

After receiving the prompted input, CloudFlow will create its initial resources and a project generator in your account.

## Creating CloudFlow projects

Clone the previously created project generator and call

```bash
./cloudflow/bin/cfl.sh deploy-project --project-name <name>
```

You are done! Enjoy developping infrastructure as code in a modular way benefitting from automatic tests and all the other CI/CD niceties
that you know from usual code ;)

## Repository Structure

## Advanced Topics
