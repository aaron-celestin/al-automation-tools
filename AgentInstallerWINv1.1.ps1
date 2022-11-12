# Alert Logic Agent Installer for Windows v1.0.1
Set-ExecutionPolicy Bypass

#####################################################################################################################
# PASTE YOUR REGISTRATION KEY HERE (between the quotes) OR THE AGENTS INSTALLED WILL NOT CLAIM                      #
#                                                                                                                   #                                                                                       
                $REG_KEY = "c7249e7055390f19f39e79818821a12faeb58ab404d070e83e"#"<YOUR REGISTRATION KEY HERE>"                                                           #
#                                                                                                                   #
#####################################################################################################################

 # Set default agent URL

#Static variables. DO NOT ALTER THESE UNLESS DIRECTED TO DO SO BY ALERT LOGIC STAFF
$REG_KEY_MIN = 50
$REG_KEY_MAX = 54
$script:logfilepath = "$env:USERPROFILE\Downloads\AlertLogic\agent_install.log"
$global:SAVED_VERB_PREF = $global:VerbosePreference

#Custom Variables
# Path to agent installer, for example if the msi has been downloaded to the local machine already. This will bypass the downloading of the msi.
#$script:custom_msi = " <custom path> \al-agent-LATEST.msi

# if the agent will not be installed to the default installation path, set it here.
#$script:cust_path = "<custom path>"

# Appliance URL. By default, the agents forwards logs direct;y to Alert Logic's datacnter at "vaporator.alertlogic.com" over port 443. In some cases where the agent 
# is in a private subnet with no direct outside internet access, logs can be forwarded through an IDS appliance. Set the IDS appliance URL or IP here that will act as
# a gateway here. 
#$app_hostname = <IP or hostname of IDS appliance>
#[int32]$app_port = <port of IDS appliance>

# If the agent will be behind a proxy, set this to true and the agent will attempt to use the proxy settings from WinHTTP's built-in settings.
#$proxy = "true"

# For debugging purposes, set this to true to see the output of the agent installer. Output will be written to the file "agent_install.log" in the same directory as the installer.
#$verb_mode = "true"

# Your system may reboot to complete the installation. The system may reboot if you have previously installed the agent, if you are running a Windows Server 2019 variant, or other reasons.
# If you want to avoid the system reboot, and consequently pause the installation process until you manually reboot, uncomment the following line to suppress the reboot. 
#$supress_reboot = "true"

#ChangeLOG
#v0.8.4     original release
#v0.8.5     added ability to set custom appliance URL, added ability to suppress reboot
#v0.9       added proxy support, added ability to set custom msi path, added ability to set custom install path
#v0.9.1     added ability to set custom log file path
#v1.0.1     refactored applianceEgress and downloadAgent functions, added more verbose messages, added verbose mode check function and added UTF-8 encoding for log file output 

function downloadAgent 
{    
    write-verbose "Downloading agent from $agent_url"
    $agent_url = "https://scc.alertlogic.net/software/al_agent-LATEST.msi"
    try 
    {
        $adl_hash = @{
            Uri = $agent_url
            OutFile = $script:p_msi
        }
        Invoke-WebRequest @adl_hash # Download MSI and put it in file destination
        Write-Verbose "Agent MSI downloaded successfully"
    }
    catch [System.Net.WebException],[System.IO.IOException] 
    {
        Write-Host "Error: Unable to download MSI file. Please check your internet connection and try again." 
        exit
    }
    catch [Microsoft.PowerShell.Commands.HttpResponseException]
    {
        Write-Host "Error: (404) Unable to download MSI file. Please check the agent download URL and try again." 
        exit
    }
}


function startAgentService ([string]$agent_svc_name)
{
    $agent_svc_name = "al_agent"
    Write-Host "Starting agent service..."
    try
    {
        start-service -name $agent_svc_name
        set-service -name $agent_svc_name -startupType automatic
        $al_service = get-service -name $agent_svc_name
        if ($al_service.status -eq "running") {
            Write-Verbose "Agent Service Started Successfully" 
        }
        else {
            Write-Verbose "Agent Service Failed to Start"
        }
    }
    catch {
        Write-Host "Service Error: Unable to start AlertLogic service. Check user permissions and try atgain."
    }
}


function checkOptionalMakePaths  ([string]$msi_path, [string]$inst_path)
{    # Check if msi_path is valid path set by user, if not, set to default
    Write-verbose "Checking if non-default install and file paths are set."
    if (Test-Path $msi_path -ErrorAction Ignore) 
    {
        $script:p_msi = $msi_path
        Write-Verbose "MSI path set by user, using path: $msi_path" 
    }   
    else
    {
        $script:p_msi = "$env:USERPROFILE\Downloads\AlertLogic\al-agent-LATEST.msi"
        New-Item -Path $script:p_msi -ItemType File -Force #create file
        Write-Verbose "MSI path not set by user or folder does not exist, using default path: $script:p_msi" 
    }
            
    # Check if inst_path is valid path set by user, if not, set to default
    if (Test-Path $inst_path -ErrorAction Ignore) 
    {
        $script:p_inst = $inst_path
        $script:cust_inst = "true"
        Write-Verbose "Install path set by user, using path: $inst_path" 
    }   
    else
    {
        Write-Verbose "Install path not set by user or does not exist, using default %systemroot% path." 
    }
}
   

