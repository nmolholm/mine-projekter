param (

	# name of the project 
	[Parameter(Mandatory=$true)]
	[string]$projectName,
	
	# emails of user(s) to be added as member(s) to ad groups
	[Parameter(Mandatory=$false)]
	[string[]]$UserPrincipalName

)

# Prompt for user input
$UserInputOwner = Read-Host "Please write the email(s) of additional user(s) to be added as owner of AD groups separated by comma, type 'Y' to use default values ('mabm@seges.dk', 'ojeadm@seges.dk', 'nmhadm@seges.dk'), or type 'N' to not add any additional users"

# Default values
$defaultOwners = @('mabm@seges.dk', 'ojeadm@seges.dk', 'nmhadm@seges.dk')

# Determine the action based on user input
switch ($UserInputOwner) {
    'Y' {
        # Use default values
        $OwnerPrincipalName = $defaultOwners
    }
    'N' {
        # No additional owners
        $OwnerPrincipalName = @()
    }
    default {
        # Process additional input or validate
        if ($UserInputOwner -split ',' -match '^[\w\.\-]+@[\w\.\-]+\.[a-zA-Z]{2,}$') {
            # Split the comma-separated values and trim spaces
            $OwnerPrincipalName = $UserInputOwner -split ',' | ForEach-Object { $_.Trim() }
        } else {
            Write-Host "Invalid input format. Exiting script."
            exit
        }
    }
}

# Output the final list of owners
Write-Host "Final list of owners:"
$OwnerPrincipalName | ForEach-Object { Write-Host $_ }ut

# create displayname variables for app-regs and ad groups from input argument
New-Variable -Name "DisplayNameAppDev" -Value "app-dataestate-landing-$projectName-dev" -Option ReadOnly
New-Variable -Name "DisplayNameAppProd" -Value "app-dataestate-landing-$projectName-prod" -Option ReadOnly
New-Variable -Name "DisplayNameGroupDev" -Value "sec-azure-dataestate-landing-$projectName-dev" -Option ReadOnly
New-Variable -Name "DisplayNameGroupProd" -Value "sec-azure-dataestate-landing-$projectName-prod" -Option ReadOnly

# create new app-reg (dev+prod)
az ad app create --display-name $DisplayNameAppDev --sign-in-audience AzureADMyOrg 
az ad app create --display-name $DisplayNameAppProd --sign-in-audience AzureADMyOrg

### get object IDs of app-regs
# show group details and capture the output
$DevAppDetailsJson = az ad app list --display-name $DisplayNameGroupDev | Out-String
$ProdAppDetailsJson = az ad app list --display-name $DisplayNameGroupProd | Out-String

# Convert the JSON output to a PowerShell object
$DevAppDetails = $DevAppDetailsJson | ConvertFrom-Json
$ProdAppDetails = $ProdAppDetailsJson | ConvertFrom-Json

# Extract the object ID
$DevAppObjectId = $DevAppDetails[0].objectId
$ProdAppObjectId = $ProdAppDetails[0].objectId

### get object IDs of ad groups
# show group details and capture the output
$DevGroupDetailsJson = az ad group show --group $DisplayNameGroupDev | Out-String
$ProdGroupDetailsJson = az ad group show --group $DisplayNameGroupProd | Out-String

# Convert the JSON output to a PowerShell object
$DevGroupDetails = $DevGroupDetailsJson | ConvertFrom-Json
$ProdGroupDetails = $ProdGroupDetailsJson | ConvertFrom-Json

# Extract the object ID
$DevGroupObjectId = $DevGroupDetails.objectId
$ProdGroupObjectId = $ProdGroupDetails.objectId

# Nye projekt-grupper skal tilføjes til gruppen "sec-azure-dataestate-landing" for at få adgang til containeren.
az ad group member add --group sec-azure-dataestate-landing --member-id $DevGroupObjectId
az ad group member add --group sec-azure-dataestate-landing --member-id $ProdGroupObjectId

