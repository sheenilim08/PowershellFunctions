Function New-ClientVPNConnection {
    <#
    .Description
    This function is designed to verify existence of a given VPN name, verify configuration, and create
    or replace the VPN connection if the settings do not align with what was defined when this function
    was called. For example, if split tunneling was set to enabled, but there is an existing VPN
    connection on the machine with the same name you defined and split tunneling disabled, the existing
    VPN connection would be removed, and a new one created with the apropriate settings.

    Note the !SUCCESS: and !FAILED: words in the function output are for easy identifiaction from
    Automate to determine success or failure of the VPN creation.

    .Parameter ServerAddress
    Enter the server address you want the VPN connection to connect to.

    .Parameter TunnelType
    Choose the type of tunnel.

    .Parameter AllUserConnection
    Enabling this allows all users that can auth to the VPN to connect to VPN before Windows logon. 
    This is helpful for when credentials for the user are not yet cached and the user is remote. Remember, 
    the user must have credentials to authenticate the VPN-- the Preshared key alone will not authenticate
    so this "all user" settings does not introduce additional security risk.

    .Parameter PresharedKey
    Enter the Preshared Key.

    .Parameter AuthenticationMethod
    Choose the Authentication Method.

    .Parameter SplitTunnel
    Setting this to 1 enables split tunneling which means only defined subnets defined on the VPN destination
    route through VPN, while the remaining requests route straight from your original IP. This can be a
    powerful way to increase performance on bandwidth constrained infrastructures, but can also have
    unintentional consequences if an asset on the target end of the VPN live on a subnet not defined on the
    target VPN side and the traffic from the endpoint goes straight to the internet instead of routing through 
    the VPN. The result would be the appearance of a down system or broken application, when in fact the
    users traffic is just simply not routing over the VPN tunnel. Note you can add additional routes from the
    endpoint (https://community.spiceworks.com/how_to/75078-configuring-split-tunnel-client-vpn-on-windows) but
    the right answer is to route from the VPN destination side since the endpoint side is reset after each
    reboot.

    .Parameter ClientName
    Set this value to name your VPN connection. The name of the VPN will be [ClientName VPN] without the brackets. 
    If this is left empty, the default is [Automated VPN].

    .Example
    C:\New-ClientVPNConnection -ServerAddress 'something.meraki.com.yourconnection.etc' -TunnelType L2tp -AllUserConnection $true -PresharedKey 'uawjiuciewcnaiwiuua3n2in' -AuthenticationMethod Pap -SplitTunnel 1 -ClientName 'Example Company'
    #>


    Param(
        [Parameter(
            Mandatory = $true,
            HelpMessage='Enter the server address you want the VPN connection to connect to.'
        )]
        [string]$ServerAddress
        ,[Parameter(
            Mandatory = $true,
            HelpMessage='Choose the type of tunnel.'
        )]
        [ValidateSet('Automatic','Ikev2','L2tp','Pptp','Sstp')]
        [string]$TunnelType
        ,[Parameter(
            Mandatory = $false,
            HelpMessage='Default this is [$true], but can be set to [$false]. Enabling this allows all users that can auth to the VPN to connect to VPN before Windows logon. This is helpful for when credentials for the user are not yet cached and the user is remote.'
        )]
        [boolean]$AllUserConnection = $true
        ,[Parameter(
            Mandatory = $true,
            HelpMessage='Enter the Preshared Key.'
        )]
        [string]$PresharedKey
        ,[Parameter(
            Mandatory = $true,
            HelpMessage='Choose the Authentication Method.'
        )]
        [ValidateSet('Chap','Eap','MachineCertificate','MSChapv2','Pap')]
        [string]$AuthenticationMethod
        ,[Parameter(
            Mandatory = $false,
            HelpMessage='Set this value to [0] or [1] without brackets. The value of [1] enables split tunneling which means only defined subnets on the VPN tunnel route through VPN, while the remaining requests route straight from your original IP.'
        )]
        [ValidateSet(0,1)]
        [int32]$SplitTunnel = 0
        ,[Parameter(
            Mandatory = $false,
            HelpMessage='Set this value to name your VPN connection. The name of the VPN will be [ClientName VPN] without the brackets. If this is left empty, the default is [Automated VPN].'
        )]
        [string]$ClientName = 'Automated'
    )


    Function Invoke-Output {
        param ([string[]]$output)
        $output = $output -join "`n"
        Write-Output $output
    }


    # Define vars
    $output = @()
    # Removing all non word characters from client name
    $ClientName = $ClientName -replace "[^\w\s]", ''
    $vpnName = "$clientName VPN"


    # Handling NULL or $false from Automate can be difficult so we're using 1/0 and converting to boolean here.
    # Since $SplitTunnel is a mandatory param we don't have to worry about a default value here.
    Switch ($SplitTunnel) {
        0 { [boolean]$SplitTunnel = $false }
        1 { [boolean]$SplitTunnel = $true }
    }


    # Create hash to splat for the VPN creation
    $vpnConfigHash = @{
        Name = $vpnName
        ServerAddress = $ServerAddress
        TunnelType = $TunnelType
        AllUserConnection = $AllUserConnection
        L2tpPsk = $PresharedKey
        AuthenticationMethod = $AuthenticationMethod
        SplitTunnel = $SplitTunnel
        Force = $true
    }


    # See if the VPN connection already exists
    $vpnPresent = Get-VpnConnection -AllUserConnection -Name $vpnName -EA 0
    If (!$vpnPresent) {
        Try {
            # Create the VPN connection
            $output += "$vpnName does not exist, creating connection..."
            # Splat the hash we made above that has the correct parameters based on used input
            Add-VpnConnection @vpnConfigHash
            # Check for the VPN connection again to see if it now exists
            $vpnPresent = Get-VpnConnection -AllUserConnection -Name $vpnName -EA 0
            If ($vpnPresent) {
                $output += "!SUCCESS: Created $vpnName successfully"
                Invoke-Output $output
                Break
            } Else {
                $output += "!FAILED: Failed to created $vpnName"
                Invoke-Output $output
                Break
            }
        } Catch {
            # If there was an error thrown during VPN connection creation it will come here and put out this error
            $output += "!FAILED: There was a problem when attempting to create $vpnName. Error output: $error"
            Invoke-Output $output
            Break
        }
    } Else {
        Try {
            $output += "Verified $vpnName already exists, checking configuration..."
            # Check the VPN connection properties. If the settings are different than the ones we are sending,
            # delete the VPN connection, then recreate it with the accurate settings.
            If (($vpnPresent).ServerAddress -ne $ServerAddress -or ($vpnPresent).AuthenticationMethod -ne $AuthenticationMethod -or ($vpnPresent).TunnelType -ne $TunnelType -or ($vpnPresent).SplitTunneling -ne $SplitTunnel) {
                $output += "$vpnName has settings that do not match the configuration sent from Automate, recreating VPN connection..."
                Remove-VpnConnection -AllUserConnection -Name $vpnName -Force
                Add-VpnConnection @vpnConfigHash
                $output += "!SUCCESS: Created $vpnName successfully"
            } Else {
                $output += "!SUCCESS: Verified all $vpnName settings match configurations from Automate!"
            }
            Invoke-Output $output
            Break
        } Catch {
            # If we're here then this means something went wrong when removing/creating the VPN connection above
            $output += "!FAILED: Failed to created $vpnName. Error ourput: $error"
            Invoke-Output $output
            Break
        }
    }
}