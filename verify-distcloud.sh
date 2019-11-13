#!/bin/bash
#
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

echo "Running script..."
DISTCLOUD_TEST_DIR="${DISTCLOUD_TEST_DIR-/home/jenkins/distributed_cloud/stx-test-suite/}"
DISTCLOUD_VIRTUALENV="${DISCLOUD_VIRTUALENV-/home/jenkins/distributed_cloud/dist_cloud/}"

echo "DISTCLOUD_TEST_DIR=${DISTCLOUD_TEST_DIR}"
echo "DISTCLOUD_VIRTUALENV=${DISTCLOUD_VIRTUALENV}"

# Check if needed folder exists in worker node.
# - The distcloud tests
if [ ! -d "$DISTCLOUD_TEST_DIR" ]; then
    echo -e "ERROR: Folder '$DISTCLOUD_TEST_DIR' does not exist\nExiting..."
    exit 0
fi
# - The virtualenv directory
if [ ! -d "$DISTCLOUD_VIRTUALENV" ]; then
    echo -e "ERROR: Folder '$DISTCLOUD_VIRTUALENV' does not exist\nExiting..."
    exit 0
fi

# Copy yaml file to folder
cp conf_files/stx-distcloud.yml $DISTCLOUD_TEST_DIR/Config/stx-duplex.yml

pushd $DISTCLOUD_TEST_DIR
# Source the environment
source $DISTCLOUD_VIRTUALENV/bin/activate
# Run setup for duplex
echo -e "INFO: Running Setup stage in the system controller\n"
# python runner.py --run-suite Setup --configuration 2 --environment baremetal
# Needs time to stabilize
# sleep 300
echo -e "INFO: Running Provision stage in the system controller\n"
# python runner.py --run-suite Provision
# Needs time to stabilize
# sleep 300
popd

pytest -v -s test_distcloud.py

