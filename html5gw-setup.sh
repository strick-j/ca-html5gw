#!/bin/bash

function main(){
	system_prep
	install_tomcat
	firewall_config
	install_psmgw
	update_guacd_config
	generate_guacd_certs
	restart_services
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
}

pushd () {
    command pushd "$@" > /dev/null
}

popd () {
    command popd "$@" > /dev/null
}

system_prep(){
	# Install system updates and required prerequisite packages
	touch html5gw.log
	yum clean all >> html5gw.log
	echo "Log file generated on $(date)" >> html5gw.log
	print_info 'Installing updates - This may take a while'
	#yum update -y >> html5gw.log
	yum install cairo libjpg libpng wget java-1.8.0-openjdk -y >> html5gw.log
	print_success 'Installed updates'
}

install_tomcat(){
	print_info 'Setting up Apache Tomcat user'
	# Setup Tomcat User
	groupadd tomcat
	sudo useradd -s /bin/nologin -g tomcat -d /opt/tomcat tomcat >> html5gw.log

	# Extract tomcat contents
	print_info 'Downloading and install Apache Tomcat 8.0.52'
	wget http://www-us.apache.org/dist/tomcat/tomcat-8/v8.0.52/bin/apache-tomcat-8.0.52.tar.gz >> html5gw.log 2>&1
	tar -xzvf apache-tomcat-8.0.52.tar.gz -C /opt/tomcat --strip-components=1 >> html5gw.log

	# Set Tomcat Permissions
	print_info 'Setting Tomcat folder permissions'
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
	print_info 'Creating Tomcat Service'
	cp tomcat.service /etc/systemd/system/tomcat.service >> html5gw.log
	systemctl daemon-reload >> html5gw.log
	systemctl enable tomcat >> html5gw.log 2>&1
	
	# Configure Tomcat Self Signed Certificate
	print_info 'Creating Tomcat Self Signed Certificate'
	mkdir /opt/secrets
	keytool -genkeypair -alias psmgw -keyalg RSA -keystore /opt/secrets/keystore -ext san=dns:html5gw2.cyberarkdemo.com -keypass "Cyberark1" -storepass "Cyberark1" -dname "cn=psmgw.cyberarkdemo.com, ou=POC, o=POC, c=US" >> html5gw.log 2>&1
	
	# Copy over the existing Tomcat Server Configuration file
	cp server.xml /opt/tomcat/conf/server.xml
	print_success 'Apache Tomcat installed and configured'
}

firewall_config(){
	print_info 'configuring Firewall for PSMGW'
	firewall-cmd --permanent --add-forward-port=port=443:proto=tcp:toport=8443 >> html5gw.log 2>&1
	firewall-cmd --permanent --add-forward-port=port=80:proto=tcp:toport=8080 >> html5gw.log 2>&1
	firewall-cmd --reload >> html5gw.log
	print_success 'Firewall configured'
}

install_psmgw(){
	print_info 'Installing PSMGW'
	cp psmgwparms /var/tmp/psmgwparms
	rpm -ivh CARKpsmgw-10.03.0.5.el7.x86_64.rpm >> html5gw.log 2>&1
	print_success 'PSMGW Installed'
}

update_guacd_config(){
	print_info 'Updating Guacamole Configuration File'
	cp /etc/guacamole/guacd.conf /etc/guacamole/guacd.old
	sed -i 's+# \[ssl\]+\[ssl\]+g' /etc/guacamole/guacd.conf
	sed -i 's+# server_cert.*+server_certificate\ \=\ \/opt\/secrets\/cert\.crt+g' /etc/guacamole/guacd.conf
	sed -i 's+# server_key.*+server_key\ \=\ \/opt\/secrets\/key\.pem+g' /etc/guacamole/guacd.conf
	print_success 'Completed guacamole configure file modifications'
}

generate_guacd_certs(){
	print_info 'Generating self signed certificates for Guacamole'
	openssl req -x509 -nodes -days 365 -newkey rsa:4096 -keyout /opt/secrets/key.pem -out /opt/secrets/cert.crt -config guac-ssl.cnf > /dev/null 2>&1
	keytool -import -alias psmgw_guacd_cert -keystore /opt/secrets/keystore -trustcacerts -file /opt/secrets/cert.crt -storepass "Cyberark1" -noprompt >> html5gw.log 2>&1
	print_success 'Guacamole certificates generated and imported into Apache Keystore' 
	
	# Import guacd certs into the Java key store
	testpath=`readlink -f /usr/bin/java | sed "s:bin/java::"`
	keytool -import -alias psmgw_guacd_cert -keystore $testpath/lib/security/cacerts -trustcacerts -file /opt/secrets/cert.crt -storepass "changeit" -noprompt >> html5gw.log 2>&1
}

restart_services(){
	print_info 'Restarting Tomact and Guacamole'
	systemctl restart tomcat >> html5gw.log
	service guacd restart >> html5gw.log 2>&1
	print_success 'Services Started Successfully'
}
main
