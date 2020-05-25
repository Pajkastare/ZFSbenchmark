#!/bin/bash

# About:		Version 0.8.2		GPLv3
# 2020-05-22
#
# This script is used to benchmark write I/O for various ZFS options.
# Read I/O is not tested (if it should, clear the ARC between each test).
# The benchmark root dataset ($BENCHMARKROOTDS) must exist before running this script.
# All options/parameters/properties except those explicitly listed in $TESTOBJECTLIST
# are by default inherited from this benchmark root dataset (for example "recordsize"),
# but this can be changed by some settings below.


# Prerequisites:
#
# The $POOLNAME must be configured with the encryption and compression features enabled.
# The $POOLNAME must be mounted at the Linux file system root, and $BENCHMARKROOTDS must exist.
# fio, bc, and a couple of standard command-line utilities must be installed.
# The user running this script must either be root, or have elevated ZFS rights.
# The system should obviously not be under high load during the test.
# The active recordsize/atime/etc parameters should not be wrong enough to skew the test results.


# Issues/caveats:
#
# A)	The time measurement is provided by the "time" command, not by fio. There is a ~2 second
#	discrepancy, probably because the time command includes time to pre-allocate files on disk,
#	while fio ignores this part. This means that fio reports a slightly higher throughtput than this script.
#	(The main log file also include the times and throughput as reported by fio, so if higher accuracy
#	is needed, this can be calculated at a later time. Note that this script calculates throughput
#	based on the used/logicalused ZFS properties, not file sizes.)
#	As long as these ~2 s is much smaller than $TESTRUNTIME, it doesn't really matter, the error will be small.
# B)	Only the first detected IOPS value is used for the summary table. For parallel write processes,
# 	this might get inaccurate. See the log file for complete data.
# C)	Since tail/head/etc are often used to extract data, it might not be robust for other systems with
# 	wildly faster or slower storage than the one used during development.


# Compatibility:
#
# Tested successfully on Ubuntu 20.04 LTS (Focal Fossa), with zfs-dkms, current as of 2020-05-14,
# with a single-disk vdev on a USB 3 mechanical hard drive. Other systems not tested.




# Primary settings:

TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")			# Appended to the test root dataset and used in logfiles
POOLNAME="your_poolname"				# No slashes at all
BENCHMARKROOTDS="$POOLNAME""/ZFSbenchmark"		# Preexisting dataset/filesystem root, >= 1 levels below $POOLNAME. No trailing slash
TESTROOTDS="$BENCHMARKROOTDS""/Test_$TIMESTAMP"		# New dataset/filesystem that will be created by this script
TESTRUNTIME=60						# Minimum runtime per individual test case in seconds (see fio parameters)

SPECIFY_ZFS_COMMON_OPTIONS=false  			# If true: Add the COMMON_ZFS_OPTIONS string to the "zfs create" command for TESTROOTDS
							# If false: Don't, and inherit all non-compression/non-encryption values from BENCHMARKROOTDS
#COMMON_ZFS_OPTIONS="-o recordsize=$1"			# Example: With no error-checking whatsoever: Set recordsize based on command-line parameter
#COMMON_ZFS_OPTIONS="-o recordsize=128k"		# Example: To override the inherited recordsize property
COMMON_ZFS_OPTIONS=""					# See "man zfs" for valid options. E.g.: "-o recordsize=1M -o sync=disabled"

APPEND_PARAMETER_2_TO_TESTROOTDS=false			# If true: Append "$2" to the name when defining the TESTROOTDS variable. If false: Don't.
if $APPEND_PARAMETER_2_TO_TESTROOTDS ; then TESTROOTDS="$TESTROOTDS""$2"; fi



# Dataset options format, note that tail/head are used to parse this so the number of characters must remain the same:
# COMPmodENCstd-bit-mod
#	COMPmod:      	COMP: Prefix;	mod: Either "lz4" or "off".
#	ENCstd-bit-mod:	ENV: Prefix;	std: Either "off" or "aes";	bit: 128|192|256; 	mod: ccm|gcm.
#						     If std = "off", the other parameters are ignored


# The interesting combinations:
#TESTOBJECTLIST=("COMPoffENCoff-000-xxx"  "COMPlz4ENCoff-000-xxx"  "COMPlz4ENCaes-256-ccm"  "COMPlz4ENCaes-256-gcm")

# All possible combinations (at least for OpenZFS on Linux 0.8.3):
TESTOBJECTLIST=("COMPoffENCoff-000-xxx"  "COMPlz4ENCoff-000-xxx"  \
		"COMPoffENCaes-128-ccm"  "COMPoffENCaes-192-ccm"  "COMPoffENCaes-256-ccm"  \
		"COMPoffENCaes-128-gcm"  "COMPoffENCaes-192-gcm"  "COMPoffENCaes-256-gcm"  \
		"COMPlz4ENCaes-128-ccm"  "COMPlz4ENCaes-192-ccm"  "COMPlz4ENCaes-256-ccm"  \
		"COMPlz4ENCaes-128-gcm"  "COMPlz4ENCaes-192-gcm"  "COMPlz4ENCaes-256-gcm")