function checkLogEgressAppliance ([string]$a_hostname,[int32]$a_port)
{
    $script:opt_app = ""
    $script:opt_port = 0
    write-verbose "Checking Log Egress Appliance is set."
    try
    {
        $tnc_hash = @{
            ComputerName = $a_hostname
            Port = $a_port
            ErrorAction = SilentlyContinue
        }
        $appObj = Test-NetConnection @tnc_hash
        write-verbose "Custom Appliance Object Function Test: $appObj"
        if ($appObj.TcpTestSucceeded)
        {
            $script:opt_app = $a_hostname
            $script:opt_port = $a_port
            $script:cust_app = "true" 
            Write-verbose "IDS Appliance Egress target $a_hostname is up."
        }
        else
        {
            Write-verbose "IDS Appliance Egress target $a_hostname is down or not set."
            Write-verbose "Agent logs will be sent to vaporator.alertlogic.com. This is the default behavior"
        }
    }
    catch {}
}


function toggleVerboseMode
{ 
    $global:VerbosePreference = "Continue"
    Write-Verbose "Debug (Verbose) mode set by user."
        
    if (Test-Path $script:logFilePath) 
    {
        Write-Verbose "Log file path is $script:logFilePath."
    }
    else
    {
        New-Item -Path $logFilePath -ItemType File -Force #create file if it doesnt exist
        Write-Verbose "Log file path $script:logFilePath created."
    } 
}


function checkVerbose
{
    Write-Host "Checking for Verbose Mode. Mode currently set to $global:VerbosePreference"
    Write-Verbose "WARNING! IF YOU ARE SEEING THIS MESSAGE, POWERSHELL IS STILL SET TO VERBOSE MODE. IT IS POSSIBLE VERBOSE MODE HAS FAILED TO REVERT."
    Write-Verbose "If your Powershell installation is set to be verbose by default, please ignore this message. If not, please check this script and make" 
    Write-Verbose "sure the last line is:  `$global:VerbosePreference = `$SAVED_VERB_PREF"
    Write-Verbose "IF VERB MODE IS STILL ON, TRY MANUALLY SETTING THE VERBOSE MODE PREFERENCE VARIABLE TO 'SilentlyContinue' FROM THE COMMAND LINE:"
    Write-Verbose "`$VerbosePreference = 'SilentlyContinue'"
}


function installAgent ([string]$key)
{
    if (($key -eq "<YOUR REGISTRATION KEY HERE>") -OR ($key-eq "")) 
        {
            Write-Host "Please enter your registration key in the script before running it." 
            exit
        }
    elseif (($REG_KEY.Length -lt $REG_KEY_MIN) -OR ($key.Length -gt $REG_KEY_MAX))
        {
            Write-Host "Your registration key is not valid. Please check it and try again." 
            exit
        } 
    else
    {
        $script:install_command = "msiexec /i $script:p_msi -prov_key=$key"
        Write-Verbose "Default install command: $script:install_command"
        if ($cust_inst -eq "true")
        {
            $script:install_command += " -install_path=$script:p_inst"
            Write-Verbose "Install path set by user, install command: $script:install_command"
        }
        if ($verb_mode -eq "true") 
        {
            $script:install_command += " /l*vx $script:logfilepath"
            Write-Verbose "Debug (verbose) install command: $script:install_command"
        }
        else {$script:install_command += $default_opts}
    

        if ($script:cust_app -eq "true") 
        {
            $script:install_command += " -sensor_host=$script:opt_app -sensor_port=$script:opt_port"
            Write-Verbose "Appliance egress added: $script:install_command"
        }
        if ($proxy -eq "true")
        {
            $script:install_command += " -use_proxy=1"
            Write-Verbose "Proxy enabled: $script:install_command"
        }
        if ($supress_reboot -eq "true")
        {
            $script:install_command += " -REBOOT=ReallySuppress"
            Write-Verbose "Reboot supressed: $script:install_command"
        }
        Write-Verbose "Final install command: $script:install_command"
        try
        {
            Invoke-Expression -command $script:install_command 
            Write-verbose "Install command executed: $script:install_command"
            Write-Verbose "Agent MSI installed successfully"
        }
        catch [System.Management.Automation.MethodInvocationException]
        {
            Write-Host "Error: Unable to install MSI file. Please check the installation path and try again."
            exit
        }
    }
    startAgentService
}

##############################################################################################################################
### START SCRIPT PROCESSING ###

if ($verb_mode -eq "true")
{
    toggleVerboseMode 
    installAgent($REG_KEY) -verbose *>&1 | Tee-Object -append -encoding utf8 -FilePath $script:logFilePath
    
}
else 
{
    Write-Host "Debug mode not set by user, using default quiet mode." 
    installAgent($REG_KEY)
    
}


        
if ($global:VerbosePreference -ne "SilentlyContinue")
{
    $global:VerbosePreference = $SAVED_VERB_PREF
    Write-Host "Verbose mode reverted back to original preference."
}
checkVerbose
# END OF SCRIPT