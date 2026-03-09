function Get-LocalAdmins {
    <#
    .SYNOPSIS
    Compensate for a known, widespread - but inexplicably unfixed - issue in Get-LocalGroupMember.
    Issue here: #2996

    .DESCRIPTION
    The script uses ADSI to fetch all members of the local Administrators group.
    MSFT are aware of this issue, but have closed it without a fix, citing no reason.
    It will output the SID of AzureAD objects such as roles, groups and users,
    and any others which cnanot be resolved.
    the AAD principals' SIDS need to be mapped to identities using MS Graph.

    Designed to run from the Intune MDM and thus accepts no parameters.

    .EXAMPLE
    $results = Get-localAdmins
    $results

    The above will store the output of the function in the $results variable, and
    output the results to console

    .OUTPUTS
    System.Management.Automation.PSCustomObject
    Name        MemberType   Definition
    ----        ----------   ----------
    Equals      Method       bool Equals(System.Object obj)
    GetHashCode Method       int GetHashCode()
    GetType     Method       type GetType()
    ToString    Method       string ToString()
    Computer    NoteProperty string Computer=Workstation1
    Domain      NoteProperty System.String Domain=Contoso
    User        NoteProperty System.String User=Administrator
    #>

    [CmdletBinding()]

    $GroupSID='S-1-5-32-544'
    [string]$Groupname = (Get-LocalGroup -SID $GroupSID)[0].Name
	
    $group = [ADSI]"WinNT://$env:COMPUTERNAME/$Groupname"

    $admins = $group.Invoke('Members') | ForEach-Object {
        $path = ([adsi]$_).path
        [pscustomobject]@{
            Computer = $env:COMPUTERNAME
            Domain   = $(Split-Path (Split-Path $path) -Leaf)
            User     = $(Split-Path $path -Leaf)
            ADSIPath = $path
        }
    }

    return $admins
}

function Remove-LocalAdmin {
    <#
    .SYNOPSIS
    Remove users from local Administrators group by ADSIPath

    .DESCRIPTION
    Looks up local Administrators group via well-known SID. This works on languages other than English. Remove users from local Administrators group by ADSIPath


    .EXAMPLE

    .OUTPUTS
    None
    #>

    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true,ValueFromPipelineByPropertyName)]
        $ADSIPath
    )

    begin{
        $ErrorActionPreference = 'Stop'
    
        $GroupSID='S-1-5-32-544'
        [string]$Groupname = (Get-LocalGroup -SID $GroupSID)[0].Name
		
        $group = [ADSI]"WinNT://$env:COMPUTERNAME/$Groupname"
    }

    process{
        Write-Verbose "Attempting to remove user $ADSIPath ($($_.Domain)\$($_.User))" -Verbose

        try{
            $group.Remove($ADSIPath)
            Write-Verbose "Successfully removed user $ADSIPath ($($_.Domain)\$($_.User))" -Verbose
        }
        catch{
            Write-Warning "Error removing $($ADSIPath): $($_.Exception.Message)"
            Write-Error $_.Exception.Message
        }
    }
}

Write-Verbose "Querying members of the 'Administrators' group" -Verbose

$groupmemberlist = Get-LocalAdmins

# filter out specific users
$remove = $groupmemberlist |
    Where-Object User -NotMatch 'Doug|^administrator$|wdagutilityaccount|defaultaccount|guest|Domain Admins' 

if($remove){
    Write-Verbose "Identified $($remove.count) user accounts to remove from 'Administrators'" -Verbose

    $remove | Remove-LocalAdmin
}
