#!/bin/bash

################################################################################
#Copyright (C) 2013 Expedia, Inc. All rights reserved.
#
#Description:
#  This script is used to copy files to remote server(s).  If a logical server
#  is specified that has multiple servers associated with it, it will run the
#  commands in parallel, and consolidate the results.
#
#Change History:
#  Date        Author         Description
#  ----------  -------------- ------------------------------------
#  2013-08-06  adillow        Added command line flags as alternatives to variables.
#                             Added -n option for log numbering.
#  2012-10-19  adillow        Created
################################################################################


################################################################################
# Define functions
################################################################################

function print_usage {
  if [ -n "$1" ]
  then
      echo ERROR: $1
      echo 
  fi 

  cat <<EOF

Usage:

   $0 [-e <environment>] [-l <log directory>] [-i <identity file>]
      [-j <jira>] [-n <log number>] <logical server> <local dir> <file>
      [<remote dir>]

Description:

   This script is used to copy files to remote server(s).  If a logical server
   is specified that has multiple servers associated with it, it will run the
   commands in parallel, and consolidate the results.

Notes:

   If this script is being run from windows, make sure cygwin is installed and
   in the path.  Execute by prefixing script name with "bash".

Options:

   -e    The name of the environment we are deploying to, this falls back to
         the \$envName variable if not specified.  If neither is used, the
         script will fail.

   -i    Specifies the full path to the identity file being used for trusted
         ssh authentication ( for more details see ssh man page ).  If this is
         not specified, the \$IDENTITY variable will be used.  If that is also
         not specified, the default private key will be used.

   -j    The number of the jira that is being deployed.  If not specified, it
         will use the \$JIRA_NUM variable.  If nothing is specified, this will
         be excluded from the logfile name.

   -l    The directory to write logs to.  If not specified, the \$logdir
         variable will be used.  If neither are specified, logs will be written
         to the local directory.

   -n    Specify a number to use to include in the logfile name.  If not
         specified, the process id will be used.

Parameters:

   logical server:
      logical name of server to deploy to

   local dir:
      local directory of file to copy

   file:
      File to copy

Optional Parameters:

   remote dir:
      Specify what directory to deploy to on the remote box.

Examples:

   1)  Show an example of a command completing successfully.

      $0 das test.txt

EOF
}

################################################################################
# Initialize
################################################################################

# Initialize variables
log_number=$$
jira_log_label=

if [[ ! -z $JIRA_NUM ]]
then
   jira_log_label=_${JIRA_NUM}
fi

# Parse flags
while getopts ":j:n:e:l:i:" opt; do
   case "$opt" in
      e)
         envName=$OPTARG
         ;;
      i)
         IDENTITY=$OPTARG
         ;;
      j)
         jira_log_label=_$OPTARG
         ;;
      l)
         logdir=$OPTARG
         ;;
      n)
         log_number=$OPTARG
         ;;
      \?)
         print_usage
         echo -e "\n\n[\e[01;31mERROR\e[00m] Invalid option:  -$OPTARG"
         exit 1
         ;;
      :)
         print_usage
         echo -e "\n\n[\e[01;31mERROR\e[00m] Option requires an argument:  -$OPTARG"
         exit 1
         ;;
   esac
done

shift $((OPTIND-1))

