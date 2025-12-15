# ephemeral environment generator, that deserved it's own repo.

> spin up temporary azure environments with auto-destruction. because not everything needs to live forever.

## quick overview of what this is

terraform-based automation for creating temporary, fully-configured azure environments that automatically destroy themselves after a specified TTL (time-to-live).

perfect for:
- feature branch testing
- client demos
- proof of concepts
- temporary dev/staging environments
- anything that doesn't need to stick around

## features

- 🕐 **auto-destruction** - environments delete themselves after TTL expires
- 💰 **cost tracking** - automatic tagging and cost monitoring
- 🎯 **one-command setup** - `./create-env.sh --name feature-123`
- 🔧 **flexible configuration** - enable/disable components as needed
- 📊 **comprehensive outputs** - all connection strings and credentials
- 🧹 **automated cleanup** - cron-ready script for expired environments
- 🏷️ **proper tagging** - owner, cost center, TTL tracking

## what gets created

**base infrastructure:**
- resource group
- virtual network with subnets
- network security groups
- dns zones

**optional components:**
- postgresql flexible server + database
- app service (linux) with docker support
- azure container registry
- load balancer
- cost management exports

## prerequisites

```bash
# install azure cli
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# install terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# login to azure
az login
az account set --subscription "your-subscription-id"

# install jq for pretty output
sudo apt install jq
```

## quick start

### create an environment

```bash
# basic environment (4 hour TTL)
./create-env.sh --name feature-123

# custom TTL and owner
./create-env.sh --name demo-client --ttl 8 --owner aymen@company.com

# minimal (no database)
./create-env.sh --name api-test --no-database

# with container registry
./create-env.sh --name build-test --enable-acr

# custom docker image
./create-env.sh --name app-demo --docker-image myapp --docker-tag v1.2.3
```

### destroy an environment

```bash
./create-env.sh --name feature-123 --destroy
```

### list active environments

```bash
./create-env.sh --list
```

### check for expired environments

```bash
./create-env.sh --check-expired
```

## configuration

### using terraform directly

```bash
# create terraform.tfvars
cat > terraform.tfvars << EOF
environment_name = "my-test-env"
ttl_hours        = 4
owner            = "aymen@company.com"
location         = "westeurope"

enable_database    = true
enable_app_service = true
enable_container_registry = false
EOF

# apply
terraform init
terraform plan
terraform apply
```

### available variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `environment_name` | string | required | Environment name (lowercase, alphanumeric, hyphens) |
| `ttl_hours` | number | 4 | Time to live (1-168 hours) |
| `owner` | string | required | Owner email/username |
| `location` | string | westeurope | Azure region |
| `enable_database` | bool | true | Create PostgreSQL database |
| `enable_app_service` | bool | true | Create App Service |
| `enable_container_registry` | bool | false | Create ACR |
| `app_docker_image` | string | nginx | Docker image for app |
| `app_docker_tag` | string | latest | Docker image tag |
| `cost_center` | string | ephemeral-environments | Cost center for billing |

## automated cleanup

set up a cron job to automatically destroy expired environments:

```bash
# edit crontab
crontab -e

# add this line (runs every hour)
0 * * * * cd /path/to/ephemeral-env && ./cleanup-expired.sh --force >> cleanup.log 2>&1
```

### manual cleanup check

```bash
# dry run (see what would be deleted)
./cleanup-expired.sh --dry-run

# interactive cleanup
./cleanup-expired.sh

# forced cleanup (no prompts)
./cleanup-expired.sh --force
```

## outputs

after creation, you get:

```
Environment Created Successfully!
=================================

Environment ID: feature-123-a1b2c3
Owner: aymen@company.com
TTL: 4 hours
Destroy After: 2025-10-01T18:30:00Z

Web App URL: https://app-feature-123-a1b2c3.azurewebsites.net
Database: psql-feature-123-a1b2c3.postgres.database.azure.com

To destroy this environment:
terraform destroy -auto-approve
```

### viewing outputs later

```bash
# all outputs
terraform output

# specific output
terraform output app_service_url

# database connection string (sensitive)
terraform output -raw database_connection_string
```

## cost management

### tags applied to all resources

- `Environment` - environment name
- `Owner` - who created it
- `TTL` - time to live in hours
- `DestroyAfter` - exact timestamp for deletion
- `CostCenter` - billing/chargeback
- `AutoDestroy` - marker for cleanup automation
- `ManagedBy` - always "Terraform"

### viewing costs

```bash
# get costs for specific environment
az consumption usage list \
  --start-date 2025-10-01 \
  --end-date 2025-10-02 \
  | jq '[.[] | select(.tags.Environment=="feature-123")] | .[0].pretaxCost'

# query all ephemeral environment costs
az consumption usage list \
  --start-date 2025-10-01 \
  --end-date 2025-10-02 \
  | jq '[.[] | select(.tags.CostCenter=="ephemeral-environments")] | map(.pretaxCost) | add'
```

## architecture

