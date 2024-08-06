param (
    # name of the project 
    [Parameter(Mandatory=$true)]
    [string]$projectName
)

# login to admin azure account
Connect-AzAccount -TenantId a7c811dd-e3ca-41b4-892b-0c0207e72a80

################################################################################################################
# Prompt for user input to get AD group owners and members
################################################################################################################

$UserInputOwner = Read-Host "Enter AD group OWNER email(s) separated by commas, 'D' for default ('examplemail@mail.com'), or 'N' for none"
$UserInputMember = Read-Host "Enter AD group MEMBER email(s) separated by commas, or 'N' for none"

# Default values
$defaultOwners = @('nikolajmolholm@nikolajmolholmgmail.onmicrosoft.com')

# Determine the action based on user input
switch ($UserInputOwner) {
    'D' {
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

# Determine the action based on user input
switch ($UserInputMember) {
    'N' {
        # No additional owners
        $MemberPrincipalName = @()
    }
    default {
        # Process additional input or validate
        if ($UserInputMember -split ',' -match '^[\w\.\-]+@[\w\.\-]+\.[a-zA-Z]{2,}$') {
            # Split the comma-separated values and trim spaces
            $MemberPrincipalName = $UserInputMember -split ',' | ForEach-Object { $_.Trim() }
        } else {
            Write-Host "Invalid input format. Exiting script."
            exit
        }
    }
}

################################################################################################################
# Create new app-regs, ad groups, service principals and print their names
################################################################################################################

# create new app-regs (dev+prod)
$DevApp = New-AzADApplication `
    -DisplayName "app-dataestate-landing-$projectName-dev" `
    -SignInAudience AzureADMyOrg

if ($DevApp) {
    Write-Output "Created AD app:              $($DevApp.DisplayName) ($($DevApp.Id))"
}

$ProdApp = New-AzADApplication `
    -DisplayName "app-dataestate-landing-$projectName-prod" `
    -SignInAudience AzureADMyOrg

if ($ProdApp) {
    Write-Output "Created AD app:              $($ProdApp.DisplayName) ($($ProdApp.Id))"
}

# create new ad groups (dev+prod)
$DevGroup = New-AzADGroup `
    -DisplayName "sec-azure-dataestate-landing-$projectName-dev" `
    -MailNickname "sec-azure-dataestate-landing-$projectName-dev" `
    -Description "Data Estate Landing - app reg dev group"

if ($DevGroup) {
    Write-Output "Created AD group:            $($DevGroup.DisplayName) ($($DevGroup.Id))"
}

$ProdGroup = New-AzADGroup `
    -DisplayName "sec-azure-dataestate-landing-$projectName-prod" `
    -MailNickname "sec-azure-dataestate-landing-$projectName-prod" `
    -Description "Data Estate Landing - app reg prod group"

if ($ProdGroup) {
    Write-Output "Created AD group:            $($ProdGroup.DisplayName) ($($ProdGroup.Id))"
}

# create service principals for app-regs
$DevSp = New-AzADServicePrincipal -ApplicationId $DevApp.AppId

if ($DevSp) {
    Write-Output "Created service principal:   $($DevSp.DisplayName) ($($DevSp.Id))"
}

$ProdSp = New-AzADServicePrincipal -ApplicationId $ProdApp.AppId

if ($ProdSp) {
    Write-Output "Created service principal:   $($ProdSp.DisplayName) ($($ProdSp.Id))"
}

################################################################################################################
# Add app-regs to ad groups and ad groups to 'sec-azure-dataestate-landing'
################################################################################################################

# add service principal as member to ad group
Add-AzADGroupMember -TargetGroupObjectId $DevGroup.Id -MemberObjectId $DevSp.Id
Add-AzADGroupMember -TargetGroupObjectId $ProdGroup.Id -MemberObjectId $ProdSp.Id

# add new ad groups as members to 'sec-azure-dataestate-landing'
$LandingGroup = Get-AzADGroup -DisplayName "sec-azure-dataestate-landing"

Add-AzADGroupMember -TargetGroupObjectId $LandingGroup.Id -MemberObjectId $DevGroup.Id
Add-AzADGroupMember -TargetGroupObjectId $LandingGroup.Id -MemberObjectId $ProdGroup.Id

################################################################################################################
# Add permissions and secrets to app-regs
################################################################################################################

# add permissions (azure storage + azure data lake)
$StorageApiId = "e406a681-f3d4-42a8-90b6-c2b029497af1"
$DataLakeApiId = "e9f49c6b-5ce5-44c8-925d-015017e9f7ad"
$GraphApiId = "00000003-0000-0000-c000-000000000000"

$StoragePermissionId = "03e0da56-190b-40ad-a80c-ea378c433f7f"
$DataLakePermissionId = "9f15d22d-3cdf-430f-ba48-f75401c0408e"
$GraphPermissionId = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"

Add-AzADAppPermission -ObjectId $DevApp.Id -ApiId $StorageApiId -PermissionId $StoragePermissionId
Add-AzADAppPermission -ObjectId $ProdApp.Id -ApiId $StorageApiId -PermissionId $StoragePermissionId
Add-AzADAppPermission -ObjectId $DevApp.Id -ApiId $DataLakeApiId -PermissionId $DataLakePermissionId
Add-AzADAppPermission -ObjectId $ProdApp.Id -ApiId $DataLakeApiId -PermissionId $DataLakePermissionId
Add-AzADAppPermission -ObjectId $DevApp.Id -ApiId $GraphApiId -PermissionId $GraphPermissionId
Add-AzADAppPermission -ObjectId $ProdApp.Id -ApiId $GraphApiId -PermissionId $GraphPermissionId

## optionally add secret to app-reg
# New-AzADAppCredential -ObjectId $DevAppObjectId
# New-AzADAppCredential -ObjectId $ProdAppObjectId

################################################################################################################
# Add members and owners to ad groups
################################################################################################################

# Add user(s) as member(s) to ad group, if UserPrincipalName parameter contains values
if ($MemberPrincipalName -and $MemberPrincipalName.Count -gt 0) {
    # Loop over each principal name in the array
    foreach ($Name in $MemberPrincipalName) {
        # get user details
        $User = Get-AzADUser -UserPrincipalName $Name

        # add user as a member to ad groups
        try {
            Add-AzADGroupMember -TargetGroupObjectId $DevGroup.Id -MemberObjectId $User.Id -ErrorAction Stop
            Add-AzADGroupMember -TargetGroupObjectId $ProdGroup.Id -MemberObjectId $User.Id -ErrorAction Stop
            Write-Output "$Name added as member to dev/prod ad groups"

        } catch {
            Write-Output "Failed to add user $Name as member. Error: $_"
        }
    }
} else {
    Write-Output "No members added to groups"
}

# Add user(s) as owner(s) to ad group, if OwnerPrincipalName parameter contains values
if ($OwnerPrincipalName -and $OwnerPrincipalName.Count -gt 0) {
    # Loop over each principal name in the array
    foreach ($Name in $OwnerPrincipalName) {
        # get user details
        $Owner = Get-AzADUser -UserPrincipalName $Name

        # add user as an owner to ad groups
        try {
            New-AzADGroupOwner -GroupId $DevGroup.Id -OwnerId $Owner.Id -ErrorAction Stop
            New-AzADGroupOwner -GroupId $ProdGroup.Id -OwnerId $Owner.Id -ErrorAction Stop
            Write-Output "$Name added as owner to dev/prod ad groups"

        } catch {
            Write-Output "Failed to add user $Name as owner. Error: $_"
        }
    }
} else {
    Write-Output "No owners added to ad groups"
}
