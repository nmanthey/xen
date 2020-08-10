#!/usr/bin/env bash
#
#  Copyright 2020 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#  
#  Licensed under the Apache License, Version 2.0 (the "License").
#  You may not use this file except in compliance with the License.
#  A copy of the License is located at
#  
#      http://www.apache.org/licenses/LICENSE-2.0
#  
#  or in the "license" file accompanying this file. This file is distributed 
#  on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either 
#  express or implied. See the License for the specific language governing 
#  permissions and limitations under the License.
#
# Script to demonstrate tooling
#
# Note: This script requires access to docker. The runtime depends on your
#       machine, and can be around an hour.


# Build all tools in Docker container
/usr/bin/time -v bash -x docker/run_in_container.sh docker/Dockerfile \
        ./build.sh

# Produce an example trace for XSA 213
/usr/bin/time -v bash -x docker/run_in_container.sh docker/Dockerfile \
        ./execute-single-run.sh 213 2 1 1 1 2 paper-testrun