# Derived settings/variables and other preparation:

LOGDIRECTORY="/tmp/ZFSBenchmark_""$TIMESTAMP"
LOGNAME="$LOGDIRECTORY""/Logfile.log"
ERRORNAME="$LOGDIRECTORY""/Errorlog.log"
TESTCASELIST="$LOGDIRECTORY""/Testcaselist"
PERTESTCASE="$LOGDIRECTORY""/CurrentTC_Log"
TIMEPERTESTCASE="$LOGDIRECTORY""/CurrentTC_Time"

SUBTEST_1_TIME=()
SUBTEST_2_TIME=()
SUBTEST_3_TIME=()
SUBTEST_1_USED=()
SUBTEST_2_USED=()
SUBTEST_3_USED=()
SUBTEST_1_LOGICALUSED=()
SUBTEST_2_LOGICALUSED=()
SUBTEST_3_LOGICALUSED=()
SUBTEST_1_IOPS=()
SUBTEST_2_IOPS=()
SUBTEST_3_IOPS=()
SUBTEST_1_LOGTHROUGHPUT=()
SUBTEST_2_LOGTHROUGHPUT=()
SUBTEST_3_LOGTHROUGHPUT=()
SUBTEST_1_THROUGHPUT=()
SUBTEST_2_THROUGHPUT=()
SUBTEST_3_THROUGHPUT=()
SUBTEST_1_ACC_USED=()
SUBTEST_2_ACC_USED=()
SUBTEST_3_ACC_USED=()
SUBTEST_1_ACC_LOGICALUSED=()
SUBTEST_2_ACC_LOGICALUSED=()
SUBTEST_3_ACC_LOGICALUSED=()

SCRIPT_PWD="$(pwd)"
DEBUGPRINTOUTS=false		# true or false
PRINTCPUINFO=false		# true or false


PreSubtestcaseStart() {
	rm $PERTESTCASE
	touch $PERTESTCASE
	mkdir Subtest$SUBTESTCASENUMBER
	cd Subtest$SUBTESTCASENUMBER
	if ! [ "$(pwd | tail -c 9 | head -c 8)" == "Subtest$SUBTESTCASENUMBER" ] ; then
		echo " [*] ERROR: Was expecting to be in a directory called \"Subtest$SUBTESTCASENUMBER\", but was in $(pwd)." | tee -a $LOGNAME $ERRORNAME
	fi
	sync
	zpool sync
}
# End [ of PreSubtestcaseStart () ]

