#!/bin/bash
# Alert Logic Agent Installer $a_version
# Copyright Alert logic, Inc. 2022. All rights reserved.
##########################################################################################################
# ENTER YOUR REGISTRATION KEY HERE. Your key can be found in the Alert Logic console.
# In the console, click the hamburger menu. Click Configure > Deployments. Select the DataCenter deployment
# this agent will reside in. Scroll in the left nav menu to the bottom and click Installation Instructions.
# Copy the Unique Registration Key and paste it below between the double quote marks. Make sure to enable 
# the line by removing the # symbol at the beginning of the line.
#
    # key="YOUR_REGISTRATION_KEY_HERE"
#
##########################################################################################################

function usage {
    sn=$(echo "$0" | sed 's/..//')
    echo -e "
--------------Alert Logic Agent Installer $a_version----------------

Usage: "$sn" [-key <key>] | [-help]
    
    -key <key>      The key to provision the agent with.
    -help           Display this help message.
   
This script will check Linux virtual machines' init and pkg manager configurations and then install the appropriate Alert 
Logic Agent. It will also check for SELinux and semanage utilities to allow log traffic. If semanage (python utils) is not
installed, this script will download and install policycoreutils which include semanage using the native software manager 
(yum/apt/zypper). Then it will modify all necessary syslog config files for log forwarding, restart the rsyslog service,
and finally will start/restart the Alert Logic agent service. 

NOTE: In AWS, use SSM to deploy this script to target Linux EC2 VMs.
NOTE: In Azure, use Azure Cloud Shell to deploy this script to the target Linux VMs.
Refer to Alert Logic documentation for more information.
            
For DataCenter deployments, a registration key must be used. There are two ways to supply the key:
    1. Paste the key directly into the script and uncomment the line by removing the #.
    2. Supply the key as an argument to the script. The key its the only argument the script accepts.
    
For cloud based virtual machines (AWS and Azure) no registration key is required.     

Example: >" $sn "-key '1234567890abcdef1234567890aabcdef1234567890abcdef'
Example: > source  "$sn" -key '1234567890abcdef1234567890aabcdef1234567890abcdef'
Example: > ./"$sn" -help

It is strongly advised that this installer be run with sudo privileges to ensure correct installation and configuration 
of the agent.

For more help, please contact Alert Logic Technical Support.                
"   
}
#################################### OPTIONAL CONFIGURATION ##############################################
# If you have set up a proxy, and you want to specify the proxy as a single point of egress for agents to use, uncomment one of
# the lines below and set either the proxy IP address or the hostname.
# NOTE: A TCP or an HTTP proxy may be used in this configuration.
# proxy_ip="192.168.1.1:8080"
# proxy_host="proxy.example.com:1234"

# Syslog configuration options. The script will try to ascertain whether ng-syslog or rsyslog is installed and configure the
# appropriate file. If that fails, you can specify the file to be used here. If you are collecting syslogs in a non-standard 
# folder set the file path here.

