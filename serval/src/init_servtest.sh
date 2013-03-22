#!/bin/bash
# Simple script to initialize a node for the test experiments on the serval architecture


# Check if the script has root permissions
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi


CMD_OUTP=    # Store the output of the progams

IPeth0=      # IP to be set for eth0 interface
SAL_FW=0     # Sal_Forward
SERVD_R=0    # servd to be run as a service router
SRIP=        # Set servd's Service Router IP
RES_MODE=    # Service Resolution Mode


# Function to print the usage message
usage() {
cat << EOF

Usage: $0 options

This script initializes a node for the test experiments on the serval architecture.
Should be run with superuser privileges.

OPTIONS:
  -h               Show this help message
  -i  <address>    Set the IP for the eth0 interface
  -f               Enable SAL_FORWARD
  -m               Service_Resolution_Mode 0=All, 1=Demux only, 2=forward only, 3=Anycast
  -s               Run servd controller as a service router
  -r  ROUTER_IP    Set servd's service router IP
EOF
}


# Parse the arguments
while getopts “hi:fsm:r:” OPTION; do
  case $OPTION in
  h)
    usage
    exit 0
    ;;
  i)
    IPeth0=$OPTARG
    ;;
  f)
    SAL_FW=1
    ;;
  m)
    RES_MODE=$OPTARG
    ;;
  s)
    SERVD_R=1
    ;;
  r)
    SRIP=$OPTARG
    ;;
  ?)
    usage
    exit 2
    ;;
  esac
done


# If IPeth0 is set, then try to ifconfig eth0
if [[ ! -z $IPeth0 ]]; then
  echo "Setting the IP of eth0 interface to" $IPeth0
  CMD_OUTP=`ifconfig eth0 $IPeth0/24`
  if [ $? -ne 0 ]; then
    echo "Could not set IP to eth0 interface"
    usage
    exit 3
  fi
  echo $CMD_OUTP
fi


# Load the serval kernel module
echo "Load the serval kernel module"
CMD_OUTP=`insmod ./stack/serval.ko`
echo $CMD_OUTP


# If -f was given as argument, enable the SAL_FORWARD
if [[ $SAL_FW == 1 ]]; then
  echo "Enabling SAL_FORWARD"
  echo 1 > /proc/sys/net/serval/sal_forward
fi


# If -f was given as argument, enable the SAL_FORWARD
if [[ ! -z $RES_MODE ]]; then
  echo "Setting Service_Resolution_Mode to" $RES_MODE
  echo $RES_MODE > /proc/sys/net/serval/service_resolution_mode
  echo
fi


# Start the service controller
echo "Starting the service controller"
if [[ $SERVD_R == 1 ]]; then
  echo "servd running in service router mode"
  CMD_OUTP=`./servd/servd -r`
  echo $CMD_OUTP
elif [[ ! -z $SRIP ]]; then
  echo "Given service router ip is" $SRIP
  CMD_OUTP=`./servd/servd -rip $SRIP`
  echo $CMD_OUTP
else
  ./servd/servd
fi