UpdateCurrentTestcaseAnalysisValues() {
	ZFS_GET_PARAMETER="$TESTROOTDS/$TESTDS@Subtest$SUBTESTCASENUMBER"
	zfs snapshot $ZFS_GET_PARAMETER >> $LOGNAME 2>> $ERRORNAME
	RC2=$?
	ZFS_GET_PARAMETER="$TESTROOTDS""/""$TESTDS"

	LAST_TC_BEFORE_THIS_USED_RAW=$LAST_TC_USED_RAW
	LAST_TC_BEFORE_THIS_LOGICALUSED_RAW=$LAST_TC_LOGICALUSED_RAW
	LAST_TC_DURATION=$(cat $TIMEPERTESTCASE | grep real | tail -c+6)

	TC_LOGICALUSED_LENGTH=$(($(echo $ZFS_GET_PARAMETER | wc -c) + 13))
	TC_USED_LENGTH=$(($(echo $ZFS_GET_PARAMETER | wc -c) + 6))
	LAST_TC_LOGICALUSED_RAW=$(zfs get -H -p -t filesystem logicalused $ZFS_GET_PARAMETER | tail -c+$TC_LOGICALUSED_LENGTH | head -c-3)
	LAST_TC_USED_RAW=$(zfs get -H -p -t filesystem used $ZFS_GET_PARAMETER | tail -c+$TC_USED_LENGTH | head -c-3)

	LAST_TC_LOGICALUSED="($LAST_TC_LOGICALUSED_RAW-$LAST_TC_BEFORE_THIS_LOGICALUSED_RAW)/1024/1024"
	LAST_TC_LOGTHROUGHPUT=$(echo $LAST_TC_LOGICALUSED | bc)		# Temporary value, see below (no "MiB" suffix)
	LAST_TC_LOGICALUSED=$(echo $LAST_TC_LOGICALUSED | bc)MiB
	LAST_TC_USED="($LAST_TC_USED_RAW-$LAST_TC_BEFORE_THIS_USED_RAW)/1024/1024"
	LAST_TC_THROUGHPUT=$(echo $LAST_TC_USED | bc)			# Temporary value, see below (no "MiB" suffix)
	LAST_TC_USED=$(echo $LAST_TC_USED | bc)MiB

	LAST_TC_IOPS=$(cat $PERTESTCASE | grep -F "IOPS=" | head -n 1 | tail -c+15 | cut --delimiter=',' -f -1)

	LAST_TC_ACC_LOGICALUSED="($LAST_TC_LOGICALUSED_RAW)/1024/1024"
	LAST_TC_ACC_LOGICALUSED=$(echo $LAST_TC_ACC_LOGICALUSED | bc)MiB
	LAST_TC_ACC_USED="($LAST_TC_USED_RAW)/1024/1024"
	LAST_TC_ACC_USED=$(echo $LAST_TC_ACC_USED | bc)MiB

	# The throughput is calculated, not a result delivered by fio:
	TIME_MIN=$(echo $LAST_TC_DURATION | cut -f 1 -d m)
	TIME_SEC=$(echo $LAST_TC_DURATION | cut -f 2 -d m)
	TIME_SEC=$(echo $TIME_SEC | cut -f 1 -d s)
	LAST_TC_THROUGHPUT="scale=1; $LAST_TC_THROUGHPUT / ($TIME_MIN*60 + $TIME_SEC)"
	LAST_TC_THROUGHPUT=$(echo $LAST_TC_THROUGHPUT | bc)MiB/s
	LAST_TC_LOGTHROUGHPUT="scale=1; $LAST_TC_LOGTHROUGHPUT / ($TIME_MIN*60 + $TIME_SEC)"
	LAST_TC_LOGTHROUGHPUT=$(echo $LAST_TC_LOGTHROUGHPUT | bc)MiB/s

	echo -e "\n                [*] This took $LAST_TC_DURATION, IOPS/process was about $LAST_TC_IOPS (first occurrence), during which\n" \
		"                   $LAST_TC_LOGICALUSED of user data was stored (logicalused) at $LAST_TC_LOGTHROUGHPUT, but compression/metadata/ZFS magic\n" \
		"                   meant that $LAST_TC_USED was actually written to disk (used) at $LAST_TC_THROUGHPUT.\n\n" | tee -a $LOGNAME

	if [ "$(pwd | tail -c 9 | head -c 8)" == "Subtest$SUBTESTCASENUMBER" ] ; then
		cd ..
	else
		echo " [*] ERROR: Was expecting to be in a directory called \"Subtest$SUBTESTCASENUMBER\", but was in $(pwd)." | tee -a $LOGNAME $ERRORNAME
	fi
}
# End [ of UpdateCurrentTestcaseAnalysisVariables() ]


# All variables are set, start the actual test:

mkdir -p $LOGDIRECTORY
touch $LOGNAME
touch $ERRORNAME
touch $TESTCASELIST >> $LOGNAME 2>> $ERRORNAME
touch $PERTESTCASE >> $LOGNAME 2>> $ERRORNAME
touch $TIMEPERTESTCASE >> $LOGNAME 2>> $ERRORNAME

echo -e "***********************************************" | tee -a $LOGNAME $ERRORNAME $TESTCASELIST
echo -e "$0, started at $TIMESTAMP" | tee -a $LOGNAME $ERRORNAME $TESTCASELIST
echo -e "***********************************************" | tee -a $LOGNAME $ERRORNAME $TESTCASELIST
echo -e "\t[Any errors detected during script execution are listed below]" >> $ERRORNAME
echo -e "\nList of test cases (>= 1 measurement per TC, each of which is >= $TESTRUNTIME seconds):" | tee -a $LOGNAME $TESTCASELIST


# This loop is mostly for cosmetic reasons:
NO_TESTCASES=0
for TESTDS in ${TESTOBJECTLIST[*]}; do
	NO_TESTCASES=$(($NO_TESTCASES + 1))
	COMPRESSION=$(echo -n $TESTDS | head -c 7 | tail -c 3)
	ENCRYPTION=$(echo -n $TESTDS | tail -c 11)
	if [ "off" == $(echo $ENCRYPTION | head -c 3) ] ; then ENCRYPTION="off"; fi
	echo -e "Test case #""$NO_TESTCASES"":\t$TESTDS\t($COMPRESSION / $ENCRYPTION)" | tee -a $LOGNAME $TESTCASELIST
done