# Packages will be linked but only downloaded when the agent is ready to be installed.
deb32="https://scc.alertlogic.net/software/al-agent_LATEST_i386.deb"
deb64="https://scc.alertlogic.net/software/al-agent_LATEST_amd64.deb"
deb64arm="https://scc.alertlogic.net/software/al-agent_LATEST_arm64.deb"
rpm32="https://scc.alertlogic.net/software/al-agent-LATEST-1.i386.rpm"
rpm64="https://scc.alertlogic.net/software/al-agent-LATEST-1.x86_64.rpm"
rpmarm="https://scc.alertlogic.net/software/al-agent-LATEST-1.aarch64.rpm"
a_version="1.1.2"
# Check whether RPM or DEB is installed
function get_pkg_mgr () {
    pkg_mgr=""
    if [[ -f /usr/bin/dpkg ]]; then       
        pkg_mgr="dpkg"
    elif [[ -f /usr/bin/rpm ]]; then        
        pkg_mgr="rpm"
    elif [[ -n "$(rpm --version)" ]]; then  # additional checks to verify which pkgmgr is installed in subshell     
        pkg_mgr="rpm"
    elif [[ -n "$(dpkg --version)" ]]; then  # the conditional checks are necessary because some distros have both rpm and  
        pkg_mgr="dpkg"                       # dpkg installed        
    else
        echo "Unable to determine package manager. Exiting."
        usage      
        exit 1
    fi
    echo "Package manager is $pkg_mgr"
}
# Check CPU Architecture
function get_arch () {
    thisarch=""
    arch=$(uname -i)
    if [[ $arch = "x86_64" ]]; then
        thisarch="x64"
    elif [[ $arch = "i*86" ]] || [[ $arch = i686 ]]; then
        thisarch="386"
    elif  [[ $arch = "arm*" ]]; then
        thisarch="ARM"
    else
        echo "Unsupported architecture: $arch"
        usage
        exit 1
    fi
    echo "Detected architecture is $arch"
}
# Setup and install the agent
function install_agent () {
    get_arch
    get_pkg_mgr
    if [[ $pkg_mgr = "dpkg" ]]; then
        case $thisarch in
            "x64" )
                curl $deb64 --output al-agent.x64.deb
                sudo dpkg -i al-agent.x64.deb
                ;;
            "386" )
                curl $deb32 --output al-agent.x86.deb
                sudo dpkg -i al-agent.x86.deb
                ;;
            "ARM" )
                curl $deb64arm --output al-agent.arm.deb
                sudo dpkg -i al-agent.arm.deb
                ;;
        esac   
    elif [[ $pkg_mgr = "rpm" ]]; then
        case $thisarch in
            "x64" )
                curl $rpm64 --output al-agent.x86_64.rpm
                sudo rpm -U al-agent.x86_64.rpm
                ;;
            "386" )
                curl $rpm32 --output al-agent.i386.rpm
                sudo rpm -U al-agent.i386.rpm
                ;;
            "ARM" )
                curl $rpmarm --output al-agent.arm64.rpm
                sudo rpm -U al-agent.arm64.rpm
                ;;
       esac
    fi        
}
# Get init configuration information
function get_init_config () {
    init_type=""
    if [[ $(ps --noheaders -o comm 1) = "systemd" ]]; then
        init_type="systemd"
    elif [[ $(ps --noheaders -o comm 1) = "init" ]]; then
        init_type="init"
    else
        echo "Unknown init configuration. Exiting."
        usage
        exit 1
    fi
    echo "Detected init type is $init_type"
}
# Configure the agent options
function configure_agent () {
    get_init_config
    if [[ -n "$REG_KEY" ]]; then
        sudo /etc/init.d/al-agent provision --key $REG_KEY
    fi
    if [[ -n "$proxy_ip" ]]; then
        sudo /etc/init.d/al-agent configure --proxy $proxy_ip
        echo "Proxy IP set $proxy_ip"
    
    elif [[ -n "$proxy_host" ]]; then
        sudo /etc/init.d/al-agent configure --proxy $proxy_host
        echo "Proxy host set $proxy_host"
    fi
}
# Configure SYSLOG Collection
function make_syslog_config () {
    syslogng_conf_file="/etc/syslog-ng/syslog-ng.conf"
    syslog_conf_file="/etc/rsyslog.conf"
    if [[ -f "$syslogng_conf_file" ]] && [[ -z $(cat "$syslogng_conf_file" | grep "log { source(s_sys); destination(d_alertlogic); };") ]]; then 
        echo "destination d_alertlogic {tcp("localhost" port(1514));};" | sudo tee -a $syslogng_conf_file
        echo "log { source(s_sys); destination(d_alertlogic); };" | sudo tee -a $syslogng_conf_file
        if [[ $( tail -n 1 "$syslogng_conf_file") =~ "log { source(s_sys); destination(d_alertlogic); };" ]]; then
            sudo systemctl restart syslog-ng
            echo "Agent rsyslogng config file $syslogng_conf_file was successfully modified."
        fi    
    elif [[ -f "$syslog_conf_file" ]] && [[ -z $(cat "$syslog_conf_file" | grep "*.* @@127.0.0.1:1514;RSYSLOG_FileFormat") ]]; then 
        echo "*.* @@127.0.0.1:1514;RSYSLOG_FileFormat" | sudo tee -a $syslog_conf_file
        if [[ $( tail -n 1 "$syslog_conf_file") =~ "*.* @@127.0.0.1:1514;RSYSLOG_FileFormat" ]]; then
            sudo systemctl restart rsyslog
            echo "Agent rsyslog config file $syslog_conf_file was successfully modified."
        fi
    elif [[ -n $(cat "$syslog_conf_file" | grep "*.* @@127.0.0.1:1514;RSYSLOG_FileFormat") ]]; then
        echo "rsyslog was already configured. No changes were made to $syslog_conf_file"
        return
    elif [[ -n $(cat "$syslogng_conf_file" | grep "log { source(s_sys); destination(d_alertlogic); };") ]]; then
        echo "rsyslogng was already configured. No changes were made to $syslogng_conf_file"
        return
    else    
        echo "No syslog configuration file was found. Please configure rsyslog manually."
    fi
} 
function check_enforce {
    if [[ $(getenforce 2>&1) =~ "command not found" ]]; then
        echo "SELinux is not enabled. Semanage utils will not be installed."
        return
    elif [[ $(getenforce 2>&1) =~ "Disabled" ]]; then
        echo "SELinux is enabled but getenforce is disabled. Semanage utils will not be installed."
        return
    elif [[ $((sudo semanage port -a -t syslogd_port_t -p tcp 1514) 2>&1) =~ "ValueError" ]]; then
        echo "SELinux is enabled and semanage is installed but syslogd tcp port 1514 has already been set"
        echo "by semanage. Continuing syslog configuration script..."
        return
    elif [[ -n $(command -v semanage 2>&1) ]]; then
            echo "SELinux is enabled but semanage is not available."
            echo "Installing semanage with policycoreutils python utils package..."       
        if [[ -n $(command -v apt 2>&1) ]]; then
            echo "using apt to install policycoreutils..."
            sudo apt install policycoreutils-python-utils -y
        elif [[ -n $(command -v zypper 2>&1) ]]; then
            echo "using zypper to install policycoreutils..."
            sudo zypper install --no-confirm policycoreutils-python-utils
        elif [[ -n $(command -v yum 2>&1) ]]; then
            echo "using yum to install policycoreutils..."
            sudo yum install policycoreutils-python-utils -y
        else
            echo "semanage tool could not be installed, contact your system administrator."
            exit 1    
        fi
        get_enforce
        return
    else
       echo "SELinux is enabled but semanage status could not be determined. Contact your administrator"    
       exit 1
    fi
}
function get_enforce {    
    if [[ $(getenforce) = "Permissive" ]]; then
        echo "getenforce reported Permissive SELinux configuration. Running semanage..."
        sudo semanage port -a -t syslogd_port_t -p tcp 1514    
    elif [[ $(getenforce) = "Enforcing" ]] && [[ -n $((command -v setenforce) 2>&1) ]]; then
        echo "getenforce reported Enforcing SELinux configuration. Toggling setenforce and running semanage..."
        setenforce 0
        sudo semanage port -a -t syslogd_port_t -p tcp 1514
        setenforce 1 
    fi
}
# Install the agent and configure it
function run_install {
    if [[ -f /etc/init.d/al-agent ]]; then
        echo "Looks like the agent is already installed on this host. Checking al-agent service status..."
        if [[ $((sudo /etc/init.d/al-agent status) 2>&1) =~ "al-agent is running" ]]; then
            echo "Agent service already running. Restarting..."
            sudo /etc/init.d/al-agent restart
            if [[ -n "$(pgrep al-agent)" ]]; then
                echo "Agent service was restarted."
            fi    
        elif [[ $((sudo /etc/init.d/al-agent status) 2>&1) =~ "al-agent is NOT running" ]]; then
            echo "Agent service is not running. Attempting to start service..."    
            sudo /etc/init.d/al-agent restart
            if [[ -n "$(pgrep al-agent)" ]]; then
                echo "Agent service was started."
            fi
        fi    
        check_enforce
        make_syslog_config
        echo "Agent configuration was successful."
        return
    elif [[ $((sudo /etc/init.d/al-agent status) 2>&1) =~ "command not found" ]] || [[ $((sudo /etc/init.d/al-agent status) 2>&1) =~ "No such file or directory" ]]; then
        install_agent
        if [[ $((sudo /etc/init.d/al-agent status) 2>&1) =~ "al-agent is running" ]]; then
            if [[ -n "$(pgrep al-agent)" ]]; then
                echo "Agent installation was completed."
                return
            fi    
        elif [[ $((sudo /etc/init.d/al-agent status) 2>&1) =~ "al-agent is NOT running" ]]; then
            sudo /etc/init.d/al-agent start
            if [[ -n "$(pgrep al-agent)" ]]; then
                echo "Agent installation was completed. Service was started."
                return
            fi
        fi
        check_enforce
        make_syslog_config
        echo "Agent installation and configuration completed successfully."   
    else 
        echo "Agent was installed but the service failed to start. Please check your system init and try again."
        exit 1
    fi
}
# Get command line args and Start script processing
if [[ $1 = "-key" ]] || [[ $1 = "--key" ]] || [[ $1 = "-k" ]]; then
    if [[ -z "$2" ]]; then
        echo "Key switch (-k|--key) set but no registration key was provided. Exiting."
        usage
        exit 1
    else
        REG_KEY=$2
        echo "REG KEY is $REG_KEY"
        run_install
    fi
elif [[ $1 = "-help" ]]; then
    usage
    exit 0
elif [[ $# = 0 ]] && [[ -n "$REG_KEY" ]]; then
    echo "REG KEY was retrieved from script section: $REG_KEY"
    run_install
elif [[ $# = 0 ]] && [[ -z "$REG_KEY" ]]; then
    echo "No registration key provided. Check if agent script is in Cloud Environment (AWS, Azure)"
    echo "If this agent is installed in a Datacenter environment, it will not provision without a registration key!"
    echo "Proceeding without a registration key..."
    run_install
else
    echo "Invalid option(s): $@. Exiting."
    usage
    exit 1
fi
#END SCRIPT
