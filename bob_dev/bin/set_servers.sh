#!/bin/bash

################################################################################
# 
#
#Description:
#  This script sets lists of servers based on the environment you are running
#  in.  It is intended to be called from other scripts.
#
#Change History:
#  Date        Author         Description
#  ----------  -------------- ------------------------------------
#  2014-08-04  qarnold        Added Milan->Sandbox connectivity (temp)
#  2013-10-01  qarnold        Added bat, pulse, and cassandra servers
#  2012-10-23  adillow        Created
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

   $0

Description:

   This script sets lists of servers based on the environment you are running
   in.  It is intended to be called from other scripts.

Environment Variables:

   \$target_env:
      This is required and is used to specify what environment we are deploying
      to.
   \$Group:
      For Teradata deployments, this is the group being deployed
	  
   \$mode:
      For Teradata deployments mode is either adm or etl depending on the
	  components being installed

   \$servers:
      This is set by this script.  The content is a associative array of space
      delimited list of servers for the environment specified.

EOF
}

################################################################################
# Initialize
################################################################################

if [ -z $target_env ]
then
   print_usage
   echo -e "\n\n[\e[01;31mERROR\e[00m] Please specify a value for target_env variable."
   exit 1
fi


################################################################################
# Server Configuration
################################################################################

# Set servers
case "$target_env" in
   "dev")
      declare -A servers=(
         ["das"]="dasdeploy@chelomsedw002"
         ["bat"]="NOT_IMPLEMENTED"
         ["hadoop_etl"]="edwbuild@cheledwhdc001"
         ["hive_udf"]="edwbuild@cheledwhdc001"
         ["hue"]="edwbuild@cheledwhdc001"
         ["informatica"]="infadm@cheletledw001"
         ["staging"]="edwbuild@cheledwhdc901"
         ["td_ba"]="d_booking_${mode}@devetl"
         ["td_eww"]="d_eww_scratch_${mode}@devetl"
      )
   ;;
   "test")
      declare -A servers=(
         ["das"]="dasdeploy@chelomsedw001"
         ["bat"]="NOT_IMPLEMENTED"
         ["hadoop_etl"]="edwbuild@chelhdpdev004"
         ["hive_udf"]="edwbuild@chelhdpdev004"
         ["hue"]="edwbuild@chelhdpdev004"
         ["informatica"]="infadm@cheletledw011"
         ["staging"]="edwbuild@cheledwhdc901"
         ["td_ba"]="t_booking_${mode}@testetl"
         ["td_eww"]="t_eww_scratch_${mode}@devetl"
      )
   ;;
   "maui")
      declare -A servers=(
         ["das"]="dasdeploy@cheljvcedw051 dasdeploy@cheljvcedw052"
         ["bat"]="batdeploy@cheljvcedw061"
         ["hadoop_etl"]="edwbuild@cheledwhdc201"
         ["hive_udf"]="edwbuild@cheledwhdc201"
         ["hue"]="edwbuild@cheledwhdc201"
         ["informatica"]="infadm@cheletledw021"
         ["staging"]="edwbuild@cheledwhdc901"
         ["td_ba"]="i_booking_${mode}@testetl"
         ["td_eww"]="i_eww_scratch_${mode}@devetl"
      )
   ;;
   "milan")
      declare -A servers=(
         ["das"]="dasdeploy@cheljvcedw201 dasdeploy@cheljvcedw202"
         ["bat"]="batdeploy@cheljvcedw211"
         ["hadoop_etl"]="NOT_IMPLEMENTED"
         ["hive_udf"]="NOT_IMPLEMENTED"
         ["hue"]="NOT_IMPLEMENTED"
         ["informatica"]="infadm@cheletledw201"
         ["staging"]="edwbuild@cheledwhdc901"
         ["td_ba"]="s_booking_${mode}@testetl"
         ["td_eww"]="s_eww_scratch_${mode}@devetl"
      )
   ;;
   "ppe")
      declare -A servers=(
         ["informatica"]="infadm@phsdetledw005"
      )
   ;;
   "prod")
      declare -A servers=(
         ["das"]="dasdeploy@phexjvcedw001 dasdeploy@phexjvcedw002 dasdeploy@phepjvcedw001 dasdeploy@phepjvcedw002 dasdeploy@phepjvcedw003 dasdeploy@phepjvcedw004 dasdeploy@phepjvcedw005 dasdeploy@phepjvcedw006 dasdeploy@phepjvcedw007 dasdeploy@phepjvcedw008"
         ["bat"]="batdeploy@chsxwebbat001"
         ["hadoop_etl"]="edwbuild@chsxedwhdc001"
         ["hive_udf"]="edwbuild@chsxedwhdc001 edwbuild@chsxedwhdc002 edwbuild@chsxedwhdu001 edwbuild@chsxedwhdu002 edwbuild@chsxedwhdu003 edwbuild@chsxedwhdu004 edwbuild@chsxedwhdu005 edwbuild@chsxedwhdu006 edwbuild@chsxedwhdu007 edwbuild@chsxedwhdu009 edwbuild@chsxedwhdu010 edwbuild@chsxedwhdu011 edwbuild@chsxedwhdu012 edwbuild@chsxedwhdu013 edwbuild@chsxedwhdu014"
         ["hue"]="edwbuild@chsxedwhdd007 edwbuild@chsxedwhdd008 edwbuild@chsxedwhdd009"
         ["informatica"]="infadm@che-etledw05"
         ["td_ba"]="p_booking_${mode}@testetl"
         ["td_eww"]="p_eww_scratch_${mode}@devetl"
      )
   ;;
   *)
      echo -e "\n[\e[01;31mERROR\e[00m] No logical servers are configured for the $target_env environment."
      exit 1
   ;;
esac

