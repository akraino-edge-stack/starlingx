#!/bin/bash

##############################################################################
# Copyright (c) 2019 Wind River Systems
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Apache License, Version 2.0
# which accompanies this distribution, and is available at
# http://www.apache.org/licenses/LICENSE-2.0
##############################################################################

###################################
### Build Step - Test Execution ###
###################################

# Set env variables for current shell session
export PROPERTY_PATH=/sandbox/jenkins_build_props/${BUILD_TAG}
REPO_DIR=testcases
if [ ${GIT_BRANCH} != "develop" ]; then
	REPO_DIR=testcases_prev
fi
echo "REPO_DIR=${REPO_DIR}" >> ${PROPERTY_PATH}

export PYTHONPATH=:/home/svc-cgcsauto/wassp-repos.new/${REPO_DIR}/cgcs/CGCSAuto
export WASSP_HOME=/home/svc-cgcsauto/wassp-repos.new
export PYTHON3=/usr/local/bin/python3.4

export LAB=WP_1-2
export TEST_PATH=z_containers/test_kube_edgex_services.py
export TEST_DOMAIN=akraino
export MARKERS=platform_sanity
export GIT_BRANCH=develop
export TEST_TYPE=functional
export LOGS_DIR=/sandbox

cd ${WASSP_HOME}/${REPO_DIR}/cgcs/CGCSAuto
    
# Get the TIS build id either from parameter or connect to LAB to find out.
if [[ ( -z "${TIS_BUILD_ID}" ) || ( -z "${SYS_TYPE}" ) ]]; then
    lab_inf=$($PYTHON3 -c "from utils import lab_info;print(' '.join(lab_info.get_lab_info(labname='${LAB}')))" | tail -n1)
    lab_array=()
    for x in $lab_inf; do lab_array+=("$x"); done
    TIS_BUILD_ID=${lab_array[0]}
    SYS_TYPE=${lab_array[1]}
fi

export MONGO_TAGS=${TEST_DOMAIN}_${TIS_BUILD_ID}_${LAB}

REPORT_SOURCE=local
HEALTH_REPORT=true
if [ ${MONGO_DB} == true ]; then
	REPORT_SOURCE=mongo
    HEALTH_REPORT=false
fi
   

# Write build env variables to property file
echo "PROPERTY_PATH=${PROPERTY_PATH}" >> ${PROPERTY_PATH}
echo "PYTHONPATH=${PYTHONPATH}" >> ${PROPERTY_PATH}
echo "WASSP_HOME=${WASSP_HOME}"  >> ${PROPERTY_PATH}
echo "TIS_BUILD=${TIS_BUILD_ID}" >> ${PROPERTY_PATH}
echo "MONGO_TAGS=${MONGO_TAGS}" >> ${PROPERTY_PATH}
echo "TIS_SYS_TYPE=${SYS_TYPE}" >> ${PROPERTY_PATH}
echo "REPORT_SOURCE=${REPORT_SOURCE}" >> ${PROPERTY_PATH}
echo "HEALTH_REPORT=${HEALTH_REPORT}" >> ${PROPERTY_PATH}



if [ ${COLLECT_ONLY} == true ]; then
	COLLECT=--collectonly
fi

if [ ${ALWAYS_COLLECT} == true ]; then
	ALWAYS_COLLECT_LOGS=--alwayscollect
else 
	if [ ${COLLECT_ALL} == true ]; then
		COLLECT_LOGS=--collectall
	fi
fi

if [[ ${TELNET_LOGS} == true ]] && [[ ${TEST_PATH} != *"test_dor"* ]]; then
	TELNET_LOG=--telnet-log
fi 


if [ ${KEYSTONE_DEBUG} == true ]; then
	KS_DEBUG=--keystone-debug
fi

if [ ${COLLECT_KPI} == true ]; then
	KPI=--kpi
fi

if [ ${REMOTE_CLI} == true ]; then
    USE_REMOTE_CLI=--remote_cli
    # disable kpi tests if remote_cli is enabled
    KPI=''
fi

if [ ${SKIP_TEARDOWN} == true ]; then
	NO_TEARDOWN=--noteardown
fi

if [ ! -z "${KEYWORDS}" ]; then
    KEYWORDS=(-k "${KEYWORDS}")
fi

if [ ! -z "${MARKERS}" ]; then
    MARKERS=(-m "${MARKERS}")
fi

if [ ${CHANGE_ADMIN_PW} == true ]; then
	CHANGE_ADMIN=--change_admin
fi

if [ ! -z "${REPEAT}" ]; then
    REPEAT="--repeat=${REPEAT}"
fi

if [ ! -z "${STRESS}" ]; then
    STRESS="--stress=${STRESS}"
fi

if [ ! -z "${TENANT}" ]; then
    TENANT="--tenant=${TENANT}"
fi

if [ ! -z "${SUBCLOUD}" ]; then
    SUBCLOUD=" --subcloud=${SUBCLOUD}"
fi



# Delay
sleep ${DELAY}

# Do not exit upon test execution failure
set +e

git checkout ${GIT_BRANCH}
# Delete vms and volumes on the system when required
#  && ${GIT_BRANCH} == 'develop'
if [[ ${DELETE_VMS} == true && ${COLLECT_ONLY} == false ]]; then
	$PYTHON3 -m pytest --lab ${LAB} --resultlog="/tmp/" ${WASSP_HOME}/${REPO_DIR}/cgcs/CGCSAuto/testcases/system_config/test_system_cleanup.py::test_delete_vms_and_vols
fi

# Write test session log dir value to property file
SESSION_DIR=$(/usr/local/bin/python3.4 utils/jenkins_utils/create_log_dir.py -d /sandbox/ ${LAB})
echo "SESSION_DIR=${SESSION_DIR}" >> ${PROPERTY_PATH}

git checkout ${GIT_BRANCH}
# Test execution starts
/usr/local/bin/python3.4 -m pytest --lab=${LAB} --sessiondir=${SESSION_DIR} "${MARKERS[@]}" "${KEYWORDS[@]}" ${COLLECT} ${KS_DEBUG} \
${ALWAYS_COLLECT_LOGS}${COLLECT_LOGS} ${REPEAT}${STRESS}${NO_TEARDOWN} ${CHANGE_ADMIN} \
${KPI}${USE_REMOTE_CLI} ${TELNET_LOG} ${TENANT}${SUBCLOUD} ${WASSP_HOME}/${REPO_DIR}/cgcs/CGCSAuto/testcases/${TEST_TYPE}/${TEST_PATH}

# Parse test execution result and save it to property file
RES="$?"
echo "EXECUTION_RES=${RES}" >> ${PROPERTY_PATH}

# Checkout to develop branch if not already on it
if [ ! ${GIT_BRANCH} == develop ]; then
    git checkout develop
fi

if [ ! -z "${FILE_PATH}" ]; then
    LOG_DIR=${FILE_PATH}
    LOG_DIR=${LOG_DIR%/test_results.log}
fi

curl -v --netrc-file /home/svc-cgcsauto/.netrc --upload-file ${FILE_PATH} https://nexus.akraino.org/content/sites/logs/windriver-stx-ex/job/starlingx-edgex-master-config/${BUILD_NUMBER}/

echo "Test execution completed"