if $PRINTCPUINFO ; then
	echo -e "\n\nCPU info:\n\t" \
		"$(lscpu | grep -iF 'Model name' | sed s/'   '//g);" \
		"$(lscpu | grep -iF 'Flags' | sed s/'  '//g).\n\t" \
		"$(lscpu | grep -iF 'Cpu(s):' | sed s/'  '//g);" \
		"$(lscpu | grep -iF 'Thread(s)' | sed s/'   '//g);" \
		"$(lscpu | grep -iF 'max' | sed s/'  '//g)."

	echo -e "ZFS kernel module information:" | tee -a $LOGNAME $ERRORNAME $TESTCASELIST
	echo -e "\t$(modinfo zfs | grep -iF author)" | tee -a $LOGNAME $ERRORNAME $TESTCASELIST
	echo -e "\t$(modinfo zfs | grep -iF version | grep -ivF srcversion)" | tee -a $LOGNAME $ERRORNAME $TESTCASELIST
	echo -e "\t$(modinfo zfs | grep -iF vermagic)" | tee -a $LOGNAME $ERRORNAME $TESTCASELIST

	# TBD/TODO: It would be nice to automatically get CPU utilization per test case,
	# but it needs to be taken while the fio processes are running. So perhaps a
	# separate worker thread, which dumps utilization to $LOGDIRECTORY, from which
	# data is read and stored in a SUBTEST_* variable.
	# Perhaps for the next release, since a separate htop window and manual logging also works.
	#
	# But if automated, code like this could be used (this shows the current CPU idle figure):
	# top -b -n 1 | sed -n "s/^%Cpu.*ni, \([0-9.]*\) .*$/\1% Idle/p"
fi


echo -e -n "\n\nCreating the main test dataset" | tee -a $LOGNAME
if $SPECIFY_ZFS_COMMON_OPTIONS ; then
	zfs create $COMMON_ZFS_OPTIONS $TESTROOTDS >> $LOGNAME 2>> $ERRORNAME
	echo " (custom parameters to \"zfs create\": \"$COMMON_ZFS_OPTIONS\")" | tee -a $LOGNAME
else
	zfs create $TESTROOTDS >> $LOGNAME 2>> $ERRORNAME
	echo "" | tee -a $LOGNAME
fi
RC=$?
if (( $RC )) ; then echo "    [*] Error code $RC was returned from the last operation" | tee -a $LOGNAME $ERRORNAME; fi


echo -e "Creating an encryption key" | tee -a $LOGNAME
KEYBYTES=32; KEYBITS=$(echo "$KEYBYTES*8" | bc)
KEY_FULL_PATH="/$TESTROOTDS/hexkey_""$KEYBYTES""B_""$KEYBITS""b"
KEY_ZFS_FORMAT="file://""$KEY_FULL_PATH"
echo -n $(tr -dc a-f0-9 < /dev/random | dd bs=$(echo "2*$KEYBYTES" | bc) count=1 2> /dev/null) > $KEY_FULL_PATH 2>> $ERRORNAME
RC=$?
if (( $RC )) ; then echo "    [*] Error code $RC was returned from the last operation" | tee -a $LOGNAME $ERRORNAME; fi


echo -e "Creating all test case datasets" | tee -a $LOGNAME
CURRENT_TC=0
for TESTDS in ${TESTOBJECTLIST[*]}; do
	CURRENT_TC=$(($CURRENT_TC + 1))
	COMPRESSION=$(echo -n $TESTDS | head -c 7 | tail -c 3)
	ENCRYPTION=$(echo -n $TESTDS | tail -c 11)
	if [ "off" == $(echo $ENCRYPTION | head -c 3) ] ; then ENCRYPTION="off"; fi
	# echo -e "Test case #""$NO_TESTCASES"":\t$TESTDS\t($COMPRESSION / $ENCRYPTION)" | tee -a $LOGNAME $TESTCASELIST

	if [ "off" == "$ENCRYPTION" ] ; then
		zfs create -o compression=$COMPRESSION \
			"$TESTROOTDS""/""$TESTDS" >> $LOGNAME 2>> $ERRORNAME
	else
		zfs create -o compression=$COMPRESSION \
			-o encryption=$ENCRYPTION \
			-o keyformat=hex \
			-o keylocation=$KEY_ZFS_FORMAT \
			"$TESTROOTDS""/""$TESTDS" >> $LOGNAME 2>> $ERRORNAME
	fi
	RC=$?
	if (( $RC )) ; then echo "    [*] Error code $RC was returned, in iteration $CURRENT_TC / $NO_TESTCASES" | tee -a $LOGNAME $ERRORNAME; fi
done


# Now ready to start the actual performance test. Change to the test directory
cd "/""$TESTROOTDS" >> $LOGNAME 2>> $ERRORNAME
RC=$?
if (( $RC )) ; then echo "    [*] Error code $RC was returned from the last operation" | tee -a $LOGNAME $ERRORNAME; fi