# Verify we have 2 arguments
if [[ $# -lt 3 || $# -gt 4 ]]
then
   print_usage
   echo -e "\n\n[\e[01;31mERROR\e[00m] The wrong number of arguments were specified."
   exit 1
fi

# Get command line parameters
logical_server=$1
local_directory=`echo $2 | sed "s/[\\\/]$//"`
file_to_copy=$3

if [ $# -eq 4 ]
then
   remote_dir=`echo $4 | sed "s/[\\\/]$//"`
else
   remote_dir=.
fi

# If local_directory is a dos path, use cygpath
if [[ $local_directory = *:* ]]
then
   local_directory=`cygpath -u $local_directory`
fi

# Initialize variables
unset pidlist
declare -A pid_file
failures=0

# Set local log directory
if [[ -z $logdir ]]
then
   local_log_directory=.
else
   if [[ $logdir =~ ^[\\\/]$ ]]
   then
      local_log_directory=$logdir
   else
      local_log_directory=`echo $logdir | sed "s/[\\\/]$//"`
   fi
fi

# Make log directory if it doesn't exist.
if [ ! -d "$local_log_directory" ]
then
   mkdir -p $local_log_directory
fi

# Set target evironment
target_env=$envName

if [ -z $target_env ]
then
   print_usage
   echo -e "\n\n[\e[01;31mERROR\e[00m] Please specify a value for -e or the \$envName variable."
   exit 1
fi

# Set variables to lowercase
logical_server=$( echo "$logical_server" | sed 's/\(.*\)/\L\1/' )
target_env=$( echo "$target_env" | sed 's/\(.*\)/\L\1/' )

# All allowable values for $env
all_envs=("dev" "test" "maui" "milan" "ppe" "prod")

(for e in ${all_envs[@]}; do [[ "$e" == "$target_env" ]] && exit 0; done) || {
   print_usage
   echo -e "\n\n[\e[01;31mERROR\e[00m] The environment specified is not valid:  $target_env"
   exit 1
}

# Set ssh options
ssh_opts=""

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

################################################################################
# Server Configuration
################################################################################

. set_servers.sh

# Make sure we have a valid configuration
if [[ ! ${servers["$logical_server"]} ]]; then {
   echo -e "\n[\e[01;31mERROR\e[00m] The logical server, $logical_server, is invalid for the $target_env environment."
   exit 1
} fi

# Gracefully exit with a warning if the environment is not implemented
if [[ ${servers["$logical_server"]} == "NOT_IMPLEMENTED" ]]; then {
   echo -e "\n[\e[01;33mWARNING\e[00m] The logical server, $logical_server, is not implemented for the $target_env environment."
   exit 0
} fi
 
################################################################################
# Server Configuration
################################################################################

echo

# Kick off remote commands
echo "Copy file:  $file_to_copy"
echo "     from:  $local_directory"
echo "       to:  $remote_dir"

# Check if file exists first.
if [ ! -e ${local_directory}/${file_to_copy} ]
then
   echo -e "\n[\e[01;31mERROR\e[00m] The file specified does not exist:"
   echo
   echo "   ${local_directory}/${file_to_copy}"
   echo
   exit 1
fi

for server in ${servers["$logical_server"]}
do
   logfile=${local_log_directory}/${target_env}${jira_log_label}_${log_number}_copy_${file_to_copy}_to_${server}.log
   echo "   to server:  $server"
   echo "logfile=$logfile"

   echo >> $logfile
   echo "--------------------------------------------------------------------------------" >> $logfile
   echo scp $ssh_opts ${local_directory}/${file_to_copy} $server:${remote_dir}/$file_to_copy >> $logfile
   echo "--------------------------------------------------------------------------------" >> $logfile
   echo >> $logfile
   scp $ssh_opts ${local_directory}/${file_to_copy} $server:${remote_dir}/$file_to_copy >> $logfile 2>&1 &
   pid=$!
   pidlist="$pidlist $pid"
   pid_file[$pid]=$server
done

echo

# Collect execution results
for pid in $pidlist
do
   echo "Waiting for server ${pid_file["$pid"]}"
   wait $pid && {
      echo -e "   [\e[01;32mSUCCESS\e[00m]"
   } || {
      echo -e "   [\e[01;31mFAILURE\e[00m]"
      let failures+=1
   }
done

if [ $failures -gt 0 ]
then
   echo -e "\n\n[\e[01;31mERROR\e[00m] There were $failures failures.  Please examine logs for details"
   exit 1
else
   echo -e "\n\nRemote command completed successfully."
fi

