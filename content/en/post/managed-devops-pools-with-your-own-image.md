---
title: "Managed DevOps Pools with your own images"
date: 2025-03-04T00:00:00
draft: false
tags:
  - pwsh
  - azure
  - devops
  - pipelines
categories:
  - iac
  - dev
---

Today we have a DevOps topic that deserves a bit more attention. Azure DevOps has allowed you for years to create VM Scale Set backed
elastic pools. These pools allow customers to integrate into their own infrastructure better. For a while now, these Pools
are also offered as a PaaS offering `Managed DevOps Pool` (<https://learn.microsoft.com/en-us/azure/devops/managed-devops-pools/?view=azure-devops>).

In this post, we'll look at how to create a pool with Terraform and how to use custom images in your pool.

## Gallery and image

To create Gallery and Pool, I am using Terraform. Why? Because I've been using it professionally for a couple of years. Is it the best tool?
Of course not - but in that case, just look for another templating tool! It's more important to use something instead of clicking around in
the Azure Portal.

We are starting off with a slight hitch: To use a custom image in a pool, the image definition (Terraform) needs an image version (not Terraform). So, you'll not be able to deploy everything at once. Instead you can use stages and remote states or targeting. Either way, you'll need to build
an image version in between. A pool without a versioned image will remain in a failed state. That's not ideal.

The following sample needs to be updated with your resources. I will not spoonfeed you everything, you should be able to do this yourselves. This
solution should be made your own. Copying is not an art.

```hcl
# These should be separate of course
variable "resource_group_name" {
  description = "The name of the resource group in which the resources should be created"  
}

variable "location" {
  description = "The location/region where the resources should be created"  
}

module "image_gallery" {
  source  = "Azure/avm-res-compute-gallery/azurerm"
  version = "0.2.0"


  name                = "use-a-naming-module-instead"
  resource_group_name = var.resource_group_name
  location            = var.location
  description         = "Shared image gallery for build agents"

  shared_image_definitions = {
    "ubuntu-buildagent-2204" = {
      name                         = "ubuntu-22.04"
      resource_group_name          = lvar.resource_group_namea
      location                     = var.location
      os_type                      = "Linux"
      description                  = "Baseline image including build tools to be used for pipeline build agents"
      min_recommended_vcpu_count   = 2
      min_recommended_memory_in_gb = 4
      specialized                  = false
      architecture                 = "x64"
      hyper_v_generation           = "V2"

      identifier = {
        publisher = "JHP"
        offer     = "UbuntuServerPipelineAgent"
        sku       = "22.04-LTS"
      }
    }
    "ubuntu-buildagent-2404" = {
      name                         = "ubuntu-24.04"
      resource_group_name          = var.resource_group_name
      location                     = var.location
      os_type                      = "Linux"
      description                  = "Baseline image including build tools to be used for pipeline build agents"
      min_recommended_vcpu_count   = 2
      min_recommended_memory_in_gb = 4
      specialized                  = false
      architecture                 = "x64"
      hyper_v_generation           = "V2"

      identifier = {
        publisher = "JHP"
        offer     = "UbuntuServerPipelineAgent"
        sku       = "24.04-LTS"
      }
    }
  }

}

resource "azurerm_user_assigned_identity" "image_builder_identity" {
  location            = var.location
  name                = "${module.service.user_assigned_identity.name}-imagebuilder-${module.env.no_service.name}"
  resource_group_name = var.resource_group_name
}

resource "azurerm_role_definition" "image_builder" {
  assignable_scopes = [data.azurerm_subscription.current.id]
  name              = "[JHP] Azure Image Builder Service"
  scope             = data.azurerm_subscription.current.id
  permissions {
    actions = [
      "Microsoft.Compute/galleries/read",
      "Microsoft.Compute/galleries/images/read",
      "Microsoft.Compute/galleries/images/versions/read",
      "Microsoft.Compute/galleries/images/versions/write",

      "Microsoft.Compute/images/write",
      "Microsoft.Compute/images/read",
      "Microsoft.Compute/images/delete"
    ]
  }
}

resource "azurerm_role_assignment" "builder" {
  depends_on           = [azurerm_role_definition.image_builder]
  principal_id         = azurerm_user_assigned_identity.image_builder_identity.principal_id
  scope                = "${data.azurerm_subscription.current.id}/resourceGroups/${var.resource_group_name}"
  role_definition_name = "[JHP] Azure Image Builder Service"
}
```

## The Pool

With an existing image version the pool is ready in no time. We opted for the faster stateful agents. Why? At the time of writing this
post, the stateless agents were so excrutiatingly slow in picking up new jobs, that the pool was painful to work with. Image wait times
of up to 5 minutes (even with standby agents) in a team of 15 devs and 10 repos. No fun at all.

If a stateful agent is free within the grace period, the agent will be used and is ready in seconds. After two hours, the agent
will be decommissioned. This means our builds run quickly, but our devs have less ways to fill the agent with junk like
artefacts, downloads and more.

```hcl
resource "azurerm_dev_center" "dev_center" {
    location = var.location
    name = "use-a-naming-module-instead"
    resource_group_name = var.resource_group_name
}

resource "azurerm_dev_center_project" "dev_center_project" {
    location = var.location
    name = "use-a-naming-module-instead"
    resource_group_name = var.resource_group_name
    dev_center_id = azurerm_dev_center.dev_center.id
}

module "managed_devops_pool" {
  source                               = "Azure/avm-res-devopsinfrastructure-pool/azurerm"
  name                                 = "use-a-naming-module-instead"
  location                             = var.location
  resource_group_name                  = var.resource_group_name
  dev_center_project_resource_id       = azurerm_dev_center_project.dev_center_project.id
  enable_telemetry                     = false
  maximum_concurrency                  = 10
  agent_profile_kind                   = "Stateful"
  agent_profile_grace_period_time_span = "00:30:00"
  agent_profile_max_agent_lifetime     = "02:00:00"

  organization_profile = {
    organizations = [
      {
        name        = "YOUR DEVOPS ORGANIZATION"
        projects    = ["YOUR OPTIONAL LIST OF PROJECTS"]
        parallelism = 10
      }
    ]
  }
  agent_profile_resource_prediction_profile = "Manual"
  agent_profile_resource_predictions_manual = {
    time_zone = "UTC"
    days_data = [
      # Sunday
      {},
      # Monday
      {
        "04:00:00" = 1
        "18:00:00" = 0
      },
      # Tuesday
      {
        "04:00:00" = 1
        "18:00:00" = 0
      },
      # Wednesday
      {
        "04:00:00" = 1
        "18:00:00" = 0
      },
      # Thursday
      {
        "04:00:00" = 1
        "18:00:00" = 0
      },
      # Friday
      {
        "04:00:00" = 1
        "18:00:00" = 0
      },
      # Saturday
      {}
    ]
  }
  fabric_profile_sku_name = "Standard_DS3_v2" # 12800 IOPS
  fabric_profile_images = [
    {
      aliases : [
        "ubuntu-22.04/latest",
        "ubuntu-latest"
      ],
      well_known_image_name : "ubuntu-22.04/latest"
      buffer = 100
    },
    {
      aliases : [
        "windows-latest"
      ],
      well_known_image_name : "windows-2022/latest"
      buffer = "0"
    },
    {
      aliases     = ["jhp-ubuntu-22.04/latest", "jhp-ubuntu/latest"]
      resource_id = "${module.image_gallery.shared_image_definitions_resource["ubuntu-buildagent-2204"].id}/versions/latest"
      buffer = "0"
    }
  ]
}
```


## Azure Image Builder: From Zero to Custom Worker in a few steps

To create the aforementioned image version, Azure offers the free Azure Image Builder. AIB uses Hashicorp Packer, so if you're familiar with
Packer, this will be easy for you.

For me, AIB is ideal since I can rely on PowerShell and all its bells and whistles. In past projects I was able to create simple and effective pipelines. The assumption: We always have a managed identity, gallery and image definition. Updating images means updating a value in a JSON configuration file, which can be read without installing further dependencies.

With the JSONs, I'm lazy. The customizers have the same properties as `New-AzImageBuilderTemplateCustomizerObject` has parameters.

```PowerShell
param
(
    [Parameter(Mandatory = $true)]
    [string]
    $UserAssignedIdentityResourceId,

    [Parameter(Mandatory = $true)]
    [string]
    $ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]
    $Location,

    [Parameter(Mandatory = $true)]
    [string]
    $ImageDefinitionPath,

    [Parameter(Mandatory = $true)]
    [string]
    $GalleryImageResourceId,

    [Parameter(Mandatory = $true)]
    [string]
    $Publisher,

    [Parameter(Mandatory = $true)]
    [string]
    $Offer,

    [Parameter(Mandatory = $true)]
    [string]
    $Sku,

    [Parameter(Mandatory = $true)]
    [string]
    $Version,

    [Parameter(Mandatory = $true)]
    [string]
    $ImageName,

    # During Builds, increase or decrease according to your performance needs
    [Parameter()]
    [string]
    $BuildImageSize = 'Standard_D4s_v3',

    # Timeout in Minutes
    [Parameter()]
    [uint16]
    $TimeoutMinute = 60
)

$imageInfo = Get-Content $ImageDefinitionPath | ConvertFrom-Json -AsHashtable

$sourceParameters = @{
    PlatformImageSource = $true
    Publisher           = $Publisher
    Offer               = $Offer
    Sku                 = $Sku
    Version             = $Version
}
$builderSource = New-AzImageBuilderTemplateSourceObject @sourceParameters

$distributorParameters = @{
    SharedImageDistributor = $true
    GalleryImageId         = $GalleryImageResourceId
    TargetRegion           = $imageInfo.TargetRegion
    RunOutputName          = 'aib-{0:yyyyMMddHHmmss}' -f (Get-Date)
    ExcludeFromLatest      = $false
}
$sharedImageDistributor = New-AzImageBuilderTemplateDistributorObject @distributorParameters

$customizers = foreach ($customizer in $imageInfo.Customizers) {
    New-AzImageBuilderTemplateCustomizerObject @customizer
}

$aibTemplateParameters = @{
    ImageTemplateName      = $ImageName
    ResourceGroupName      = $ResourceGroup
    Source                 = $builderSource
    Distribute             = $sharedImageDistributor
    Customize              = $customizers 
    Location               = $Location
    UserAssignedIdentityId = $UserAssignedIdentityResourceId
    VMProfileOsdiskSizeGb  = $imageInfo.DiskSizeGiB
    VMProfileVmsize        = $BuildImageSize
    VMBootState            = 'Enabled'
    BuildTimeoutInMinute   = $TimeoutMinute
    ErrorAction            = 'Stop'
}

if (Get-AzImageBuilderTemplate -Name $ImageName -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue) {
    $null = Remove-AzImageBuilderTemplate -Name $ImageName -ResourceGroupName $ResourceGroup
}

$builderTemplate = New-AzImageBuilderTemplate @aibTemplateParameters

$builderTemplate | Start-AzImageBuilderTemplate
```

While the parameters might look intimidating, remember that they are used in a pipeline. Our image JSONs always look similar:

```json
{
  "DiskSizeGiB": 256,
  "TargetRegion": [
    {
      "Name": "westeurope",
      "ReplicaCount": "1",
      "StorageAccountType": "Standard_LRS"
    }
  ],
  "Customizers": [
    {
      "ShellCustomizer": true,
      "Name": "UpdateAndUpgradeUbuntu",
      "Inline": [
        "echo 'UpdateAndUpgradeUbuntu' Customizer",
        "export DEBIAN_FRONTEND=noninteractive",
        "sudo apt update -y && sudo apt upgrade -y"
      ]
    },
    {
        "...": "..."
    },
    {
      "ShellCustomizer": true,
      "Name": "InstallPwsh",
      "Inline": [
        "echo 'InstallPwsh' Customizer",
        "export DEBIAN_FRONTEND=noninteractive",
        ". /etc/os-release && wget -q https://packages.microsoft.com/config/ubuntu/$VERSION_ID/packages-microsoft-prod.deb",
        "sudo dpkg -i packages-microsoft-prod.deb",
        "rm packages-microsoft-prod.deb",
        "sudo apt update && sudo apt install -y powershell",
        "pwsh -c 'Install-Module -Name Az -Scope AllUsers -Force'"
      ]
    }
  ]
}
```

The important thing is to test your customizers first. The image build takes a long time, logs will be ready after the build is finished. It
is not very great to wait for an eternity just to see that your ancient package does not exist in Ubuntu 24.04 or that you had a typo somewhere.

## And now for the Automation

With help from Azure Pipelines we can publish our images. We are using a matrix build to quickly generate a list of images based on generic
templates. With modules like Datum or the PSFramework you could create an even more modular approach, but how many images do you really need nowadays?

I assume you've created your service connection. If not, do it! That stuff has to go to the cloud somehow, so create a managed identity or app registration with Federated Credentials. The last bit is crucial: We never want to store credentials anywhere, ever again.

Using the service connection, the build is simple. Our parameters come from the matrix and the variables, so that our pipeline consists of just
one job: Publishing the image.

```yaml
pool: 
  name: your-sweet-managed-pool
  demands:
  - ImageOverride -equals ubuntu-latest # Make sure we do not run on our customized image ;)
trigger: none

variables:
  - name: azureServiceConnection
    value: name-of-service-connection
  - name: resourceGroup
    value: image-gallery-rg
  - name: location
    value: westeurope
  - name: imageBuilderIdentityResourceId
    value: /subscriptions/.../resourcegroups/.../providers/Microsoft.ManagedIdentity/userAssignedIdentities/...

strategy:
  maxParallel: 4
  matrix:
    jhp-ubuntu-2204-buildagent:
      BaseName: jhp-ubuntu-buildagent
      ImageName: jhp-ubuntu-2204-buildagent
      ResourceId: /subscriptions/.../resourceGroups/.../providers/Microsoft.Compute/galleries/.../images/ubuntu-22.04
      Publisher: "Canonical"
      Offer: "0001-com-ubuntu-server-jammy"
      Sku: "22_04-lts-gen2"
      Version: "latest"
    jhp-ubuntu-2404-buildagent:
      BaseName: jhp-ubuntu-buildagent
      ImageName: jhp-ubuntu-2404-buildagent
      ResourceId: /subscriptions/.../resourceGroups/.../providers/Microsoft.Compute/galleries/.../images/ubuntu-24.04
      Publisher: "Canonical"
      Offer: "ubuntu-24_04-lts"
      Sku: "server"
      Version: "latest"

steps:
  - pwsh: Install-Module Az.ImageBuilder -Force
  - task: AzurePowerShell@5
    displayName: Deploy image $(ImageName)
    inputs:
      azurePowerShellVersion: LatestVersion
      azureSubscription: ${{variables.azureServiceConnection}}
      pwsh: true
      ScriptType: FilePath
      ScriptPath: ./build-agents/Start-AzureComputeGalleryDeployment.ps1
      ScriptArguments: -UserAssignedIdentityResourceId ${{variables.imageBuilderIdentityResourceId}} -ResourceGroup ${{variables.resourceGroup}} -Location ${{variables.location}} -ImageDefinitionPath (Join-Path $(Build.Repository.LocalPath) "build-agents/images/$(BaseName).json") -GalleryImageResourceId $(ResourceId) -Publisher $(Publisher) -Offer $(Offer) -Sku $(Sku) -Version $(Version) -ImageName $(ImageName)
```

Enjoy!