CURRENT_TC=0
for TESTDS in ${TESTOBJECTLIST[*]}; do
	CURRENT_TC=$(($CURRENT_TC + 1))
	COMPRESSION=$(echo -n $TESTDS | head -c 7 | tail -c 3)
	ENCRYPTION=$(echo -n $TESTDS | tail -c 11)
	if [ "off" == $(echo $ENCRYPTION | head -c 3) ] ; then ENCRYPTION="off"; fi
	echo -e "\n\n***********************\n [*] Starting test case #$CURRENT_TC/$NO_TESTCASES:\t$TESTDS\t($COMPRESSION / $ENCRYPTION)\n" | tee -a $LOGNAME

	# Sanity-check: Are we were we think we are?
	if ! [ "$(pwd)" == "/""$TESTROOTDS" ] ; then
		echo -e "\t[*] ERROR: Expected to be in (/""$TESTROOTDS""), was in (""$(pwd)"")" | tee -a $LOGNAME $ERRORNAME
	fi
	# Failsafe: Go the the correct, intended directory even if we weren't in it from the start:
	cd "/""$TESTROOTDS" >> $LOGNAME 2>> $ERRORNAME

	cd $TESTDS >> $LOGNAME 2>> $ERRORNAME
	# Start the test in the current directory
	#echo -e "\t[*] DEBUG: Now in directory $(pwd)"
	##################### START OF ACTUAL DISK I/O TEST #####################

	        ZFS_GET_PARAMETER="$TESTROOTDS""/""$TESTDS""@BeforeTest"
        	zfs snapshot $ZFS_GET_PARAMETER >> $LOGNAME 2>> $ERRORNAME
		LAST_TC_USED_RAW=0				# Needed for the UpdateCurrentTestcaseAnalysisValues() function
		LAST_TC_LOGICALUSED_RAW=0


		# Based on https://arstechnica.com/gadgets/2020/02/how-fast-are-your-disks-find-out-the-open-source-way-with-fio/

		# Get the log output to this file, which is overwritten for each fio execution.
		# Extract meaningful parts, discard the rest.
		touch $PERTESTCASE
		touch $TIMEPERTESTCASE	# This file is used to get the output from "time" (redirected stderr)


		SUBTESTCASENUMBER="1"
		PreSubtestcaseStart
		echo -e "\n        [*] Starting subtest $SUBTESTCASENUMBER: Single 4 KiB random write process" | tee -a $LOGNAME
		{ time fio --name=random-write --ioengine=posixaio --rw=randwrite --bs=4k --size=4g --numjobs=1 \
			--iodepth=1 --runtime=$TESTRUNTIME --time_based --end_fsync=1 ; \
#			} 2> $TIMEPERTESTCASE | tee -a $PERTESTCASE
			} 2> $TIMEPERTESTCASE > $PERTESTCASE
		RC=$?		# RC is ignored except for the last subtest in each test case.
		echo -e "\n                [*] The most relevant parts of the fio output:" | tee -a $LOGNAME
		cat $PERTESTCASE | grep -i write | grep -vF "random-write: (" | tee -a $LOGNAME
		cat $PERTESTCASE | grep -i iops | grep -vF "write:" | tee -a $LOGNAME
		UpdateCurrentTestcaseAnalysisValues
		SUBTEST_1_TIME+=($LAST_TC_DURATION)
		SUBTEST_1_LOGICALUSED+=($LAST_TC_LOGICALUSED)
		SUBTEST_1_USED+=($LAST_TC_USED)
		SUBTEST_1_IOPS+=($LAST_TC_IOPS)
		SUBTEST_1_LOGTHROUGHPUT+=($LAST_TC_LOGTHROUGHPUT)
		SUBTEST_1_THROUGHPUT+=($LAST_TC_THROUGHPUT)
		SUBTEST_1_ACC_LOGICALUSED+=($LAST_TC_ACC_LOGICALUSED)
		SUBTEST_1_ACC_USED+=($LAST_TC_ACC_USED)


		SUBTESTCASENUMBER="2"
		PreSubtestcaseStart
		echo -e "\n        [*] Starting subtest $SUBTESTCASENUMBER: 16 parallel 64 KiB random write processes" | tee -a $LOGNAME
		{ time fio --name=random-write --ioengine=posixaio --rw=randwrite --bs=64k --size=256m --numjobs=16 \
			--iodepth=16 --runtime=$TESTRUNTIME --time_based --end_fsync=1 ; \
#			} 2> $TIMEPERTESTCASE | tee -a $PERTESTCASE
			} 2> $TIMEPERTESTCASE > $PERTESTCASE
		RC=$?		# RC is ignored except for the last subtest in each test case.
		echo -e "\n                [*] The most relevant parts of the fio output (first part via uniq -c, prefixed by counts):" | tee -a $LOGNAME
		cat $PERTESTCASE | grep -i write | grep -vF "random-write: (" | uniq -c | tee -a $LOGNAME
		cat $PERTESTCASE | grep -i iops | grep -vF "write:" | tee -a $LOGNAME
		UpdateCurrentTestcaseAnalysisValues
		SUBTEST_2_TIME+=($LAST_TC_DURATION)
		SUBTEST_2_LOGICALUSED+=($LAST_TC_LOGICALUSED)
		SUBTEST_2_USED+=($LAST_TC_USED)
		SUBTEST_2_IOPS+=($LAST_TC_IOPS)
		SUBTEST_2_LOGTHROUGHPUT+=($LAST_TC_LOGTHROUGHPUT)
		SUBTEST_2_THROUGHPUT+=($LAST_TC_THROUGHPUT)
		SUBTEST_2_ACC_LOGICALUSED+=($LAST_TC_ACC_LOGICALUSED)
		SUBTEST_2_ACC_USED+=($LAST_TC_ACC_USED)


		SUBTESTCASENUMBER="3"
		PreSubtestcaseStart
		echo -e "\n        [*] Starting subtest $SUBTESTCASENUMBER: Single 1 MiB random write process" | tee -a $LOGNAME
		{ time fio --name=random-write --ioengine=posixaio --rw=randwrite --bs=1m --size=16g --numjobs=1 \
			--iodepth=1 --runtime=$TESTRUNTIME --time_based --end_fsync=1 ; \
#			} 2> $TIMEPERTESTCASE | tee -a $PERTESTCASE
			} 2> $TIMEPERTESTCASE > $PERTESTCASE
		RC=$?		# RC is ignored except for the last subtest in each test case.
		echo -e "\n                [*] The most relevant parts of the fio output:" | tee -a $LOGNAME
		cat $PERTESTCASE | grep -i write | grep -vF "random-write: (" | tee -a $LOGNAME
		cat $PERTESTCASE | grep -i iops | grep -vF "write:" | tee -a $LOGNAME
		UpdateCurrentTestcaseAnalysisValues
		SUBTEST_3_TIME+=($LAST_TC_DURATION)
		SUBTEST_3_LOGICALUSED+=($LAST_TC_LOGICALUSED)
		SUBTEST_3_USED+=($LAST_TC_USED)
		SUBTEST_3_IOPS+=($LAST_TC_IOPS)
		SUBTEST_3_LOGTHROUGHPUT+=($LAST_TC_LOGTHROUGHPUT)
		SUBTEST_3_THROUGHPUT+=($LAST_TC_THROUGHPUT)
		SUBTEST_3_ACC_LOGICALUSED+=($LAST_TC_ACC_LOGICALUSED)
		SUBTEST_3_ACC_USED+=($LAST_TC_ACC_USED)

	##################### END OF ACTUAL DISK I/O TEST #####################
	if (( $RC )) ; then echo "    [*] Error code $RC was returned, for TC#$CURRENT_TC/$NO_TESTCASES" | tee -a $LOGNAME $ERRORNAME; fi

	# This test is finished, move back to the test root
	cd .. >> $LOGNAME 2>> $ERRORNAME
