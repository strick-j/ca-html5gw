#!/bin/bash

function main(){
  system_prep
  gather_info
  install_tomcat
  firewall_config
  install_psmgw
  update_guacd_config
  update_guacssl_config
  generate_guacd_certs
  restart_services
}

# Generic output functions
print_head(){
  local white=`tput setaf 7`
  local reset=`tput sgr0`
  echo ""
  echo "==========================================================================="
  echo "${white}$1${reset}"
  echo "==========================================================================="
  echo ""
}

print_info(){
  local white=`tput setaf 7`
  local reset=`tput sgr0`
  echo "${white}INFO: $1${reset}"
  echo "INFO: $1" >> html5gw.log
}

print_success(){
  local green=`tput setaf 2`
  local reset=`tput sgr0`
  echo "${green}SUCCESS: $1${reset}"
  echo "SUCCESS: $1" >> html5gw.log
}

print_error(){
  local red=`tput setaf 1`
  local reset=`tput sgr0`
  echo "${red}ERROR: $1${reset}"
  echo "ERROR: $1" >> html5gw.log
}

print_warning(){
  local yellow=`tput setaf 3`
  local reset=`tput sgr0`
  echo "${yellow}WARNING: $1${reset}"
  echo "WARNING: $1" >> html5gw.log
}

testkey(){
  # Function to list certificates in the keystore and verify keytool imports
  # List keytool and export to file
  print_info "Checking $1 keystore for $2 alias"
  keytool -list -v -keystore $1 -alias $2 -storepass $3 > temp.log 2>&1

  # Read in first line from file
  line=$(head -n 1 temp.log)
  verify="Alias name: $2"

  # Compare log file and expected key alias
  if [[ $line == $verify ]]; then
    print_success "$2 successfully imported into $1 keystore"
  else
    print_error "$2 not present in $1 keystore. Exiting now..."
    exit 1
  fi
 
  # Concatenate temp log and cleanup
  cat temp.log >> html5gw.log
  rm temp.log
}

pushd () {
  command pushd "$@" > /dev/null
}

popd () {
  command popd "$@" > /dev/null
}

system_prep(){
  print_head "Step 1: Installing system updates and required prerequisite packages"
  touch html5gw.log
  yum clean all >> html5gw.log
  echo "Log file generated on $(date)" >> html5gw.log

  print_info "Validating HTMl5GW rpm is present"
  if [[ $PWD/CARKpsmgw* ]] && [[ $PWD/RPM-GPG-KEY-CyberArk]]; then
    print_success "Installation rpm and gpg key are present, proceeding..."
  else
    print_error "Installation rpm is missing. Exiting..."
    exit 1
  fi

  print_info "Installing New Packages - This may take some time"
  pkgarray=(cairo libpng libjpeg-turbo wget java-1.8.0-openjdk java-1.8.0-openjdk-devel openssl)
  for pkg in  ${pkgarray[@]}
  do
    pkg="$pkg"
    yum list $pkg > /dev/null
    if [[ $? -eq 0 ]]; then
      print_info "Installing $pkg"
      yum -y install $pkg >> html5gw.log 2>&1
      yum list installed $pkg > /dev/null
      # Check if packages installed correctly, if not - Exit
      if [[ $? -eq 0 ]]; then
        print_success "$pkg installed."
      else
        print_error "$pkg could not be installed. Exiting...."
        exit 1
      fi
    else
      print_error "Required package - $pkg - not found. Exiting..."
      exit 1
    fi
  done
  print_success "Required packages installed."
}

gather_info(){
  print_head "Step 2: Collecting user provided information"
  done=0
  while : ; do
    read -p 'Please enter fully qualified domain name or hostname: ' hostvar
    print_info "You entered $hostvar, is this correct (Yes or No)? "
    select yn in "Yes" "No"; do
      case $yn in 
        Yes ) done=1; break;;
        No ) echo ""; break;; 
      esac
    done
    if [[ "$done" -ne 0 ]]; then
      break
    fi
  done
}

