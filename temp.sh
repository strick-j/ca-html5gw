#!/bin/bash

firewalldservice=firewalld

yum list $firewalldiservice > /dev/null
if [[ $? -eq 0 ]]; then
  echo "$firewalldservice is installed"
else
  echo "$firewalldservice is not installed, skipping firewall configuration"
fi

echo "Verifying firewall is running"
if [[ $(ps -ef | grep -v grep | grep $firewalldservice | wc -l) > 0 ]]; then
  echo "$firewalldservice is running"
else
  echo "$firewalldservice is not running, skipping firewall configuration"
fi
