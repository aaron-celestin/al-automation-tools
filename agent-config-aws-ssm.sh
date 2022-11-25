sudo tee -a agent_configurator.sh > /dev/null <<"EOT"
    # Packages will be linked but only downloaded when the agent is ready to be installed.
    deb32="https://scc.alertlogic.net/software/al-agent_LATEST_i386.deb"
    deb64="https://scc.alertlogic.net/software/al-agent_LATEST_amd64.deb"
    deb64arm="https://scc.alertlogic.net/software/al-agent_LATEST_arm64.deb"
    rpm32="https://scc.alertlogic.net/software/al-agent-LATEST-1.i386.rpm"
    rpm64="https://scc.alertlogic.net/software/al-agent-LATEST-1.x86_64.rpm"
    rpmarm="https://scc.alertlogic.net/software/al-agent-LATEST-1.aarch64.rpm"
    # Check whether package manager is RPM or DEB
    function get_pkg_mgr () {
        pkg_mgr=""
        if [[ -f /usr/bin/dpkg ]]; then       
            pkg_mgr="dpkg"
        elif [[ -f /usr/bin/rpm ]]; then        
            pkg_mgr="rpm"
        elif [[ -n "$(rpm --version)" ]]; then  # additional checks to verify which pkgmgr is installed in subshell     
            pkg_mgr="rpm"
        elif [[ -n "$(dpkg --version)" ]]; then  # the conditional checks are necessary because some distros have both rpm and dpkg installed      
            pkg_mgr="dpkg"
        else
            echo -e "Unable to determine package manager. Exiting. "
            usage      
            exit 1
        fi
        echo -e "Package manager is $pkg_mgr "
    }
    # Check CPU Architecture
    function get_arch () {
        thisarch=""
        arch=$(uname -i)
        echo -e " Detected architecture is $arch"
        if [[ $arch = "x86_64" ]]; then
            thisarch="x64"
        elif [[ $arch = "i*86" ]] || [[ $arch -eq i686 ]]; then
            thisarch="386"
        elif  [[ $arch = "arm*" ]]; then
            thisarch="ARM"
        else
            echo -e "Unsupported architecture: $arch"
            usage
            exit 1
        fi
        echo -e "Architecture is $thisarch"
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
            echo -e "Unknown init configuration. Exiting."
            usage
            exit 1
        fi
        echo -e "Detected init type is $init_type "
    }
    # Configure the agent options
    function configure_agent () {
        get_init_config
        if [[ -n "$REG_KEY" ]]; then
            sudo /etc/init.d/al-agent provision --key $REG_KEY
        fi
        if [[ -n "$proxy_ip" ]]; then
            sudo /etc/init.d/al-agent configure --proxy $proxy_ip
            echo -e "Proxy IP set $proxy_ip"

        elif [[ -n "$proxy_host" ]]; then
            sudo /etc/init.d/al-agent configure --proxy $proxy_host
            echo -e "Proxy host set $proxy_host"
        fi
    }
    # Configure SYSLOG Collection
    function make_syslog_config () {
        if [[ -f "$syslogng_conf_file" ]] && [[ $( tail -n 1 "$syslogng_conf_file") != "log { source(s_sys); destination(d_alertlogic); };" ]]; then 
            echo "destination d_alertlogic {tcp("localhost" port(1514));};" | sudo tee -a $syslogng_conf_file
            echo "log { source(s_sys); destination(d_alertlogic); };" | sudo tee -a $syslogng_conf_file
            if [[ $( tail -n 1 "$syslogng_conf_file") =~ "log { source(s_sys); destination(d_alertlogic); };" ]]; then
                sudo systemctl restart syslog-ng
                echo "Agent rsyslogng config file $syslogng_conf_file was successfully modified."
            fi    
        elif [[ -f "$syslog_conf_file" ]] && [[ $( tail -n 1 "$syslog_conf_file") != "*.* @@127.0.0.1:1514;RSYSLOG_FileFormat" ]]; then 
            echo "*.* @@127.0.0.1:1514;RSYSLOG_FileFormat" | sudo tee -a $syslog_conf_file
            if [[ $( tail -n 1 "$syslog_conf_file") =~ "*.* @@127.0.0.1:1514;RSYSLOG_FileFormat" ]]; then
                sudo systemctl restart rsyslog
                echo "Agent rsyslog config file $syslog_conf_file was successfully modified."
            fi
        elif [[ $( tail -n 1 "$syslog_conf_file") =~ "*.* @@127.0.0.1:1514;RSYSLOG_FileFormat" ]]; then
            echo "rsyslog was already configured. No changes were made to $syslog_conf_file"
        elif [[ $( tail -n 1 "$syslogng_conf_file") != "log { source(s_sys); destination(d_alertlogic); };" ]]; then
            echo "rsyslogng was already configured. No changes were made to $syslogng_conf_file"
        else    
            echo "No syslog configuration file was found. Please configure rsyslog manually."
        fi
    } 
    function check_enforce {
        if [[ $(getenforce 2>&1) =~ "command not found" ]]; then
            echo "SELinux is not enabled. Semanage utils will not be installed."
        elif [[ $(getenforce 2>&1) =~ "Disabled" ]]; then
            echo "SELinux is enabled but getenforce is disabled. Semanage utils will not be installed."
        elif [[ $((sudo semanage port -a -t syslogd_port_t -p tcp 1514) 2>&1) =~ "ValueError" ]]; then
            echo "SELinux is enabled and semanage is installed and syslogd tcp port 1514 has already been set"
            echo "by semanage. Continuing syslog configuration script..."
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
            fi
            get_enforce
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
            echo "setenforce 0"
            setenforce 0
            sudo semanage port -a -t syslogd_port_t -p tcp 1514
            setenforce --version #temp placeholder to prevent getenforce from turning on and locking users out
        fi
    }
    # Install the agent and configure it
    function run_install {
        if [[ -f /etc/init.d/al-agent ]]; then
            echo "Looks like the agent is already installed on this host. Running config fuctions...\"",
            check_enforce
            make_syslog_config
        else
            install_agent
            check_enforce
            make_syslog_config
        fi
        if [[ $((sudo /etc/init.d/al-agent status) 2>&1) =~ "al-agent is NOT running" ]]; then
            sudo /etc/init.d/al-agent start
            if [[ -n "$(pgrep al-agent)" ]]; then
                echo "Agent service was started. Install complete."
            fi    
        elif [[ $((sudo /etc/init.d/al-agent status) 2>&1) =~ "al-agent is running" ]]; then
            echo "Agent service already running. Restarting..."
            sudo /etc/init.d/al-agent restart     
            if [[ -n "$(pgrep al-agent)" ]]; then
                echo "Agent service restarted. Install complete."
            fi    
        else 
            echo "Agent was installed but the service failed to start. Please check your system init and try again."
            exit 1
        fi
    }
    run_install
EOT
sudo chmod +x agent_configurator.sh
./agent_configurator.sh 