done


if $DEBUGPRINTOUTS ; then
	echo -e "\n\n\tDEBUG PRINTOUTS: Start"
	echo -e "\t\tTESTROOTDS: $TESTROOTDS"
	echo -e "\t\tLOGDIRECTORY: $LOGDIRECTORY"
	echo -e "\t\tSCRIPT_PWD: $SCRIPT_PWD"
	echo -e "\t\tTESTOBJECTLIST: ${TESTOBJECTLIST[@]}"
	echo -e "\t\tSUBTEST_1_TIME: ${SUBTEST_1_TIME[@]}"
	echo -e "\t\tSUBTEST_2_TIME: ${SUBTEST_2_TIME[@]}"
	echo -e "\t\tSUBTEST_3_TIME: ${SUBTEST_3_TIME[@]}"
	echo -e "\t\tSUBTEST_1_LOGICALUSED: ${SUBTEST_1_LOGICALUSED[@]}"
	echo -e "\t\tSUBTEST_2_LOGICALUSED: ${SUBTEST_2_LOGICALUSED[@]}"
	echo -e "\t\tSUBTEST_3_LOGICALUSED: ${SUBTEST_3_LOGICALUSED[@]}"
	echo -e "\t\tSUBTEST_1_USED: ${SUBTEST_1_USED[@]}"
	echo -e "\t\tSUBTEST_2_USED: ${SUBTEST_2_USED[@]}"
	echo -e "\t\tSUBTEST_3_USED: ${SUBTEST_3_USED[@]}"
	echo -e "\t\tSUBTEST_1_IOPS: ${SUBTEST_1_IOPS[@]}"
	echo -e "\t\tSUBTEST_2_IOPS: ${SUBTEST_2_IOPS[@]}"
	echo -e "\t\tSUBTEST_3_IOPS: ${SUBTEST_3_IOPS[@]}"
	echo -e "\t\tSUBTEST_1_LOGTHROUGHPUT: ${SUBTEST_1_LOGTHROUGHPUT[@]}"
	echo -e "\t\tSUBTEST_2_LOGTHROUGHPUT: ${SUBTEST_2_LOGTHROUGHPUT[@]}"
	echo -e "\t\tSUBTEST_3_LOGTHROUGHPUT: ${SUBTEST_3_LOGTHROUGHPUT[@]}"
	echo -e "\t\tSUBTEST_1_THROUGHPUT: ${SUBTEST_1_THROUGHPUT[@]}"
	echo -e "\t\tSUBTEST_2_THROUGHPUT: ${SUBTEST_2_THROUGHPUT[@]}"
	echo -e "\t\tSUBTEST_3_THROUGHPUT: ${SUBTEST_3_THROUGHPUT[@]}"
	echo -e "\t\tSUBTEST_1_ACC_LOGICALUSED: ${SUBTEST_1_ACC_LOGICALUSED[@]}"
	echo -e "\t\tSUBTEST_2_ACC_LOGICALUSED: ${SUBTEST_2_ACC_LOGICALUSED[@]}"
	echo -e "\t\tSUBTEST_3_ACC_LOGICALUSED: ${SUBTEST_3_ACC_LOGICALUSED[@]}"
	echo -e "\t\tSUBTEST_1_ACC_USED: ${SUBTEST_1_ACC_USED[@]}"
	echo -e "\t\tSUBTEST_2_ACC_USED: ${SUBTEST_2_ACC_USED[@]}"
	echo -e "\t\tSUBTEST_3_ACC_USED: ${SUBTEST_3_ACC_USED[@]}"
	echo -e "\t\tString pad check: SUBTEST_1_TIME[0]=\"__${SUBTEST_1_TIME[0]}__\""
	echo -e "\t\tString pad check: SUBTEST_1_LOGICALUSED[0]=\"__${SUBTEST_1_LOGICALUSED[0]}__\""
	echo -e "\t\tString pad check: SUBTEST_1_USED[0]=\"__${SUBTEST_1_USED[0]}__\""
	echo -e "\t\tString pad check: SUBTEST_1_IOPS[0]=\"__${SUBTEST_1_IOPS[0]}__\""
	echo -e "\t\tString pad check: SUBTEST_1_THROUGHPUT[0]=\"__${SUBTEST_1_THROUGHPUT[0]}__\""
	echo -e "\tDEBUG PRINTOUTS: End\n"
