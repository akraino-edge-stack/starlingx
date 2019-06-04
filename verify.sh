#!/bin/bash

##############################################################################
# Copyright (c) 2019 Wind River Systems
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Apache License, Version 2.0
# which accompanies this distribution, and is available at
# http://www.apache.org/licenses/LICENSE-2.0
##############################################################################

# Set env variables for current shell session
export PROPERTY_PATH=/sandbox/jenkins_build_props/${BUILD_TAG}
REPO_DIR=testcases
echo "REPO_DIR=${REPO_DIR}" >> ${PROPERTY_PATH}

export PYTHONPATH=:/home/svc-cgcsauto/wassp-repos.new/${REPO_DIR}/cgcs/CGCSAuto
export WASSP_HOME=/home/svc-cgcsauto/wassp-repos.new
export PYTHON3=/usr/local/bin/python3.4

export LAB=WCP_14
export TEST_DOMAIN=akraino
export TEST_TYPE=functional
export TEST_PATH=z_containers/test_kube_edgex_services.py
export GIT_BRANCH=develop

cd ${WASSP_HOME}/${REPO_DIR}/cgcs/CGCSAuto

# Get the StarlingX build id either from parameter or connect to LAB to find out.
if [[ ( -z "${TIS_BUILD_ID}" ) || ( -z "${SYS_TYPE}" ) ]]; then
    lab_inf=$($PYTHON3 -c "from utils import lab_info;print(' '.join(lab_info.get_lab_info(labname='${LAB}')))" | tail -n1)
    lab_array=()
    for x in $lab_inf; do lab_array+=("$x"); done
    TIS_BUILD_ID=${lab_array[0]}
    SYS_TYPE=${lab_array[1]}
fi

# Write build env variables to property file
echo "PROPERTY_PATH=${PROPERTY_PATH}" >> ${PROPERTY_PATH}
echo "PYTHONPATH=${PYTHONPATH}" >> ${PROPERTY_PATH}
echo "WASSP_HOME=${WASSP_HOME}"  >> ${PROPERTY_PATH}
echo "TIS_BUILD=${TIS_BUILD_ID}" >> ${PROPERTY_PATH}
echo "TIS_SYS_TYPE=${SYS_TYPE}" >> ${PROPERTY_PATH}

# Do not exit upon test execution failure
set +e

git checkout ${GIT_BRANCH}

# Write test session log dir value to property file
SESSION_DIR=$(/usr/local/bin/python3.4 utils/jenkins_utils/create_log_dir.py -d /sandbox/ ${LAB})
echo "SESSION_DIR=${SESSION_DIR}" >> ${PROPERTY_PATH}

export LOGS_DIR=/sandbox
FILE_PATH=${SESSION_DIR}/test_results.log

# Test execution starts
/usr/local/bin/python3.4 -m pytest --lab=${LAB} --sessiondir=${SESSION_DIR} ${WASSP_HOME}/${REPO_DIR}/cgcs/CGCSAuto/testcases/${TEST_TYPE}/${TEST_PATH}

# Parse test execution result and save it to property file
RES="$?"
echo "EXECUTION_RES=${RES}" >> ${PROPERTY_PATH}

if [ ! -z "${FILE_PATH}" ]; then
    LOG_DIR=${FILE_PATH}
    LOG_DIR=${LOG_DIR%/test_results.log}
fi

curl -v --netrc-file /home/svc-cgcsauto/.netrc --upload-file ${FILE_PATH} https://nexus.akraino.org/content/sites/logs/windriver-stx-ex/job/starlingx-edgex-master-config/${BUILD_NUMBER}/

echo "Test execution completed"
