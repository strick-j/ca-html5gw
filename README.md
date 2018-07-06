# ca-html5gw
Script to automate the setup of CyberArk's HTML5 Web Gateway.

# Installation
Intended for installation on an updated minimal CentOS 7 Server. General install instructions:
1. Clone or download the git repository
2. Copy the necessary Cyber Ark PSMGW rpm file into the local git repository
3. Run the setup script as a user with admin rights (e.g. "sudo ./html5gw-setup.sh")

# Notes
Passwords for the Apache Keystore are hard coded in the script and set to CyberArk1 for demonstration purposes. Change these if you would like to set them to something else.
DNS / Hostnames are hard coded in the script and in the guac_ssl.cnf file, change these to match you environment.