fi


echo -e "Destroying all test case datasets, but not their parent dataset" | tee -a $LOGNAME
CURRENT_TC=0
for TESTDS in ${TESTOBJECTLIST[*]}; do
	CURRENT_TC=$(($CURRENT_TC + 1))

	zfs destroy -fvr "$TESTROOTDS/$TESTDS" >> $LOGNAME 2>> $ERRORNAME
	RC=$?
	if (( $RC )) ; then echo "    [*] Error code $RC was returned, in iteration $CURRENT_TC / $NO_TESTCASES" | tee -a $LOGNAME $ERRORNAME; fi
done



echo -e "\n\nResults summary:\n****************" | tee -a $LOGNAME $TESTCASELIST
echo -e "  Test case\tTest case name          Compr/Encr settings \t Subtest 1\t Subtest 2\t Subtest 3" | tee -a $LOGNAME $TESTCASELIST
echo -e "  ---------\t--------------          ------------------- \t ---------\t ---------\t ---------" | tee -a $LOGNAME $TESTCASELIST
CURRENT_TC=0
for TESTDS in ${TESTOBJECTLIST[*]}; do
	SUBTESTINDEX=$CURRENT_TC
	CURRENT_TC=$(($CURRENT_TC + 1))
	COMPRESSION=$(echo -n $TESTDS | head -c 7 | tail -c 3)
	ENCRYPTION=$(echo -n $TESTDS | tail -c 11)
	if [ "off" == $(echo $ENCRYPTION | head -c 3) ] ; then ENCRYPTION="off"; fi
	if [ "off" == "$ENCRYPTION" ] ; then
		ENCRYPTION="off        "
	fi

	# Test result: Time to complete each subtest
	echo -e "  TC #$CURRENT_TC/$NO_TESTCASES:\t$TESTDS   $COMPRESSION / $ENCRYPTION\t" \
                "${SUBTEST_1_TIME[$SUBTESTINDEX]}\t" \
                "${SUBTEST_2_TIME[$SUBTESTINDEX]}\t" \
                "${SUBTEST_3_TIME[$SUBTESTINDEX]}" | tee -a $LOGNAME $TESTCASELIST

	# Test result: Logical (logicalused) data size as written per subtest
	echo -e "                                          -Logical data size: \t" \
		" ${SUBTEST_1_LOGICALUSED[$SUBTESTINDEX]}  \t" \
		" ${SUBTEST_2_LOGICALUSED[$SUBTESTINDEX]}  \t" \
		" ${SUBTEST_3_LOGICALUSED[$SUBTESTINDEX]}" | tee -a $LOGNAME $TESTCASELIST

	# Test result: Actual (used) data size as written per subtest
	echo -e "                                          -Actual data size:  \t" \
		" ${SUBTEST_1_USED[$SUBTESTINDEX]}  \t" \
		" ${SUBTEST_2_USED[$SUBTESTINDEX]}  \t" \
		" ${SUBTEST_3_USED[$SUBTESTINDEX]}" | tee -a $LOGNAME $TESTCASELIST

	# Test result: Accumulated, total logical (logicalused) data, for each test case (i.e., subtest 1 + subtest 2 + subtest 3)
	echo -e "                                          -Acc. logical data: \t" \
		" ${SUBTEST_1_ACC_LOGICALUSED[$SUBTESTINDEX]}  \t" \
		" ${SUBTEST_2_ACC_LOGICALUSED[$SUBTESTINDEX]}  \t" \
		" ${SUBTEST_3_ACC_LOGICALUSED[$SUBTESTINDEX]}" | tee -a $LOGNAME $TESTCASELIST

	# Test result: Accumulated, total actual (used) data, for each test case (i.e., subtest 1 + subtest 2 + subtest 3)
	echo -e "                                          -Acc. actual data:  \t" \
		" ${SUBTEST_1_ACC_USED[$SUBTESTINDEX]}  \t" \
		" ${SUBTEST_2_ACC_USED[$SUBTESTINDEX]}  \t" \
		" ${SUBTEST_3_ACC_USED[$SUBTESTINDEX]}" | tee -a $LOGNAME $TESTCASELIST

	# Test result: Input/output operations per second, per process (not an exact value)
	# (Cosmetic preparation: Might need to lengthen the IOPS strings, for vertical alignment.)
                                                                     IOPSPAD=${SUBTEST_1_IOPS[$SUBTESTINDEX]}
	if (( ${#IOPSPAD} < 7 )) ; then IOPSPAD="      "; else IOPSPAD=""; fi; IOPSPAD_1=$IOPSPAD
                                                                     IOPSPAD=${SUBTEST_2_IOPS[$SUBTESTINDEX]}
	if (( ${#IOPSPAD} < 7 )) ; then IOPSPAD="      "; else IOPSPAD=""; fi; IOPSPAD_2=$IOPSPAD
                                                                     IOPSPAD=${SUBTEST_3_IOPS[$SUBTESTINDEX]}
	if (( ${#IOPSPAD} < 7 )) ; then IOPSPAD="      "; else IOPSPAD=""; fi; IOPSPAD_3=$IOPSPAD
	echo -e "                                          -IOPS/process:      \t" \
		" ${SUBTEST_1_IOPS[$SUBTESTINDEX]}$IOPSPAD_1  \t" \
		" ${SUBTEST_2_IOPS[$SUBTESTINDEX]}$IOPSPAD_2  \t" \
		" ${SUBTEST_3_IOPS[$SUBTESTINDEX]}$IOPSPAD_3" | tee -a $LOGNAME $TESTCASELIST

	# Test result: Logical (logicalused) data written per time unit, i.e., throughtput
	echo -e "                                          -Logical throughput:\t" \
		" ${SUBTEST_1_LOGTHROUGHPUT[$SUBTESTINDEX]}  \t" \
		" ${SUBTEST_2_LOGTHROUGHPUT[$SUBTESTINDEX]}  \t" \
		" ${SUBTEST_3_LOGTHROUGHPUT[$SUBTESTINDEX]}" | tee -a $LOGNAME $TESTCASELIST

	# Test result: Actual (used) data written per time unit, i.e., throughtput
	echo -e "                                          -Actual throughput: \t" \
		" ${SUBTEST_1_THROUGHPUT[$SUBTESTINDEX]}  \t" \
		" ${SUBTEST_2_THROUGHPUT[$SUBTESTINDEX]}  \t" \
		" ${SUBTEST_3_THROUGHPUT[$SUBTESTINDEX]}" | tee -a $LOGNAME $TESTCASELIST

	RC=$?
	if (( $RC )) ; then echo "    [*] Error code $RC was returned, in iteration $CURRENT_TC / $NO_TESTCASES" | tee -a $LOGNAME $ERRORNAME; fi
done


ENDTIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")
echo -e "\nThis test sequence, which started at $TIMESTAMP, ended at $ENDTIMESTAMP." | tee -a $LOGNAME $ERRORNAME $TESTCASELIST
echo -e "Logfiles are stored here: /""$TESTROOTDS" | tee -a $LOGNAME $TESTCASELIST
echo -e "***********************************************" | tee -a $LOGNAME $ERRORNAME $TESTCASELIST


# Silent final cleanup: Move all log files to the main test directory, before returning to the original directory:
# Failsafe: Go the the correct, intended directory even if we weren't in it from the start (which we should've been):
cd "/""$TESTROOTDS" >> $LOGNAME 2>> $ERRORNAME
mv "$LOGDIRECTORY"/* .

cd "${SCRIPT_PWD}"

# Done.
