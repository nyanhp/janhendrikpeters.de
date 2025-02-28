---
title: "Managed DevOps Pools mit euren eigenen Images"
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

Heute gibt es mal ein DevOps-Thema, dem mehr Aufmerksamkeit gebührt. Azure DevOps bietet seit Jahren die Möglichkeit eine skalierbare
Build-Infrastruktur an mit sogenannten Elastic Pools zu betreiben. Dies sind Pools mit einem vom Kunden selbst betriebenen Azure VM Scale Set, und
somit Möglicheiten wie VNET-Integration um auf private Build-Ressourcen zuzugreifen. Seit einiger Zeit gibt es genau diese nun auch
als PaaS-Angebot `Managed DevOps Pool` (<https://learn.microsoft.com/en-us/azure/devops/managed-devops-pools/?view=azure-devops>).

In diesem Artikel wollen wir uns anschauen, wie ein Pool z.B. mit Terraform eingerichtet werden kann, und wie ihr eigene Images in den Pool bekommt.

## Die Gallerie und das Image

Um Gallerie und Pool aufzubauen, nehme ich Terraform. Warum? Weil ich es beruflich seit Jahren nutze. Ist es da beste Tool? Sicher nicht - aber dann sucht euch einfach ein anderes Templating-Tool! Hauptsache, ihr nutzt überhaupt eines, und klickt nicht wild im Azure Portal herum.

Zu Beginn wird es gleich unpraktisch. Damit im Pool ein custom image genutzt werden kann, muss es zu der Image-Definition (Terraform) eine Image-Version geben.
Alles in einem Rutsch könnt ihr also nicht ausbringen. Stattdessen arbeitet ihr entweder mit Stages und Remote States oder Targeting. In allen Fällen
muss das erstellte Image erst noch gebaut werden! Ohne eine Image-Version wird der Pool immer in einem failed state sein, was insbesondere bei späteren
Deployments sehr unschön ist.

Das folgende Beispiel muss um eure Ressourcen ergänzt werden! Ich möchte euch hier nicht die Lösung mit dem Löffel füttern, ein bisschen sollt
ihr auch selbst denken und euch die Lösung so erarbeiten, dass sie zu eurer Infrastruktur wird. Kopieren kann jeder.

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

## Der Pool

Mit einer existierenden Image-Version ist der Pool schnell definiert. Wir entscheiden uns für flotte Stateful Agents. Warum? Zum Zeitpunkt des Artikels
waren Stateless Agents so extrem langsam beim Aufnehmen neuer Jobs, dass sie bei Projekten mit vielen Builds unbenutzbar waren.

Stellt euch einfach Wartezeiten bis zu 5 Minuten vor, in einem Team mit 15 Entwickelnden in über 10 Repositories. Keine Freude.

Wird innerhalb der Grace Period ein freier Agent gefunden, wird dieser sogleich genutzt. Nach maximal zwei Stunden wird der Agent
jedoch abgebaut. So laufen unsere Builds zügig, aber die Entwicklerinnen haben wenig Gelegenheit, die Agenten vollzumüllen mit nicht
aufgeräumten Artefakten, Downloads und mehr.

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
      resource_id = "${module.image_gallery.shared_images_definitions_resource["ubuntu-buildagent-2204"].id}/versions/latest"
      buffer = "0"
    }
  ]
}
```


## Azure Image Builder: Mit wenigen Schritten zum eigenen Worker

Um nun die oben notwendige Image-Version zu erstellen, bietet Azure einen kostenfreien Dienst an, der im Hintergrund Hashicorp Packer nutzt: Den Azure Image Builder.

Für mich ist AIB ideal, da ich mit PowerShell arbeiten kann mit allem Komfort. Für meine vergangenen Projekte sind dabei simpelste Pipelines entstanden. Die Annahme
ist jedes Mal: Wir haben bereits eine User-Assigned Managed Identity, eine Gallery und eine Image Definition. Anpassungen an Images erfolgen in einfachen JSON-Dateien,
die ohne weitere Module direkt gelesen und verarbeitet werden können.

Bei den JSONs mache ich mir gar keine Arbeit: Die Customizer, die mein Image anpassen, entsprechen exakt den Parametern des PowerShell-Cmdlets `New-AzImageBuilderTemplateCustomizerObject`.

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

Die Parameter erscheinen etwas unhandlich. Da das Script jedoch über die Pipeline orchestriert wird, ist es nicht so tragisch. Die genutzten
Imagevorlagen sehen wie folgt aus:

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

Wichtig ist, dass ihr eure Customizer vorher einmal testet. Der Image Build dauert lange, und Protokolle gibt es erst nach Beendigung zu sehen. Nichts ist nerviger, als ewig zu warten, nur um festzustellen, dass es ein uraltes Paket unter Ubuntu 24.04 nicht mehr gibt, oder dass ihr euch irgendwo
vertippt habt.

## Und so wandert das Image in die Gallery

Mit Hilfe von Azure Pipelines geht es natürlich direkt in die Gallery. Wir nutzen hier die Möglichkeit von Matrizen aus, um schnell eine Menge Images
parallel bauen zu können. Das erlaubt mir in Projekten, eine Basis zu bauen, die z.B. für mehrere Windows oder Ubuntu Versionen gültig ist. So spart ihr
eine gute Menge Code. Mit PowerShell-Modulen wie Datum oder PSFramework könntet ihr zusätzlich noch ein Konfigurationsmanagement bauen, um das Projekt
noch generischer und größer aufzustellen. Aber mal ehrlich: Wie viele Images braucht man schon, wenn eigentlich nur noch PaaS und SaaS Angebote
genutzt werden sollen? 😉

Ich gehe davon aus, dass ihr bereits eine Service Connection eingerichtet habt. Wenn nicht, dann los! Irgendwie muss der Kram in die Cloud,
also richtet euch eine user-assigned managed identity oder eine app registration mit Federated Credentials ein. Der letzte Part ist entscheidend: Wir
wollen niemals wieder Credentials irgendwo speichern.

Mit der Service Connection ist der Build dann simpel. Unsere Parameter bedienen sich aus der Matrix und den globalen Variablen, so dass wir
am Ende eine hinreichend elegante Pipeline haben, mit der Images publiziert werden können.

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