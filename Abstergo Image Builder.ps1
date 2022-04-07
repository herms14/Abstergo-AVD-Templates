# check you are registered for the providers, ensure RegistrationState is set to 'Registered'.
Get-AzResourceProvider -ProviderNamespace Microsoft.VirtualMachineImages
Get-AzResourceProvider -ProviderNamespace Microsoft.Storage 
Get-AzResourceProvider -ProviderNamespace Microsoft.Compute
Get-AzResourceProvider -ProviderNamespace Microsoft.KeyVault

# If they do not show as registered, run the commented out code below.

## Register-AzResourceProvider -ProviderNamespace Microsoft.VirtualMachineImages
## Register-AzResourceProvider -ProviderNamespace Microsoft.Storage
## Register-AzResourceProvider -ProviderNamespace Microsoft.Compute
## Register-AzResourceProvider -ProviderNamespace Microsoft.KeyVault


# Step 1: Import module
Import-Module Az.Accounts

# Step 2: get existing context
$currentAzContext = Get-AzContext

# destination image resource group
$imageResourceGroup="abs-avd-image-rg"

# location (see possible locations in main docs)
$location="southeastasia"

# your subscription, this will get your current subscription
$subscriptionID=$currentAzContext.Subscription.Id

# image template name
$imageTemplateNameWin10= "ABS-Corp-Win10-ImageTemplate"
$imageTemplateNameWin11 = "ABS-Corp-Win11-ImageTemplate"

# distribution properties object name (runOutput), i.e. this gives you the properties of the managed image on completion
$runOutputName="sigOutput"

# create resource group
New-AzResourceGroup -Name $imageResourceGroup -Location $location




# setup role def names, these need to be unique
$timeInt=$(get-date -UFormat "%s")
$imageRoleDefName="Azure Image Builder Image Def"+$timeInt
$identityName="abs-imagebuilder-msi"

## Add AZ PS modules to support AzUserAssignedIdentity and Az AIB
'Az.ImageBuilder', 'Az.ManagedServiceIdentity' | ForEach-Object {Install-Module -Name $_}

# create identity
New-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName

$identityNameResourceId=$(Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName).Id
$identityNamePrincipalId=$(Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName).PrincipalId


$aibRoleImageCreationUrl="https://raw.githubusercontent.com/azure/azvmimagebuilder/master/solutions/12_Creating_AIB_Security_Roles/aibRoleImageCreation.json"
$aibRoleImageCreationPath = "aibRoleImageCreation.json"

# download config
Invoke-WebRequest -Uri $aibRoleImageCreationUrl -OutFile $aibRoleImageCreationPath -UseBasicParsing

((Get-Content -path $aibRoleImageCreationPath -Raw) -replace '<subscriptionID>',$subscriptionID) | Set-Content -Path $aibRoleImageCreationPath
((Get-Content -path $aibRoleImageCreationPath -Raw) -replace '<rgName>', $imageResourceGroup) | Set-Content -Path $aibRoleImageCreationPath
((Get-Content -path $aibRoleImageCreationPath -Raw) -replace 'Azure Image Builder Service Image Creation Role', $imageRoleDefName) | Set-Content -Path $aibRoleImageCreationPath

# create role definition
New-AzRoleDefinition -InputFile  ./aibRoleImageCreation.json

# grant role definition to image builder service principal
New-AzRoleAssignment -ObjectId $identityNamePrincipalId -RoleDefinitionName $imageRoleDefName -Scope "/subscriptions/$subscriptionID/resourceGroups/$imageResourceGroup"



$sigGalleryName= "ABS_ComputeGallery"
$imageDefNameWin10 ="ABS_WIN10_AVD_Definition"
$imageDefNameWin11 ="ABS_WIN11_AVD_Definition"

# create gallery
New-AzGallery -GalleryName $sigGalleryName -ResourceGroupName $imageResourceGroup  -Location $location

# create gallery definition
New-AzGalleryImageDefinition -GalleryName $sigGalleryName -ResourceGroupName $imageResourceGroup -Location $location -Name $imageDefNameWin10 -OsState generalized -OsType Windows -Publisher 'AbstergoIndustries' -Offer 'Windows10' -Sku '10avd'
New-AzGalleryImageDefinition -GalleryName $sigGalleryName -ResourceGroupName $imageResourceGroup -Location $location -Name $imageDefNameWin11 -OsState generalized -OsType Windows -HyperVGeneration V2 -Publisher 'AbstergoIndustries' -Offer 'Windows11' -Sku '11avd'

#############################################################################################################################
# Deploy image for Win 10 and Win 11 

#Template for Win 10

#$templateUrl="https://raw.githubusercontent.com/azure/azvmimagebuilder/master/solutions/14_Building_Images_WVD/armTemplateWVD.json"
#$templateFilePath = "armTemplateWVD.json"

#Template for Win 11

$templateUrl="https://raw.githubusercontent.com/herms14/Abstergo-AVD-Templates/master/ABS-WIN11-ImageDefinition.json"
$templateFilePath = "ABS-WIN11-ImageDefinition.json"

Invoke-WebRequest -Uri $templateUrl -OutFile $templateFilePath -UseBasicParsing

((Get-Content -path $templateFilePath -Raw) -replace '<subscriptionID>',$subscriptionID) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<rgName>',$imageResourceGroup) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<region>',$location) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<runOutputName>',$runOutputName) | Set-Content -Path $templateFilePath
#Change Image Definition parameter to appropriate variable
((Get-Content -path $templateFilePath -Raw) -replace '<imageDefName>',$imageDefNameWin11) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<sharedImageGalName>',$sigGalleryName) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<region1>',$location) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<imgBuilderId>',$identityNameResourceId) | Set-Content -Path $templateFilePath

#Change ImageTemplateName parameter based on Win version

New-AzResourceGroupDeployment -ResourceGroupName $imageResourceGroup -TemplateFile $templateFilePath -TemplateParameterObject @{"api-Version" = "2020-02-14"} -imageTemplateName $imageTemplateNameWin11 -svclocation $location

# Optional - if you have any errors running the above, run:
$getStatus=$(Get-AzImageBuilderTemplate -ResourceGroupName $imageResourceGroup -Name $imageTemplateNameWin11)
$getStatus.ProvisioningErrorCode 
$getStatus.ProvisioningErrorMessage