# add permissions (azure storage + azure data lake)
az ad app permission add --api $DevAppObjectId --api-permissions e406a681-f3d4-42a8-90b6-c2b029497af1 --id 03e0da56-190b-40ad-a80c-ea378c433f7f #app=azure storage, permission=user_impersonation
az ad app permission add --api $ProdAppObjectId --api-permissions e406a681-f3d4-42a8-90b6-c2b029497af1 --id 03e0da56-190b-40ad-a80c-ea378c433f7f #app=azure storage, permission=user_impersonation
az ad app permission add --api $DevAppObjectId --api-permissions e9f49c6b-5ce5-44c8-925d-015017e9f7ad --id 03e0da56-190b-40ad-a80c-ea378c433f7f #app=azure data lake, permission=user_impersonation
az ad app permission add --api $ProdAppObjectId --api-permissions e9f49c6b-5ce5-44c8-925d-015017e9f7ad --id 03e0da56-190b-40ad-a80c-ea378c433f7f #app=azure data lake, permission=user_impersonation
az ad app permission add --api $DevAppObjectId --api-permissions 00000003-0000-0000-c000-000000000000 --id e1fe6dd8-ba31-4d61-89e7-88639da4683d #app=microsoft graph, permission=User.Read
az ad app permission add --api $ProdAppObjectId --api-permissions 00000003-0000-0000-c000-000000000000 --id e1fe6dd8-ba31-4d61-89e7-88639da4683d #app=microsoft graph, permission=User.Read

# evt. tilføj secret til app-reg
az ad app credential reset --id $DevAppObjectId
az ad app credential reset --id $ProdAppObjectId

# opret projektspecifik ad group (dev+prod)
az ad group create --display-name $DisplayNameGroupDev --mail-nickname $DisplayNameGroupDev --description "Data Estate Landing - app reg dev group"
az ad group create --display-name $DisplayNameGroupProd --mail-nickname $DisplayNameGroupProd --description "Data Estate Landing - app reg prod group"

# tilføj app-reg som member til ad group
az ad group member add --group $DisplayNameGroupDev --member-id $DevAppObjectId
az ad group member add --group $DisplayNameGroupProd --member-id $ProdAppObjectId

### Tilføj user(s) som member(s) til ad group, hvis UserPrincipalName parameteren indeholder værdier
if ($UserPrincipalName -and $UserPrincipalName.Count -gt 0) {
    # Loop over each principal name in the array
    foreach ($Name in $UserPrincipalName) {
		
		# show user details and capture the output
		$UserDetailsJson = az ad user show --id $Name | Out-String
		
		# Convert the JSON output to a PowerShell object
		$UserDetails = $UserDetailsJson | ConvertFrom-Json

		# Extract the object ID
		$UserObjectId = $UserDetails.objectId
	
		# use object id when adding user as a member to ad groups
        az ad group member add --group $DisplayNameGroupDev --member-id $UserObjectId
		az ad group member add --group $DisplayNameGroupProd --member-id $UserObjectId
    }
	
} else {

    Write-Output "No users were added as a member to ad groups"
	
}

### Tilføj user(s) som owner(s) til ad group, hvis OwnerPrincipalName parameteren indeholder værdier
if ($OwnerPrincipalName -and $OwnerPrincipalName.Count -gt 0) {
    # Loop over each principal name in the array
    foreach ($Name in $OwnerPrincipalName) {
		
		# show user details and capture the output
		$OwnerDetailsJson = az ad user show --id $Name | Out-String
		
		# Convert the JSON output to a PowerShell object
		$OwnerDetails = $OwnerDetailsJson | ConvertFrom-Json

		# Extract the object ID
		$OwnerObjectId = $OwnerDetails.objectId
	
		# use object id when adding user as a member to ad groups
        az ad group owner add --group $DisplayNameGroupDev --owner-object-id $OwnerObjectId
		az ad group owner add --group $DisplayNameGroupProd --owner-object-id $OwnerObjectId
    }
	
} else {

    Write-Output "No users were added as an additional owner to ad groups"
	
}
