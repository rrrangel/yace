# YACE Terraform Infrastructure

This repository contains the Terraform configuration for deploying Yet Another CloudWatch Exporter (YACE) on AWS ECS Fargate.

## Prerequisites

- Terraform >= 1.0.0
- AWS CLI configured
- AWS account with appropriate permissions

## Repository Structure

```
project/
├── main.tf # Main Terraform configuration
├── variables.tf # Variable definitions
├── outputs.tf # Output definitions
├── config/
│ ├── config.yml # YACE configuration
│ └── credentials # AWS credentials
```

### The config.yml file:

- Monitors EC2 instances for CPU and Memory metrics
- Uses a 5-minute period (300 seconds) for data collection
- Includes key metrics like CPUUtilization, MemoryUtilization, and - Status Checks
- Will discover EC2 instances tagged with any Environment value
- Uses the InstanceId dimension for metrics

### The credentials file:

- Uses the ECS container's IAM role credentials
- This is an approach for ECS tasks rather than storing static credentials

#### Note: The `${AWS_REGION}` in the config.yml will need to be replaced with your actual AWS region (e.g., us-west-2) or you can set it as an environment variable in your ECS task definition.

### To use this configuration:

- Ensure that you have your AWS config set properly (you can verify with the following):
```
aws sts get-caller-identity
```
- Export the AWS conig to variables to be used
```
export AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)
export AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key)
export AWS_DEFAULT_REGION=$(aws configure get region)
```

- Create your YACE configuration file at config/config.yml
- Create your AWS credentials file at config/credentials
- Initialize Terraform:

`terraform init`

- Apply the configuration (add the variables as needed to ensure that terraform knows what to use):

`terraform plan -var="aws_region=$AWS_DEFAULT_REGION"`  
`terraform apply -var="aws_region=$AWS_DEFAULT_REGION"`

Or you can run the following:

`
terraform plan -var="aws_region=$AWS_DEFAULT_REGION" -out=tfplan
`

and will see something like the following at the end of the plan:

```
Saved the plan to: tfplan

To perform exactly these actions, run the following command to apply:
    terraform apply "tfplan
```

Then you can run:

`terraform apply tfplan`

After deployment, get the ALB DNS name from the outputs:

`terraform output alb_dns_name`

## Accessing the Exporter
Access the YACE metrics endpoint through:

`http://[alb_dns_name]:5000/metrics`

## Clean Up
To destroy the infrastructure:

`terraform destroy`

## Local Testing
Test YACE locally before deployment:

```
docker run -d --rm \
  -v $PWD/config/credentials:/exporter/.aws/credentials \
  -v $PWD/config/config.yml:/tmp/config.yml \
  -p 5000:5000 \
  --name yace ghcr.io/nerdswords/yet-another-cloudwatch-exporter:v0.27.0
```