```
┌─────────────────────────────────────────────┐
│         Resource Group (rg-{env-id})        │
├─────────────────────────────────────────────┤
│                                             │
│  ┌────────────────────────────────────┐   │
│  │    VNet (vnet-{env-id})            │   │
│  │  ┌──────────────────────────────┐  │   │
│  │  │  Compute Subnet (10.0.1.0/24)│  │   │
│  │  │  ┌──────────────────────┐    │  │   │
│  │  │  │   App Service        │    │  │   │
│  │  │  │   (Docker)           │    │  │   │
│  │  │  └──────────────────────┘    │  │   │
│  │  └──────────────────────────────┘  │   │
│  │  ┌──────────────────────────────┐  │   │
│  │  │  Database Subnet (10.0.2.0/24│  │   │
│  │  │  ┌──────────────────────┐    │  │   │
│  │  │  │  PostgreSQL          │    │  │   │
│  │  │  │  Flexible Server     │    │  │   │
│  │  │  └──────────────────────┘    │  │   │
│  │  └──────────────────────────────┘  │   │
│  └────────────────────────────────────┘   │
│                                             │
│  Optional:                                  │
│  - Container Registry (ACR)                 │
│  - Load Balancer + Public IP                │
│  - Private DNS Zones                        │
│                                             │
└─────────────────────────────────────────────┘
```

## common workflows

### feature branch testing

```bash
# create environment when branch is created
./create-env.sh --name feature-${BRANCH_NAME} --ttl 24

# deploy your app
az webapp deployment source config \
  --name app-feature-${BRANCH_NAME} \
  --resource-group rg-feature-${BRANCH_NAME} \
  --repo-url ${GIT_REPO} \
  --branch ${BRANCH_NAME}

# destroy when merged
./create-env.sh --name feature-${BRANCH_NAME} --destroy
```

### client demo

```bash
# create demo environment (8 hour TTL)
./create-env.sh --name demo-acme --ttl 8 --owner aymen@company.com

# get connection details
terraform output app_service_url

# extend TTL if needed
terraform apply -var="ttl_hours=16" -auto-approve
```

### load testing

```bash
# spin up temporary environment
./create-env.sh --name loadtest-$(date +%s) --ttl 2

# run tests
# ...

# automatic cleanup after 2 hours
```

## ci/cd integration

### gitlab ci example

```yaml
stages:
  - provision
  - deploy
  - cleanup

variables:
  ENV_NAME: "feature-${CI_COMMIT_REF_SLUG}"

provision:
  stage: provision
  script:
    - ./create-env.sh --name $ENV_NAME --ttl 24 --auto-approve --skip-plan
    - terraform output -json > env-outputs.json
  artifacts:
    paths:
      - env-outputs.json
  only:
    - branches
  except:
    - main

deploy:
  stage: deploy
  script:
    - APP_URL=$(jq -r '.app_service_url.value' env-outputs.json)
    - echo "Deploying to $APP_URL"
    - # your deployment steps
  dependencies:
    - provision

cleanup:
  stage: cleanup
  script:
    - ./create-env.sh --name $ENV_NAME --destroy
  when: manual
  dependencies:
    - provision
```

### github actions example

```yaml
name: Ephemeral Environment

on:
  pull_request:
    types: [opened, synchronize]

jobs:
  provision:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      
      - name: Create Environment
        run: |
          ./create-env.sh \
            --name pr-${{ github.event.pull_request.number }} \
            --ttl 24 \
            --owner ${{ github.actor }}@company.com \
            --auto-approve
      
      - name: Comment PR
        uses: actions/github-script@v6
        with:
          script: |
            const output = require('./env-outputs.json');
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `🚀 Environment deployed!\n\nURL: ${output.app_service_url.value}`
            })
```

## troubleshooting

### environment won't create

```bash
# check azure login
az account show

# verify subscription
az account list --output table

# check terraform state
terraform state list

# reinitialize
rm -rf .terraform
terraform init
```

### environment won't destroy

```bash
# force destroy
terraform destroy -auto-approve

# if that fails, manually delete resource group
az group delete --name rg-{env-id} --yes --no-wait
```

### can't connect to database

```bash
# check if database is ready
az postgres flexible-server show \
  --name psql-{env-id} \
  --resource-group rg-{env-id}

# verify network access
# database is on private endpoint, only accessible from vnet
```

### app service not responding

```bash
# check app service logs
az webapp log tail \
  --name app-{env-id} \
  --resource-group rg-{env-id}

# restart app service
az webapp restart \
  --name app-{env-id} \
  --resource-group rg-{env-id}
```

## security considerations

- database passwords are randomly generated (32 chars)
- database uses private endpoint (not public)
- nsg rules restrict ssh access (configure `allowed_ssh_source`)
- all secrets in terraform state (use remote backend with encryption)
- resource groups have delete lock prevention disabled (for auto-cleanup)

## cost estimation

typical 4-hour environment costs (westeurope):

| Component | SKU | Hourly Cost | 4h Cost |
|-----------|-----|-------------|---------|
| App Service | B1 | €0.013 | €0.052 |
| PostgreSQL | B_Standard_B1ms | €0.022 | €0.088 |
| VNet | Standard | free | free |
| NSG | Standard | free | free |
| **Total** | | **~€0.035/hr** | **~€0.14** |

*costs are approximate and vary by region (this is for belgium)*

## contributing

improvements welcome! areas for enhancement:
- support for aws/gcp
- kubernetes cluster deployment
- redis/mongodb support
- automated testing framework
- grafana/prometheus monitoring
- better notification integrations

## license

do whatever you want with it. no warranty, use at your own risk.

---

*because sometimes the best infrastructure is the one that knows when to disappear.*
