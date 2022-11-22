sudo tee -a agent_configurator.sh > /dev/null <<"EOT"
    #!/bin/bash 
    #Date: 2022-11-21
    #SSM Agent Configurator v1.0
    set -e
    function check_enforce {
        if [[ $(getenforce 2>&1) =~ "command not found" ]]; then
            echo -e "SELinux is not enabled. Continuing with installation..."
        elif [[ $(getenforce) ]]; then
            if [[ -n "$(command -v semanage)" ]]; then 
                get_enforce
            else
            { 
                echo -e "The semanage pkg is not available. Installing policycoreutils python utils package..."
                if [[ -n $(sudo zypper --version 2>&1) ]]; then
                    sudo apt install policycoreutils-python-utils -y
                elif [[ -n $(sudo apt --version 2>&1) ]]; then    
                    sudo zypper install --no-confirm policycoreutils-python-utils
                elif [[ -n $(sudo yum --version 2>&1) ]]; then
                    sudo yum install policycoreutils-python-utils -y
                fi
                get_enforce    
            }
            fi
        fi
    }
    function get_enforce {    
        if [[ $(getenforce) = "Permissive" ]]; then
            sudo semanage port -a -t syslogd_port_t -p tcp 1514
        elif [[ $(getenforce) = "Enforcing" ]]; then
            sudo setenforce 0
            sudo semanage port -a -t syslogd_port_t -p tcp 1514
            sudo setenforce 1
        fi
    }
    function make_syslog { 
        if [ -f /etc/rsyslog.conf ]; then  
            echo '*.* @@127.0.0.1:1514;RSYSLOG_FileFormat' | sudo tee -a /etc/rsyslog.conf 
            sudo systemctl restart rsyslog 
        elif [ -f /etc/syslog-ng/syslog-ng.conf ]; then 
            echo 'destination d_alertlogic {tcp("localhost" port(1514));};' | sudo tee -a /etc/syslog-ng/syslog-ng.conf
            echo 'log { source(s_sys); destination(d_alertlogic); };' | sudo tee -a /etc/syslog-ng/syslog-ng.conf 
            sudo systemctl restart syslog-ng 
        fi
        echo 'Finished.' 
    }
    if [[ -n "$(pgrep al-agent)" ]]; then
        echo "Agent service started."
        check_enforce
        make_syslog
    elif [[ -z "$(pgrep al-agent)" ]]; then
        echo "Agent service not started."
        sudo /etc/init.d/al-agent start
        check_enforce
        make_syslog
    else
        echo "Agent was installed but agent services failed to start. Please check your system init and try again."
        exit 1
    fi
EOT
sudo chmod +x agent_configurator.sh
./agent_configurator.sh 
