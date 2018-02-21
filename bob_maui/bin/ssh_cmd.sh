#!/bin/bash

################################################################################
#Copyright (C) 2013 Expedia, Inc. All rights reserved.
#
#Description:
#  This script is used to run commands on remote server(s).  If a logical
#  server is specified that has multiple servers associated with it, it will
#  run the commands in parallel, and consolidate the results.
#
#Change History:
#  Date        Author         Description
#  ----------  -------------- ------------------------------------
#  2013-10-14  qarnold        Added -t stdout option (for serial requests only)
#  2013-08-06  adillow        Added command line flags as alternatives to variables.
#                             Added -n option for log numbering.
#                             Added -s option for serial processing.
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

   $0 [-s] [-t] [-e <environment>] [-l <log directory>] [-i <identity file>]
      [-j <jira>] [-n <log number>] <logical server> <cmd>

Description:

   This script is used to run commands on remote server(s).  If a logical
   server is specified that has multiple servers associated with it, it will
   run the commands in parallel, and consolidate the results.

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

		 Not valid with -t option

   -n    Specify a number to use to include in the logfile name.  If not
         specified, the process id will be used.

   -s    Process commands on servers sequentially.  If not specified commands
         will be processed in parallel.

   -t    Same as -s except use stdout for logging
   
Parameters:

   logical server:
      logical name of server to deploy to

   cmd:
      Command to run on remote host

Examples:

   1)  Show an example of a command completing successfully.

      $0 das "exit 0"

   2)  Show an example of a command completing with failure.

      $0 das "exit 1"

EOF
}

################################################################################
# Initialize
################################################################################

# Initialize variables
serial_processing=false
opt_stdout=false
log_number=$$
jira_log_label=

if [[ ! -z $JIRA_NUM ]]
then
   jira_log_label=_${JIRA_NUM}
fi

# Parse flags
while getopts ":stj:n:e:l:i:" opt; do
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
      s)
		 serial_processing=true
         ;;
      t)
         serial_processing=true
		 opt_stdout=true
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

# Check for logging conflict
if [[ $opt_stdout == true ]] && [[ ! -z "$logdir" ]]
then
   print_usage
   echo -e "\n\n[\e[01;31mERROR\e[00m] -l option invalid with -S."
   exit 1
fi

# Verify we have 2 arguments
if [ $# -ne 2 ]
then
   print_usage
   echo -e "\n\n[\e[01;31mERROR\e[00m] The wrong number of arguments were specified: $#."
   exit 1
fi

# Get command line parameters
logical_server=$1
remote_command=$2

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
ssh_opts="${ssh_opts} -ln"

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

if [[ $serial_processing == true ]]
then
   if [[ ! $opt_stdout == true ]]
   then
       logfile=${local_log_directory}/${target_env}${jira_log_label}_${log_number}_remote_shell.log
       echo "logfile=$logfile"
   fi
   

   for server in ${servers["$logical_server"]}
   do
      echo "Run on $server:  $remote_command"
      if  [[ $opt_stdout != true ]]
	  then
	      echo $logfile | tee $logfile
      fi
	  
      echo "--------------------------------------------------------------------------------" | tee $logfile
      echo ssh $ssh_opts $server "${remote_command}" | tee $logfile
      echo "--------------------------------------------------------------------------------" | tee $logfile
      echo | tee $logfile
      oldifs=$IFS
	  IFS=$'\n'
	  output=$(eval ssh $ssh_opts $server "'"${remote_command}"'" )
	  rc=$?
      for line in $output:
	  do
	      echo $line | tee $logfile	  
      done
	  
      if [[ $rc == 0 ]]; then {
         echo -e "   [\e[01;32mSUCCESS\e[00m]"
      } else {
         echo -e "   [\e[01;31mFAILURE\e[00m]  Stopped deployment.  If deploying to multiple servers, some may have not been updated.  Please examine log for details."
         exit 1
      }
      fi
   done
else
   # Kick off remote commands
   for server in ${servers["$logical_server"]}
   do
      logfile=${local_log_directory}/${target_env}${jira_log_label}_${log_number}_remote_shell_${server}.log
      echo "Run on $server:  $remote_command"
      echo "logfile=$logfile"
      echo >> $logfile
      echo "--------------------------------------------------------------------------------" >> $logfile
      echo ssh $ssh_opts $server "${remote_command}" >> $logfile
      echo "--------------------------------------------------------------------------------" >> $logfile
      echo >> $logfile
      ssh $ssh_opts $server "${remote_command}" >> $logfile 2>&1 &
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
fi

