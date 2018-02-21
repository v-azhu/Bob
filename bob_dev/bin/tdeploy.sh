#!/bin/bash

################################################################################
#Copyright (C) 2015 Expedia, Inc. All rights reserved.
#
#Description:
#  Teradata deployment wrapper
#
#Change History:
#  Date        Author         Description
#  ----------  -------------- ------------------------------------
#  2015-03-11  Awen zhu       Teradata deployment wrapper
################################################################################

function print_usage {
  if [ -n "$1" ]
  then
      echo ERROR: $1
  fi 

  cat <<EOF

Usage:

   $0 <envName> <repository> <Group> <DBUser> <Module-build/component> <Manifest>
   example from raid.txt:
     bash tdeploy.sh ba LZ_DB2_EDW_ADB TDDB2_LZ_DB2_EDW-75/db LZ_DB2_EDW
     Note: make sure %envName% %repository% are set if you run it without Build processor or Bob.
Description:

   This script for teradata deployment. it accepting 4 arguments.

EOF
}

if [ "$#" -ne 4 ]
then
   print_usage
   exit 1
fi

# Set target evironment
Group=$1
DBUser=$2
Module_Folder=${3}
arrModule_Folder=(${3//// })
Module=${arrModule_Folder[0]}
Manifest=$4

# All allowable values for $envName
all_envs=("dev" "test" "maui" "milan" "ppe" "prod")

(for e in ${all_envs[@]}; do [[ "$e" == "$envName" ]] && exit 0; done) || {
   print_usage
   echo -e "\n\n[\e[01;31mERROR\e[00m] The environment specified is not valid:  $envName"
   exit 1
}

if [[ ${Manifest} =~ ^[A-Z]+-[0-9]+$ ]] 
then
   Manifest="${Module}/manifests/hotfix/${Manifest}.json"
else
   Manifest="${Module}/manifests/${Manifest}_canonical.json"
fi

echo "envName=${envName}"
echo "repository=${repository}"
echo "Group=${Group}"
echo "DBUser=${DBUser}"
echo "Module_Folder=${Module_Folder}"
echo "Module=${Module}"
echo "Manifest=${Manifest}"

for mode in adm etl
do
   # Set servers
   export target_env=$envName
   export mode=adm
   . set_servers.sh

   td_conn=${servers[td_${Group}]}
   td_env=${td_conn:0:1}

   echo "td_conn=${td_conn}"
   echo "td_env=${td_env}"

   if [ ! -z $IDENTITY ]; then
      IDENTITY=`cygpath -u $IDENTITY`
      if [ -f "$IDENTITY" ]; then
         ssh_opts="-i $IDENTITY"
      else
         echo -e "\n[\e[01;31mERROR\e[00m] The private key file specified does not exist:\n   $IDENTITY"
      fi
   fi

   ssh_opts="${ssh_opts} -o PasswordAuthentication=no"
   ssh_opts="${ssh_opts} -o StrictHostKeyChecking=no"
   ssh_opts="${ssh_opts} -ln"

   if [ ${mode} == "adm" ]
   then
      # ignore ssh option here, we can add that later if needed.
      echo deploying Module ${Module}
      ssh ${ssh_opts} -T ${servers[td_${Group}]} << EOF
wget ${repository}/teradata/${Group^^}/${Module}.tar.gz -O - | tar -xzvf /dev/stdin || exit 2
export TD_USERNAME="${td_env^^}_${DBUser}"
td_deploy ${Module_Folder} ${Manifest} || exit 4
echo rm -rf ${Module}* 
EOF
   else
      echo copying tpt and btq scripts
      ssh ${ssh_opts} -T ${servers[td${GROUP}]} << EOF
cp ${Module}/lib/tpt/* ~/lib/tpt || exit 6
cp ${Module}/lib/btq/* ~/lib/btq || exit 6
EOF
   fi

   rc=$?
   if [ $rc -gt 0 ]
   then 
     
     break
   fi
done
   
if [ $rc -gt 0 ]
   then
      echo -e "\n\n[\e[01;31mERROR\e[00m] There were $failures failures.  Please examine logs for details"
      exit 1
   else
      echo -e "\n\nRemote command completed successfully."
fi
