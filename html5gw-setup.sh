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
  white=`tput setaf 7`
  reset=`tput sgr0`
  echo ""
  echo "==========================================================================="
  echo "${white}$1${reset}"
  echo "==========================================================================="
  echo ""
}
print_info(){
  white=`tput setaf 7`
  reset=`tput sgr0`
  echo "${white}INFO: $1${reset}"
  echo "INFO: $1" >> html5gw.log
}
print_success(){
  green=`tput setaf 2`
  reset=`tput sgr0`
  echo "${green}SUCCESS: $1${reset}"
  echo "SUCCESS: $1" >> html5gw.log
}
print_error(){
  red=`tput setaf 1`
  reset=`tput sgr0`
  echo "${red}ERROR: $1${reset}"
  echo "ERROR: $1" >> html5gw.log
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
  print_info "Installing New Packages - This may take some time"
  pkgarray=(cairo libpng libjpeg-turbo wget java-1.8.0-openjdk)
  for pkg in  ${pkgarray[@]}
  do
    pkg="$pkg"
    yum list $pkg > /dev/null
    if [[ $? -eq 0 ]]; then
      print_info "Installing $pkg"
      yum -y install $pkg >> html5gw.log 2>&1
      yum list $pkg > /dev/null
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
  print_head "Step 2: Installing and configuring Apache Tomcat"
  print_info "Setting up Apache Tomcat user"
  # Setup Tomcat User
  groupadd tomcat
  sudo useradd -s /bin/nologin -g tomcat -d /opt/tomcat tomcat >> html5gw.log
  
  # Extract tomcat contents
  print_info "Downloading Apache Tomcat 8.0.53"
  wget http://www-us.apache.org/dist/tomcat/tomcat-8/v8.0.53/bin/apache-tomcat-8.0.53.tar.gz >> html5gw.log 2>&1
  # Verify Apache Tomcat tar.gz file was downloaded, if not - Exit
  if [ -f $PWD/apache* ]; then
    print_info "Download succesfull - Installing Now"
    tar -xzvf apache-tomcat-8.0.53.tar.gz -C /opt/tomcat --strip-components=1 >> html5gw.log
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
	
  # Copy over the existing Tomcat Server Configuration file
  cp server.xml /opt/tomcat/conf/server.xml
  print_success "Apache Tomcat installed and configured"
}

firewall_config(){
  print_head "Step 3: Configuring firewall"
  print_info "configuring Firewall for PSMGW"
  firewall-cmd --permanent --add-forward-port=port=443:proto=tcp:toport=8443 >> html5gw.log 2>&1
  firewall-cmd --permanent --add-forward-port=port=80:proto=tcp:toport=8080 >> html5gw.log 2>&1
  firewall-cmd --reload >> html5gw.log
  print_success "Firewall configured"
}

install_psmgw(){
  print_head "Step 4: Installing and configuring HTML5 PSMGW"
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
  openssl req -x509 -nodes -days 365 -newkey rsa:4096 -keyout
  /opt/secrets/key.pem -out /opt/secrets/cert.crt -config guac-ssl.cnf
  > /dev/null 2>&1
  keytool -import -alias psmgw_guacd_cert -keystore /opt/secrets/keystore -trustcacerts -file /opt/secrets/cert.crt -storepass "Cyberark1" -noprompt >> html5gw.log 2>&1
  print_success "Guacamole certificates generated and imported into Apache Keystore" 
	
	# Import guacd certs into the Java key store
  testpath=`readlink -f /usr/bin/java | sed "s:bin/java::"`
  keytool -import -alias psmgw_guacd_cert -keystore $testpath/lib/security/cacerts -trustcacerts -file /opt/secrets/cert.crt -storepass "changeit" -noprompt >> html5gw.log 2>&1
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
