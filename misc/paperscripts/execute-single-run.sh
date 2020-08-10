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
# Script to run a single XSA analysis on given Xen artifacts
#
# Usage:
#   ./execute-single-run.sh XSA_num depth unwind preserve_direct_paths full_slice FP_removal [NAME]
#
# Example:
#   ./execute-single-run.sh 200 0 0 0 1 2 XSA200-test-run
#
# Parameter values to consider:
#   XSA_num in 200 212 213 227 238 238b
#   depth in {0..2} results in --aggressive-slice --aggressive-slice-call-depth ${depth}
#   unwind in {0..2} results in --unwind ${unwinding}
#   preserve_direct_paths in {0..1} results in  --aggressive-slice-preserve-all-direct-paths
#   full_slice in {0..1} results in a separate iteration of slicing with --full-slice
#   FP_removal in {0..2} results in (remove-function-pointers,--moderate-function-pointer-removal,--extreme-function-pointer-removal)


# Make sure we are called from the right place
check_environment ()
{
	local STATUS=0
	# Check for CPROVER tools being avaiable
	for tool in cbmc goto-cc goto-instrument
	do
		if ! command -v "$tool" &> /dev/null
		then
			echo "Cannot find tool $tool, abort"
			STATUS=1
		fi
	done

	# Check for Xen being compiled with goto-cc correctly
	for goto_file in xen/xen/xen-syms.binary xen/xen/arch/x86/harness.o xen/xen/common/multicallstub.o xen/stub_syscall.o
	do
		if ! cbmc/src/goto-instrument/goto-instrument --count-eloc xen/xen/xen.binary &> /dev/null
		then
			echo "Cannot find goto-gcc compiled file: $goto_file, abort"
			STATUS=1
		fi
	done

	if [ "$STATUS" -ne 0 ]
	then
		echo "Abort due to detected problems"
		exit 1
	fi
}

# Setup variables so that we find all the tools we need
setup_work_environment ()
{
	# make cbmc, goto-cc and goto-instrument avaiable
	export PATH=$PATH:$(readlink -e cbmc/src/cbmc)
	export PATH=$PATH:$(readlink -e cbmc/src/goto-cc)
	export PATH=$PATH:$(readlink -e cbmc/src/goto-instrument)
}

error ()
{
        echo "Error: $*"
        exit 1
}

set -e 

XSA_num=$1
depth=$2
unwinding=$3
preserve_direct_paths=$4
full_slice=$5
FP_removal=$6
NAME=$7
if [ -z "$XSA_num" ]; then
    error "No XSA number given"
fi

if [ -z "${depth}" ]; then
    depth=0
fi

if [ -z "${unwinding}" ]; then
    unwinding=1
fi

if [ -z "${preserve_direct_paths}" ]; then
    preserve_direct_paths=0
fi

if [ -z "${full_slice}" ]; then
    full_slice=0
fi

if [ -z "$NAME" ]; then
  NAME="run"
fi  

# Make sure we are called from the right place, after building all artifacts
setup_work_environment
check_environment

SLICE_options="--aggressive-slice --aggressive-slice-call-depth ${depth} "

CBMC_options=" --stop-on-fail --object-bits 16 --trace --trace-show-function-calls --trace-show-code --trace-hex --no-sat-preprocessor --unwind ${unwinding} "

if [ ${preserve_direct_paths} -ne 0 ]; then
 SLICE_options="$SLICE_options --aggressive-slice-preserve-all-direct-paths "
fi

# Create directory for this run
BASE="$NAME"-xsa"$XSA_num"
DIR="$BASE"-${depth}${unwinding}${preserve_direct_paths}
mkdir -p "$DIR"

echo "Place relevant files into directory: $DIR"

cp xen/xen/xen-syms.binary xen/xen/arch/x86/harness.o xen/xen/common/multicallstub.o xen/stub_syscall.o "$DIR"

cd "$DIR" || exit
echo "Start analysis: $(date +%s)" |& tee "$BASE.sliced.trace"

# Select XSA
case "$1" in
200) echo "XSA 200"
    goto-cc xen-syms.binary harness.o  -o "$BASE.tmp.binary"
    goto-cc --function main "$BASE.tmp.binary" -o "$BASE.binary"
    PROPERTY="x86_emulate.assertion.1"
    ;;

