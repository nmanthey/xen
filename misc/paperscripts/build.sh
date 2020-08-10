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
# Script to build binaries required for analysis of Xen with CBMC
#
# Note: this script should be executed from within the given Docker container,
#       so that all relevant dependencies are present.

get_and_build_cbmc ()
{
	[ -d cbmc ] || git clone https://github.com/diffblue/cbmc.git

	pushd cbmc

	# go to our changes
	git reset --hard 2ebbb24
	git pull ../git-bundles/cbmc-2ebbb24..xen-paper-shared.bundle refs/heads/xen-paper-shared


	# actually build CBMC
	[ -d minisat-2.2.1 ] || make -C src minisat2-download
	make LINKFLAGS=-static -C src cbmc.dir goto-cc.dir goto-diff.dir goto-instrument.dir -j $(nproc)
	
	popd
}


get_xen ()
{
	[ -d xen ] || git clone git://xenbits.xen.org/xen.git

	pushd xen

	# go to our changes
	git reset --hard RELEASE-4.8.0
	git pull ../git-bundles/xen-RELEASE-4.8.0..cbmc-paper-nice.bundle refs/heads/cbmc-paper-nice

	popd
}

get_one_line_scan ()
{
	[ -d one-line-scan ] || git clone https://github.com/awslabs/one-line-scan.git
}

build_goto_xen ()
{
	# prepare environment
	export PATH=$PATH:$(readlink -e cbmc)/src/cbmc
	export PATH=$PATH:$(readlink -e cbmc)/src/goto-instrument
	export PATH=$PATH:$(readlink -e cbmc)/src/goto-cc
	export PATH=$PATH:$(readlink -e cbmc)/src/goto-diff
	export PATH=$PATH:$(pwd)/one-line-scan/configuration

	pushd xen
	# This call is expected to fail, as the final linking steps will fail.
	#
	# One of the warnings is: execvp ls_parse.py failed: No such file or directory
	# This warning is expected, and results in not fully linking Xen - at the benefit of a better run time
	time one-line-scan --no-analysis --trunc-existing --extra-cflags -Wno-error -o CPROVER -j 3 -- make xen -j $(nproc) -k || true
	./compile_stub_syscall.sh
	cd xen/arch/x86/
	./generic-compile-xsa200.sh harness.o
	cd ../../common
	./compile_get_cpu_info.sh
	./compile_multicallstub.sh
	cd ../
	mv xen-syms xen.binary
	goto-cc xen.binary common/get_cpu_info.o  -o xen-syms.binary
	popd
}

# Trace steps, fail on error
set -ex

get_xen
get_one_line_scan
get_and_build_cbmc
build_goto_xen