install_tomcat(){
  print_head "Step 3: Installing and configuring Apache Tomcat"
  print_info "Setting up Apache Tomcat user"
  # Setup Tomcat User
  groupadd tomcat
  sudo useradd -s /bin/nologin -g tomcat -d /opt/tomcat tomcat >> html5gw.log
  
  print_info "Searching for correct Apache URL"

  # Specify major version of Tomcat desired
  wanted_ver=9
  # Use curl to search for latest minor version of specified major version
  tomcat_ver=`curl --silent https://downloads.apache.org/tomcat/tomcat-${wanted_ver}/ | grep v${wanted_ver} | awk '{split($5,c,">v") ; split(c[2],d,"/") ; print d[1]}' | tail -n 1`
  # Create URL based on curl
  apache_url="https://downloads.apache.org/tomcat/tomcat-${wanted_ver}/v${tomcat_ver}/bin/apache-tomcat-${tomcat_ver}.tar.gz"
  if [[ `curl -Is ${apache_url}` == *200* ]] ; then
    print_success "URL Found: ${apache_url}"
    print_info "Downloading Apache Tomcat v${tomcat_ver}"
    wget $apache_url >> html5gw.log 2>&1
  else 
    print_error "Apache Tomcat could not be downloaded. Exiting now..."
    exit 1
  fi

  # Verify Apache Tomcat tar.gz file was downloaded, if not - Exit
  if [ -f $PWD/apache* ]; then
    print_info "Apache Tomcat v${tomcat_ver} download succesful - Installing Now"
    tar -xzvf apache-tomcat-${tomcat_ver}.tar.gz -C /opt/tomcat --strip-components=1 >> html5gw.log
  else
    print_error "Apache Tomcat could not be downloaded. Exiting now..."
    exit 1
  fi
	
  # Set Tomcat Permissions
  print_info "Setting Tomcat folder permissions"
  pushd /opt/tomcat
  sudo chgrp -R tomcat conf
  sudo chmod g+rwx conf
  sudo chmod g+r conf/*
  sudo chown -R tomcat logs/ temp/ webapps/ work/
  sudo chgrp -R tomcat bin
  sudo chgrp -R tomcat lib
  sudo chmod g+rwx bin
  sudo chmod g+r bin/*
  popd
	
  # Create and enable Tomcat Service
  print_info "Creating Tomcat Service"
  cp tomcat.service /etc/systemd/system/tomcat.service >> html5gw.log
  systemctl daemon-reload >> html5gw.log
  systemctl enable tomcat >> html5gw.log 2>&1
	
  # Configure Tomcat Self Signed Certificate
  print_info "Creating Tomcat Self Signed Certificate"
  mkdir /opt/secrets
  keytool -genkeypair -alias psmgw -keyalg RSA -keystore /opt/secrets/keystore -ext san=dns:$hostvar -keypass "Cyberark1" -storepass "Cyberark1" -dname "cn=$hostvar, ou=POC, o=POC, c=US" >> html5gw.log 2>&1
	
  # Verify Keytool Import was successful
  testkey "/opt/secrets/keystore" "psmgw" "Cyberark1"
  
  # Export certificate in .cer format
  print_info "Exporting Tomcat Certificate from Keystore"
  keytool -export -keystore /opt/secrets/keystore -alias psmgw -file tomcat.cer -storepass "Cyberark1" >> html5gw.log 2>&1

  # Copy over the existing Tomcat Server Configuration file
  cp server.xml /opt/tomcat/conf/server.xml
  print_success "Apache Tomcat installed and configured"
}

firewall_config(){
  print_head "Step 4: Configuring firewall"
  # Verify firewalld is installed, if installed check if enabled, if not enabled prompt to start  
  local firewalldservice=firewalld
  print_info "Verifying $firewalldservice is installed"
  yum list installed $firewalldservice > /dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    print_success "$firewalldservice is installed" 
    print_info "Checking status of $firewalldservice"
    if [[ `systemctl is-active firewalld` != "active" ]]; then
      # Prompt user and start firewalld if they would like
      local done=0
      while : ; do
        print_warning "$firewalldservice is not running, would you like to start it?"
        select yn in "Yes" "No"; do
          case $yn in
            Yes ) 
              echo ""
              `systemctl start firewalld` >> html5gw.log 2>&1
              if [[ `systemctl is-active firewalld` = "active" ]]; then
                print_success "$firewalldservice started"
              else
                print_error "$firewalldservice could not be started, please manually configure"
              fi
              done=1
              break;;
            No ) 
              echo ""
              print_warning "$firewalldservice will not be started"
              done=1
              break;;
          esac
        done
        if [[ "$done" -ne 0 ]]; then
          break
        fi
      done
    fi
      # Verify firewall is running after prompt and configure firewall
      if  [[ `systemctl is-active firewalld` = "active" ]]; then
        print_info "Configuring Firewall for PSMGW"
        firewall-cmd --permanent --add-forward-port=port=443:proto=tcp:toport=8443 >> html5gw.log 2>&1
        firewall-cmd --permanent --add-forward-port=port=80:proto=tcp:toport=8080 >> html5gw.log 2>&1
        firewall-cmd --reload >> html5gw.log
  
        print_info "Gathering active firewall zone information"
        firewall-cmd --get-active-zones >> html5gw.log
        verfirewallcmd=$(tail -2 html5gw.log | head -1)
  
        print_info "Active zone is "$verfirewallcmd", gathering forward port information"
        firewall-cmd --zone="$verfirewllcmd" --list-forward-ports >> html5gw.log
        rule1=$(tail -2 html5gw.log | head -1)
        rule2=$(tail -1 html5gw.log)
  
        print_info "Verifying forward ports are correct"
        # Verify port 443 rules are setup properly, exit if not
        if [[ $rule1 == "port=443:proto=tcp:toport=8443:toaddr="  ]]; then
          print_success "Port 443 Port Forwarding is correct"
        else
          print_error "Port 443 Port Forwarding is not setup properly, exiting now..."
          exit 1
        fi
        # Verify port 80 rules are setup properly, exit if not
        if [[ $rule2 == "port=80:proto=tcp:toport=8080:toaddr=" ]]; then
          print_success "Port 80 Port Forwarding is correct"
        else
          print_error "Port 80 Port Forwarding is not setup properly, exiting now..."
          exit 1
        fi

        # Firewall configured properly, print success
        print_success "Firewall configured"
      else
        print_warning "$firewalldservice is not running, enabling $firewalldservice is recommended"
        print_warning "Skipping $firewalldservice configuration"
      fi
  else
    print_warning "$firewalldservice is not installed, installing and enabling $firewalldservice is recommended"
    print_warning "Skipping $firewalldservice configuration"
  fi
}

function preinstall_gpgkey() {
   "Verifying rpm GPG Key is present"
  if [[ -f ${CYBR_DIR}/RPM-GPG-KEY-CyberArk ]]; then
    # Import GPG Key
    write_to_terminal "GPG Key present - Importing..."
    #TODO: Catch import error
    rpm --import "INSTALLFILES"/RPM-GPG-KEY-CyberArk
    write_to_terminal "GPG Key imported, proceeding..."
  else
    # Error - File not found
    write_to_terminal "RPM GPG Key not found, verify needed files have been copied over. Exiting now..."
    exit 1
  fi  
  printf "\n"
}

install_psmgw(){
  print_head "Step 5: Installing and configuring HTML5 PSMGW"
  print_info "Verifying rpm GPG Key is present"
  if [[ -f $PWD/RPM-GPG-KEY-CyberArk ]]; then
    # Import GPG Key
    print_info "GPG Key present - Importing..."
    #TODO: Catch import error
    rpm --import $PWD/RPM-GPG-KEY-CyberArk
    print_info "GPG Key imported, proceeding..."
  else
    # Error - File not found
    print_info "RPM GPG Key not found, verify needed files have been copied over. Exiting now..."
    exit 1
  fi 

  print_info "Verifying PSMGW has been placed within the repository"
  cp psmgwparms /var/tmp/psmgwparms
  # Check if required CyberArk files have been copied into the folder
  if [ -f $PWD/CARKpsmgw* ]; then
    print_info "PSMGW file found, Installing now"
    cp psmgwparms /var/tmp/psmgwparms
    psmgwrpm=`ls $dir | grep CARKpsmgw*`
    rpm -ivh $psmgwrpm >> html5gw.log 2>&1
  else
    print_error "CyberArk PSMGW file not in repository. Exiting now..."
    exit 1
  fi
  print_success "PSMGW Installed"
}

update_guacd_config(){
  print_info "Updating Guacamole Configuration File"
  cp /etc/guacamole/guacd.conf /etc/guacamole/guacd.old
  sed -i 's+# \[ssl\]+\[ssl\]+g' /etc/guacamole/guacd.conf
  sed -i 's+# server_cert.*+server_certificate\ \=\ \/opt\/secrets\/cert\.crt+g' /etc/guacamole/guacd.conf
  sed -i 's+# server_key.*+server_key\ \=\ \/opt\/secrets\/key\.pem+g' /etc/guacamole/guacd.conf
  print_success "Completed guacamole configure file modifications"
}

update_guacssl_config(){
  print_info "Updating guacamole SSL configuration file"
  cp $PWD/guac-ssl.cnf $PWD/guac-ssl.cnf.old
  sed -i "s+test.host.local+$hostvar+g" $PWD/guac-ssl.cnf
  print_success "Completed guacamole SSL configure file modifications"
}

generate_guacd_certs(){
  print_info "Generating self signed certificates for Guacamole"
  openssl req -x509 -nodes -days 365 -newkey rsa:4096 -keyout /opt/secrets/key.pem -out /opt/secrets/cert.crt -config guac-ssl.cnf > /dev/null 2>&1
  keytool -import -alias psmgw_guacd_cert -keystore /opt/secrets/keystore -trustcacerts -file /opt/secrets/cert.crt -storepass "Cyberark1" -noprompt >> html5gw.log 2>&1
  # Verify Keytool Import was successful
  testkey "/opt/secrets/keystore" "psmgw_guacd_cert" "Cyberark1"
  print_success "Guacamole certificates imported into Apache Keystore" 
	
  # Import guacd certs into the Java key store
  testpath=`readlink -f /usr/bin/java | sed "s:bin/java::"`
  keytool -import -alias psmgw_guacd_cert -keystore $testpath/lib/security/cacerts -trustcacerts -file /opt/secrets/cert.crt -storepass "changeit" -noprompt >> html5gw.log 2>&1
  # Verify Keytool Import was successful
  testkey "$testpath/lib/security/cacerts" "psmgw_guacd_cert" "changeit"
  print_success "Guacamole certificates imported into Java Keystore"
}

restart_services(){
  print_info "Restarting Tomcat and Guacamole"
  systemctl restart tomcat >> html5gw.log
  service guacd restart >> html5gw.log 2>&1

  # Test if services started properly
  print_info "Checking on status of Tomcat Service"
  local tomcatservice=tomcat
  if [[ $(ps -ef | grep -v grep | grep $tomcatservice | wc -l) > 0 ]]; then
    print_success "$tomcatservice is running!"
  else
    print_error "$tomcatservice is not running, please review tomcat logs."
  fi

  print_info "Checking on status of Guacamole Service"
  local guacservice=guacd
  if [[ $(ps -ef | grep -v grep | grep $guacservice | wc -l) > 0 ]]; then
    print_success "$guacservice is running!"
  else
    print_error "$guacservice is not running, please review guacd status and logs."
  fi
}
main
