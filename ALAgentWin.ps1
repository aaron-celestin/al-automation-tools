# Alert Logic Agent Installer for Windows v1.0.4
Set-ExecutionPolicy Bypass -Scope Process -Force;
#####################################################################################################################
# PASTE YOUR REGISTRATION KEY HERE (between the quotes) OR THE AGENTS INSTALLED WILL NOT CLAIM                      #
#                                                                                                                   #                                                                                       
                $REG_KEY = "<YOUR REGISTRATION KEY HERE>"                                                           #
#                                                                                                                   #
#####################################################################################################################
#-----------------STATIC VARIABLES-------------------
#Static variables. DO NOT ALTER THESE UNLESS DIRECTED TO DO SO BY ALERT LOGIC STAFF
$REG_KEY_MIN = 50
$REG_KEY_MAX = 54
#-----------------OPTIONS--------------------
# Path to agent installer, for example if the msi has been downloaded to the local machine already. This will bypass the downloading of the msi.
#$script:msi_path =  "< MSI file path >"
#--------------------------------------------
# if the agent will not be installed to the default installation path, set it here.
#$script:inst_path = "< install file path >"
#--------------------------------------------
# Appliance URL. By default, the agents forwards logs direct;y to Alert Logic's datacnter at "vaporator.alertlogic.com" over port 443. In some cases where the agent 
# is in a private subnet with no direct outside internet access, logs can be forwarded through an IDS appliance. Set the IDS appliance URL or IP here that will act as
# a gateway here. 
#$script:app_hostname = "< IP or hostname of IDS appliance >"
#$script:app_port = "< port of IDS appliance >"
#--------------------------------------------
# If the agent will be behind a proxy, set this to true and the agent will attempt to use the proxy settings from WinHTTP's built-in settings.
#$proxy = "true"
#--------------------------------------------
# For debugging purposes, set this to true to see the output of the agent installer. Output will be written to the file "agent_install.log" in the same directory as the installer.
#$verb_mode = "true"
#--------------------------------------------
# Your system may reboot to complete the installation. The system may reboot if you have previously installed the agent, if you are running a Windows Server 2019 variant, or other reasons.
# If you want to avoid the system reboot, and consequently pause the installation process until you manually reboot, uncomment the following line to suppress the reboot. 
#$supress_reboot = "true"
#----------------------SCRIPT BODY----------------------
function downloadAgent 
{    
    $agent_url = "https://scc.alertlogic.net/software/al_agent-LATEST.msi"
    write-verbose "Downloading agent from $agent_url"
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
function startAgentService 
{
    $agent_svc_name = "al_agent"
    Write-verbose "Starting agent service..."
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
function checkOptionalMakePaths
{    # Check if msi_path is valid path set by user, if not, set to default
    Write-Verbose "Checking if non-default install and MSI file paths are set."
    if (Test-Path $msi_path -ErrorAction "Ignore") 
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
    if (Test-Path $inst_path -ErrorAction "Ignore") 
    {
        $script:p_inst = $inst_path
        $script:cust_inst = "true"
        Write-Verbose "Install path set by user, using path: $inst_path" 
    }   
    else
    {
        Write-Verbose "Install path not set by user or does not exist, using default ${env:ProgramFiles(x86)} path." 
    }
}
function checkLogEgressAppliance
{
    $script:opt_app = ""
    $script:opt_port = 0
    $script:app_hostname = $app_hostname -as [string]
    $script:app_port = $app_port -as [int]
    write-verbose "Checking if Log Egress through Appliance is set."
    try
    {
        write-verbose "Egress appliance args found: $script:app_hostname : $script:app_port"
        write-verbose "Initializing connection to appliance, please wait."
        $tnc_hash = @{
            ComputerName = $script:app_hostname
            Port = $script:app_port
            ErrorAction = "SilentlyContinue"
        }
        write-verbose "IDS Appliance connection and function testing in progress. Target: $script:app_hostname"
        $appObj = Test-NetConnection @tnc_hash
        if ($appObj.TcpTestSucceeded)
        {
            $script:opt_app = $script:app_hostname
            $script:opt_port = $script:app_port
            $script:cust_app = "true" 
            Write-Verbose "IDS Appliance connection target test successful. $app_hostname is up and reachable."
        }
        else
        {
            Write-verbose "IDS Appliance Egress target $app_hostname is down or not set."
            Write-verbose "Agent logs will be sent to vaporator.alertlogic.com. This is the default behavior"
        }
    }
    catch {}
}
function toggleVerboseMode
{ 
    $script:logfilepath = "$env:USERPROFILE\Downloads\AlertLogic\agent_install.log"
    $script:SAVED_GVB_PREF = $global:VerbosePreference  
    if ($script:VerbosePreference -ne "Continue") #if anything but continue, set it to continue (verb mode on)
    {
        $script:VerbosePreference = "Continue"
        Write-Verbose "Script level scope verbose mode was set to ON ($script:VerbosePreference)."
        if (Test-Path $logFilePath) 
        {
            Write-Verbose "Log file path is $logFilePath."
        }
        else
        {
            New-Item -Path $logFilePath -ItemType File -Force #create file if it doesnt exist
            Write-Verbose "Log file path $logFilePath created."
        } 
    }
    elseif ($script:VerbosePreference -eq "Continue") #or if set to continue, turn it off (toggle off)
    {
        $script:VerbosePreference = "SilentlyContinue"
        Write-Verbose "Script level scope verbose mode was set to OFF ($script:VerbosePreference)."
        Write-Verbose "Global level scope verbose mode is set to $global:VerbosePreference."
    }
}   
function checkVerbosePreference
{
    Write-Host "Checking Script and Global verbose mode preferences." 
    Write-Host "Script level pref was set to $script:VerbosePreference"
    Write-Host "Global level pref was set to $global:VerbosePreference"
    if ($global:VerbosePreference -ne $script:SAVED_GVB_PREF) 
    {
        Write-Host "WARNING! POWERSHELL'S VERBOSE MODE PREFS HAVE BEEN MODIFIED!"
        Write-Host "VERBOSE MODE PREFERENCES FAILED TO REVERT TO THE DEFAULT." 
        Write-Verbose "Check your verbose mode preferences by typing `$global:VerboseModePreference on the command line."
        Write-Verbose "Try manually setting your VB Mode preference from the PowerShell command prompt:"
        Write-Verbose "Example: `$VerbosePreference = 'SilentlyContinue'"
    }
    else 
    {
        Write-Host "Global verbose mode preferences were not modified."
    }
}
function installAgent ([string]$key)
{
    downloadAgent
    checkOptionalMakePaths
    checkLogEgressAppliance
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
        Write-Verbose "Default install command string $script:install_command"
        if ($cust_inst -eq "true")
        {
            $script:install_command += " -install_path=$script:p_inst"
            Write-Verbose "Install path, $script:p_inst set by user"
        }
        if ($verb_mode -eq "true") 
        {
            $script:install_command += " /l*vx $script:logfilepath"
            Write-Verbose "Verbose mode enabled, logfile is $script:logfilepath"
        }
        else 
        {
            $script:install_command += $default_opts
            Write-Verbose "Default options $default_opts set."
        }
        if ($script:cust_app -eq "true") 
        {
            $script:install_command += " -sensor_host=$script:opt_app -sensor_port=$script:opt_port"
            Write-Verbose "Appliance egress was set: $script:opt_app : $script:opt_port"
        }
        if ($proxy -eq "true")
        {
            $script:install_command += " -use_proxy=1"
            Write-Verbose "Proxy enabled."
        }
        if ($supress_reboot -eq "true")
        {
            $script:install_command += " -REBOOT=ReallySuppress"
            Write-Verbose "Reboot prompt supressed."
        }
        Write-Verbose "Final install command string: $script:install_command"
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
----------------------------START SCRIPT PROCESSING-------------------------------
if ($verb_mode -eq "true")
{
    toggleVerboseMode 
    installAgent($REG_KEY) -verbose *>&1 | Tee-Object -append -encoding "utf8" -FilePath $script:logFilePath
    toggleVerboseMode
    checkVerbosePreference
}
else 
{
    Write-Host "Debug mode not set by user, using default quiet mode." 
    installAgent($REG_KEY)  
}
# END OF SCRIPT
