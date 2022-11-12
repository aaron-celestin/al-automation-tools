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
    echo "Alert Logic Agent Installer $a_version
Usage:" $0 "[-key <key>] | [-help]
    
    -key <key>      The key to provision the agent with.
    -help           Display this help message.
   
This script will check a Linux virtual machines init and pkg manager configurations and then install the appropriate Alert 
Logic Agent. Cloud environments AWS and Azure do not require registration keys to provision to Alert Logics backend. Thus,
this script is not neccessary for those environments. 

NOTE: In AWS, use SSM to deploy this script to target EC2 instances.
NOTE: In Azure, use Azure Cloud Shell to deploy this script to the target instances.
Refer to Alert Logic documentation for more information.
            
For DataCenter deployments, a registration key must be used. There are two ways to supply the key:
    1. Paste the key directly into the script and uncomment the line by removing the #.
    2. Supply the key as an argument to the script. The key its the only argument the script accepts.

Example: >" $0 "-key '1234567890abcdef1234567890aabcdef1234567890abcdef'
Example: > source  "$0" -key '1234567890abcdef1234567890aabcdef1234567890abcdef'
Example: > ./scriptname.sh -help

It is strongly advised that this installer be run with sudo priviliges to ensure correct installation and configuration 
of the agent.

For help, contact Alert Logic Technical Support.                
"   
}
#################################### OPTIONAL CONFIGURATION ##############################################
# If you have set up a proxy, and you want to specify the proxy as a single point of egress for agents to use, uncomment one of
# the lines below and set either the proxy IP address or the hostname.
# NOTE: A TCP or an HTTP proxy may be used in this configuration.
# proxy_ip="192.168.1.1:8080"
# proxy_host="proxy.example.com:1234"

# Syslog configuration options. The script will try to ascertain whether ng-syslog or rsyslog is installed and configure the appropriate file. If that fails, you 
# can specify the file to be used here. If you are collecting syslogs in a non-standard folder set the file path here.
syslogng_conf_file="/etc/syslog-ng/syslog-ng.conf"
syslog_conf_file="/etc/rsyslog.conf"

# Packages will be linked but only downloaded when the agent is ready to be installed.
deb32="https://scc.alertlogic.net/software/al-agent_LATEST_i386.deb"
deb64="https://scc.alertlogic.net/software/al-agent_LATEST_amd64.deb"
deb64arm="https://scc.alertlogic.net/software/al-agent_LATEST_arm64.deb"
rpm32="https://scc.alertlogic.net/software/al-agent-LATEST-1.i386.rpm"
rpm64="https://scc.alertlogic.net/software/al-agent-LATEST-1.x86_64.rpm"
rpmarm="https://scc.alertlogic.net/software/al-agent-LATEST-1.aarch64.rpm"

a_version="0.8.2"

# Check whether RPM or DEB is installed
function get_pkg_mgr () {
    pkg_mgr=""
    if [ -f /usr/bin/dpkg ]; then       
        pkg_mgr="dpkg"
    elif [ -f /usr/bin/rpm ]; then        
        pkg_mgr="rpm"
    elif [ -n $(rpm --version) ]; then  # additional checks to verify which pkgmgr is installed in subshell     
        pkg_mgr="rpm"
    elif [ -n $(dpkg --version) ]; then  # the conditional checks are necessary because some distros have both rpm and dpkg installed      
        pkg_mgr="dpkg"
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
    echo "Detected architecture is $arch"
    if [[ $arch = x86_64 ]]; then
        thisarch="x64"
    elif [[ $arch = i*86 ]] || [[ $arch -eq i686 ]]; then
        thisarch="386"
    elif  [[ $arch = arm* ]]; then
        thisarch="ARM"
    else
        echo "Unsupported architecture: $arch"
        usage
        exit 1
    fi
    echo "Architecture is $thisarch"
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
 
    if [ ! -z $REG_KEY ]; then
        sudo /etc/init.d/al-agent provision --key $REG_KEY
        echo "Registration key set $REG_KEY"
    fi
    if [ ! -z $proxy_ip ]; then
        sudo /etc/init.d/al-agent configure --proxy $proxy_ip
        echo "Proxy IP set $proxy_ip"
    elif [ ! -z $proxy_host ]; then
        sudo /etc/init.d/al-agent configure --proxy $proxy_host
        echo "Proxy host set $proxy_host"
    fi
}

# Configure SYSLOG Collection
function make_syslog_config () {
    if [[ -f $syslogng_conf_file ]]; then #check if given ngsyslog file exists
        echo "destination d_alertlogic {tcp("localhost" port(1514));};" | sudo tee -a $syslogng_conf_file
        echo "log { source(s_sys); destination(d_alertlogic); };" | sudo tee -a $syslogng_conf_file
        sudo systemctl restart syslog-ng
    elif [[ -f $syslog_conf_file ]]; then #check if given rsyslog file exists
        echo "*.* @@127.0.0.1:1514;RSYSLOG_FileFormat" | sudo tee -a $syslog_conf_file
        sudo systemctl restart rsyslog
    else
        echo "No syslog configuration file found. Please configure syslog manually."
    fi
}

# Check SELinux Status using semanage
# If the semanage command is not present in your system, you can install the policycoreutils-python package to obtain the semanage command. 
function check_enforce () {
    se_status=$(getenforce)
    echo "sestatus is $se_status"
    if [[ $se_status ]]; then
        if [ -n $(command -v semanage) ]; then 
           if [[ $(getenforce) = "Permissive" ]]; then
                sudo semanage port -a -t syslogd_port_t -p tcp 1514
            elif [[ $(getenforce) = "Enforcing" ]]; then
                sudo setenforce 0
                sudo semanage port -a -t syslogd_port_t -p tcp 1514
                sudo setenforce 1
            fi
        else 
            echo "SELinux is enabled but semanage is not installed. Please configure SELinux manually or install the policycoreutils-python package."
        fi
    else 
        echo "SELinux is not enabled."
    fi 
}

# Install the agent with default settings
function run_install {
    install_agent
    check_enforce
    configure_agent
    make_syslog_config
    echo "Install complete."   
}



if [[ $1 = "-key" ]]; then
    if [[ -z $2 ]]; then
        echo "Registration key not provided. Exiting."
        usage
        exit 1
    else
        REG_KEY=$2
        echo "REG KEY is $REG_KEY"
        run_install
    fi
    REG_KEY=$2
elif [[ $1 = "-help" ]]; then
    usage
    exit 0
elif [[ $# = 0 ]]; then
    echo "REG KEY is in script: $REG_KEY"
    run_install
else
    echo "Invalid option(s): $@. Exiting."
    usage
    exit 1
fi