212) echo "XSA 212"
    goto-cc --function do_memory_op xen-syms.binary -o "$BASE.binary"
    PROPERTY="memory_exchange.assertion.1"
    ;;

213) echo "XSA 213"
	goto-cc xen-syms.binary multicallstub.o -o "$BASE.tmp.binary"
    goto-cc --function do_multicall_stub "$BASE.tmp.binary" -o "$BASE.binary"
    PROPERTY="mod_l4_entry.assertion.1"
    ;;

227) echo "XSA 227"
    goto-cc --function my_granttable_init xen-syms.binary -o "$BASE.binary"
    PROPERTY="create_grant_pte_mapping.assertion.1"
    ;;

238) echo "XSA 238"
    goto-cc xen-syms.binary stub_syscall.o -o "$BASE.tmp.binary"
    goto-cc --function start_function "$BASE.tmp.binary" -o "$BASE.binary"
    PROPERTY="hvm_unmap_io_range_from_ioreq_server.assertion.1"
    ;;

238b) echo "XSA 238"
    goto-cc xen-syms.binary stub_syscall.o -o "$BASE.tmp.binary"
    goto-cc --function start_function "$BASE.tmp.binary" -o "$BASE.binary"
    PROPERTY="hvm_map_io_range_to_ioreq_server.assertion.1"
    ;;

 *) error "XSA number not found"
    exit 1
    ;;
esac

# Select function pointer removal
case "$FP_removal" in
0) echo "default FP removal " |& tee -a "$BASE.sliced.log"
	goto-instrument --remove-function-pointers "$BASE.binary" tmp.binary
	mv tmp.binary "$BASE.binary"
	;;
1) echo "moderate FP removal " |& tee -a "$BASE.sliced.log"
	goto-instrument --moderate-function-pointer-removal "$BASE.binary" tmp.binary
	mv tmp.binary "$BASE.binary"
	;;
2) echo "extreme FP removal " |& tee -a "$BASE.sliced.log"
	goto-instrument --extreme-function-pointer-removal "$BASE.binary" tmp.binary
	mv tmp.binary "$BASE.binary"
	;;

*) echo "default FP removal " |& tee -a "$BASE.sliced.log"
	goto-instrument --remove-function-pointers "$BASE.binary" tmp.binary
	mv tmp.binary "$BASE.binary"
	;;
esac

echo "Slicing: $SLICE_options"
( time goto-instrument --timestamp monotonic $SLICE_options --property $PROPERTY $BASE.binary $BASE.sliced.binary ) |& tee  "$BASE.sliced.log"

if [ ${full_slice} -ne 0 ]; then
	echo "Running full slicer" |& tee -a "$BASE.sliced.log"
	( time goto-instrument --timestamp monotonic --full-slice --property $PROPERTY $BASE.sliced.binary $BASE.sliced2.binary ) |& tee -a "$BASE.sliced.log"
	cp "$BASE.sliced2.binary" "$BASE.sliced.binary"
fi


echo "Done slicing $(date +%s)" |& tee -a "$BASE.sliced.trace"

goto-instrument --count-eloc "$BASE.sliced.binary" |tee -a "$BASE.sliced.trace"
goto-instrument --count-eloc "$BASE.binary" |tee -a "$BASE.sliced.trace"

echo "Havoc undefined function bodies"
goto-instrument --generate-function-body '.*' --generate-function-body-options 'havoc,params:.*' $BASE.sliced.binary $BASE.havoc.binary
goto-instrument --count-eloc "$BASE.havoc.binary" |tee -a "$BASE.sliced.trace"
cp $BASE.havoc.binary $BASE.sliced.binary

aws s3 cp "$BASE.sliced.trace" "$BUCKETNAME/$NAME$BASE.depth${depth}-unwind${unwinding}-dp${preserve_direct_paths}-fs${full_slice}-fp$FP_removal.trace"

echo "Running analysis: $CBMC_options"
( time cbmc --timestamp monotonic $CBMC_options --property $PROPERTY $BASE.sliced.binary ) |& tee -a "$BASE.sliced.trace"
CBMC_STATUS=${PIPESTATUS[0]}

echo "goto-instrument options: $SLICE_options"  |tee -a "$BASE.sliced.trace"
echo "cbmc options: $CBMC_options" |tee -a "$BASE.sliced.trace"
echo "End time $(date +%s)" |& tee -a "$BASE.sliced.trace" 
