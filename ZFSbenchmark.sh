#!/bin/bash

# About:		Version 0.9.0		GPLv3
# 2024-12-10
#
# This script is used to benchmark disk write performance for various ZFS options.
# Read performance is not tested (if it should, clear the ARC between each test).
# The benchmark root dataset ($BENCHMARKROOTDS) must exist before running this script.
# All options/parameters/properties except those explicitly listed in $TESTOBJECTLIST
# are by default inherited from this benchmark root dataset (for example "recordsize"),
# but this can be changed by some settings below.


# Prerequisites:
#
# The $POOLNAME must be configured with the encryption and compression features enabled.
# The $POOLNAME must be mounted at the Linux file system root, and $BENCHMARKROOTDS must exist.
# (I.e., don't let the zpool root filesystem have mountpoint=none or canmount=off.)
# fio, bc, and a couple of standard command-line utilities must be installed.
# The user running this script must either be root, or have elevated ZFS rights.
# The system should obviously not be under high load from other programs during the tests.
# The active recordsize/atime/sync/etc parameters should not be wrong enough to skew the test results.


# Optional external configuration file:
#
# Create the file /etc/zfsbenchmark.conf, and define variables that otherwise would
# taken from under the "Primary settings" below file in this script. That file, if it
# can be read, is sourced from this script, not executed in a subshell.
# I.e., add a line such as this one to /etc/zfsbenchmark.conf:
#	POOLNAME="your_poolname"
# The values that are _supposed_ to be stored in that file are these, and these only:
#	POOLNAME
#	BENCHMARKROOTDS
#	TESTRUNTIME
#	SPECIFY_ZFS_COMMON_OPTIONS
#	COMMON_ZFS_OPTIONS
#	APPEND_PARAMETER_2_TO_TESTROOTDS
#	TESTOBJECTLIST
# (and the 'if $APPEND_PARAMETER_2_TO_TESTROOTDS; then TESTROOTDS="$TESTROOTDS$2"; fi' statement)



# Issues/caveats:
#
# A)	The time measurement is provided by the "time" command, not by fio. There is a
#	small discrepancy, probably because the time command includes time to pre-allocate
#	files on disk, while fio ignores this part. fio also measures time, and this is
#	presented in the human-readable summary output from fio.
#	However, the bandwidth and IOPS that are reported by fio itself are based on the
#	"fio time", so the value of the "time" that is printed at the end of each test
#	might be a bit off but that does not really matter.
# B)	Since tail/head/etc are often used to extract data, it might not be robust for
#	other systems with wildly faster or slower storage than the one used during development.
#	But cosmetic aspects of the output will more likely break due to locale settings or
#	non-Ubuntu operating systems, that have not been tested.
# C)	This script currently only supports compression algorithms that ZFS defined by
#	three (3) characters, such as "lz4".
#	Notably, these do _not_ include the more recent "zstd" variants. This is of course
#	possible to fix, but haven't. [Yet.]


# Compatibility:
#
# Original version tested successfully on Ubuntu 20.04 LTS (Focal Fossa), with zfs-dkms,
# current as of 2020-05-14, with a single-disk vdev on a USB 3 mechanical hard drive.
#
# Updated version tested on Ubuntu 22.04 (Jammy Jellyfish) with the default in-kernel ZFS support,
# using the HWE kernel. Unfortunately, this means that the kernelspace and userspace ZFS versions
# aren't exactly the same, which is a known bug with this setup (workarounds are to use the
# non-HWE kernel or cherry-picking more modern releases for certain ZFS tools or using ZFS via DKMS).
#
# Other systems have not been tested.




# Primary settings (see note above regarding /etc/zfsbenchmark.conf, which takes precedense over these values):

TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")			# Appended to the test root dataset and used in logfiles
POOLNAME="your_poolname"				# No slashes at all - Overwritten if this line exists in a "/etc/zfsbenchmark.conf" file
BENCHMARKROOTDS="$POOLNAME""/ZFSbenchmark"		# Preexisting dataset/filesystem root, >= 1 levels below $POOLNAME. No trailing slash
TESTROOTDS="$BENCHMARKROOTDS""/Test_$TIMESTAMP"		# New dataset/filesystem that will be created by this script
TESTRUNTIME=60						# Minimum runtime per individual test case in seconds (see fio parameters)

SPECIFY_ZFS_COMMON_OPTIONS=false  			# If true: Add the COMMON_ZFS_OPTIONS string to the "zfs create" command for TESTROOTDS
							# If false: Don't, and inherit all non-compression/non-encryption values from BENCHMARKROOTDS
#COMMON_ZFS_OPTIONS="-o recordsize=$1"			# Example: With no error-checking whatsoever: Set recordsize based on command-line parameter
#COMMON_ZFS_OPTIONS="-o recordsize=128k"		# Example: To override the inherited recordsize property
COMMON_ZFS_OPTIONS=""					# See "man zfs" for valid options. E.g.: "-o recordsize=1M -o sync=disabled"

APPEND_PARAMETER_2_TO_TESTROOTDS=false			# If true: Append "$2" to the name when defining the TESTROOTDS variable. If false: Don't.
if $APPEND_PARAMETER_2_TO_TESTROOTDS; then TESTROOTDS="$TESTROOTDS$2"; fi		# Don't forget this line if using the external settings file



# Dataset options format, note that tail/head are used to parse this so the number of characters must remain the same:
# COMPmodENCstd-bit-mod
#	COMPmod:      	COMP: Prefix;	mod: Either "lz4" or "off".
#	ENCstd-bit-mod:	ENV: Prefix;	std: Either "off" or "aes";	bit: 128|192|256; 	mod: ccm|gcm.
#						     If std = "off", the other parameters are ignored
# Note that the possible "compression" values, from "man zfsprops" on Ubuntu 22.04, are:
#	on|off|gzip|gzip-N|lz4|lzjb|zle|zstd|zstd-N|zstd-fast|zstd-fast-N
# 	(But don't use "on" if benchmarks are to be compared across time or between systems, since the default might change.)
# Note that the possible "encryption" values, from "man zfsprops" on Ubuntu 22.04, are:
# 	off|on|aes-128-ccm|aes-192-ccm|aes-256-ccm|aes-128-gcm|aes-192-gcm|aes-256-gcm
# (Again, the default "on" value might change.)

# The interesting combinations:
#TESTOBJECTLIST=("COMPoffENCoff-000-xxx"  "COMPlz4ENCoff-000-xxx"  "COMPlz4ENCaes-256-ccm"  "COMPlz4ENCaes-256-gcm")

# All possible combinations (at least for OpenZFS on Linux 0.8.3):
TESTOBJECTLIST=("COMPoffENCoff-000-xxx"  "COMPlz4ENCoff-000-xxx"  \
		"COMPoffENCaes-128-ccm"  "COMPoffENCaes-192-ccm"  "COMPoffENCaes-256-ccm"  \
		"COMPoffENCaes-128-gcm"  "COMPoffENCaes-192-gcm"  "COMPoffENCaes-256-gcm"  \
		"COMPlz4ENCaes-128-ccm"  "COMPlz4ENCaes-192-ccm"  "COMPlz4ENCaes-256-ccm"  \
		"COMPlz4ENCaes-128-gcm"  "COMPlz4ENCaes-192-gcm"  "COMPlz4ENCaes-256-gcm")


# As stated in a comment above, some of the above variables might defined in another file,
# and if a variable name is defined in that file too, it will overwrite whatever was assigned
# higher up in _this_ file. Note that this file is not essential to have.
EXTERNAL_CONFIG_FILE="/etc/zfsbenchmark.conf"
if [ -r "$EXTERNAL_CONFIG_FILE" ]; then
	. "$EXTERNAL_CONFIG_FILE"
	echo -e "\n\t[*] Note: Might have overwritten some script variables with data from $EXTERNAL_CONFIG_FILE\n"
fi


# Derived settings/variables and other preparation:

LOGDIRECTORY="/tmp/ZFSBenchmark_""$TIMESTAMP"
LOGFILENAME="$LOGDIRECTORY""/Logfile.log"
ERRORNAME="$LOGDIRECTORY""/Errorlog.log"
TESTCASELIST="$LOGDIRECTORY""/Testcaselist"
PERTESTCASE="$LOGDIRECTORY""/CurrentTC_Log"
PERTESTCASE_FULL="${PERTESTCASE}_Full"
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
SUBTEST_1_FIO_BW_MEAN=()
SUBTEST_1_FIO_BW_TOTAL=()
SUBTEST_1_FIO_IOPS_MEAN=()
SUBTEST_1_FIO_IOPS_TOTAL=()
SUBTEST_2_FIO_BW_MEAN=()
SUBTEST_2_FIO_BW_TOTAL=()
SUBTEST_2_FIO_IOPS_MEAN=()
SUBTEST_2_FIO_IOPS_TOTAL=()
SUBTEST_3_FIO_BW_MEAN=()
SUBTEST_3_FIO_BW_TOTAL=()
SUBTEST_3_FIO_IOPS_MEAN=()
SUBTEST_3_FIO_IOPS_TOTAL=()

SCRIPT_PWD="$(pwd)"
DEBUGPRINTOUTS=false		# true or false
PRINTCPUINFO=false		# true or false


PreSubtestcaseStart() {
	rm $PERTESTCASE
	touch $PERTESTCASE
	mkdir Subtest$SUBTESTCASENUMBER
	cd Subtest$SUBTESTCASENUMBER
	if ! [ "$(pwd | tail -c 9 | head -c 8)" == "Subtest$SUBTESTCASENUMBER" ] ; then
		echo " [*] ERROR: Was expecting to be in a directory called \"Subtest$SUBTESTCASENUMBER\", but was in $(pwd)." | tee -a $LOGFILENAME $ERRORNAME
	fi
	sync
	zpool sync
}
# End [ of PreSubtestcaseStart () ]

UpdateCurrentTestcaseAnalysisValues() {
	# When parsing the fio output, it is better to use the JSON output than the human-readable one,
	# since the human-readable is not guaranteed to be stable across fio releases. Also, we might need
	# to detect if slow units are MiB/s and fast units are GiB/s, or similar.
	# When the fio output format is both "normal,json", it appears then JSON data is output before
	# the normal data (regardless of order in the parameter).

	# What the fio output actually means:
	# https://fio.readthedocs.io/en/latest/fio_doc.html#interpreting-the-output

	# In short, look att the JSON "bw" (KiB) or "bw_bytes" (B) values per thread.
	# These represent the total bytes written divided by the total test time.
	# Do _not_ look at "bw_mean", since that is calculated based on min/max over
	# a couple of sample periods, not the entire test sequence. Similarly for IOPS.


	# Note that in the human-readable fio output, the string "random-write" (first on a row) occurs
	#	both before the test is started (before both JSON and normal output, before "fio-<REV>"),
	#	and again in the human-readable output prior to printing actual test result data.
	#	I.e., as long as we know what kind of test we run, we can ignore all "random-write" strings.


	# Get rid of a lot of JSON clutter we don't care about
	mv "$PERTESTCASE" "$PERTESTCASE_FULL"
	cat "$PERTESTCASE_FULL" \
		| grep -v -e "random-write" -e '[[:space:]]*:[[:space:]]*0.00*[,[:space:]]*$' -e '[[:space:]]*:[[:space:]]*0[,[:space:]]*$' \
		> "$PERTESTCASE"

	# In case debugging of this function is needed:
	# set -x

	# Updated value extracted from the fio JSON output: Note that bandwidth from "bw" is in KiB/s, but "bw_bytes" is in B/s.
	LAST_TC_HUMAN_READABLE_FIO_SUMMARY="$(cat $PERTESTCASE | grep 'WRITE')"
	LAST_TC_PROCESSES=$(cat "$PERTESTCASE" | sort | uniq -c | grep '"write" : {' | sed -e 's/^[^0-9]*//' -e 's/[^0-9]*$//')

	LAST_TC_WRITEBANDWIDTH_MEAN_LIST=($(cat "$PERTESTCASE" | grep -e '^[[:space:]]*"bw_bytes"[[:space:]]:' | sed -e 's/\..*$//' -e 's/^[^0-9]*//' -e 's/,[[:space:]]*$//'))
	LAST_TC_WRITEBANDWIDTH_MEAN=0
	for TEMPWRITEBANDWIDTH in "${LAST_TC_WRITEBANDWIDTH_MEAN_LIST[@]}"; do
		LAST_TC_WRITEBANDWIDTH_MEAN="$(($LAST_TC_WRITEBANDWIDTH_MEAN + $TEMPWRITEBANDWIDTH))"
	done
	# This is the total, accumulated, summed bandwidth of all threads, converted to MiB/s:
	LAST_TC_WRITEBANDWIDTH_TOTAL=$(echo "scale=1; $LAST_TC_WRITEBANDWIDTH_MEAN / 1024 / 1024" | bc) 					# "$(($LAST_TC_WRITEBANDWIDTH_MEAN / 1024 / 1024))"
	# And as MiB/s per process:
	LAST_TC_WRITEBANDWIDTH_MEAN=$(echo "scale=1; $LAST_TC_WRITEBANDWIDTH_MEAN / ${#LAST_TC_WRITEBANDWIDTH_MEAN_LIST[@]} /1024 / 1024" | bc)	# "$(($LAST_TC_WRITEBANDWIDTH_MEAN / ${#LAST_TC_WRITEBANDWIDTH_MEAN_LIST[@]} / 1024 / 1024))"

	# Since the other variables generated by this function include unit, add units here too:
	LAST_TC_WRITEBANDWIDTH_TOTAL="$LAST_TC_WRITEBANDWIDTH_TOTAL MiB/s"
	LAST_TC_WRITEBANDWIDTH_MEAN="$LAST_TC_WRITEBANDWIDTH_MEAN MiB/s"

	# Get the "iops" values the same way the bandwidth was extracted above, except that no conversion to MiB/s is needed, truncate the decimal part
	LAST_TC_IOPS_MEAN_LIST=($(cat "$PERTESTCASE" | grep -e '^[[:space:]]*"iops"[[:space:]]:' | sed -e 's/\..*$//' -e 's/^[^0-9]*//' -e 's/,[[:space:]]*$//'))
	LAST_TC_IOPS_MEAN=0
	for TEMPIOPS in "${LAST_TC_IOPS_MEAN_LIST[@]}"; do
		LAST_TC_IOPS_MEAN="$(($LAST_TC_IOPS_MEAN + $TEMPIOPS))"
	done
	LAST_TC_IOPS_TOTAL="$LAST_TC_IOPS_MEAN"						# This is the sum of all threads
	LAST_TC_IOPS_MEAN=$(echo "scale=1; $LAST_TC_IOPS_MEAN / ${#LAST_TC_IOPS_MEAN_LIST[@]}" | bc)		# "$(($LAST_TC_IOPS_MEAN / ${#LAST_TC_IOPS_MEAN_LIST[@]}))"	# And this is per process


	# Older code:
	ZFS_GET_PARAMETER="$TESTROOTDS/$TESTDS@Subtest$SUBTESTCASENUMBER"
	zfs snapshot $ZFS_GET_PARAMETER >> $LOGFILENAME 2>> $ERRORNAME
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
	# But first, in case the locale is such that decimal comma is used (not decimal .), convert it
	LAST_TC_DURATION="$(echo $LAST_TC_DURATION | sed 's/,/./g')"
	TIME_MIN=$(echo $LAST_TC_DURATION | cut -f 1 -d m)
	TIME_SEC=$(echo $LAST_TC_DURATION | cut -f 2 -d m)
	TIME_SEC=$(echo $TIME_SEC | cut -f 1 -d s)
	LAST_TC_THROUGHPUT="scale=1; $LAST_TC_THROUGHPUT / ($TIME_MIN*60 + $TIME_SEC)"
	LAST_TC_THROUGHPUT=$(echo $LAST_TC_THROUGHPUT | bc)MiB/s
	LAST_TC_LOGTHROUGHPUT="scale=1; $LAST_TC_LOGTHROUGHPUT / ($TIME_MIN*60 + $TIME_SEC)"
	LAST_TC_LOGTHROUGHPUT=$(echo $LAST_TC_LOGTHROUGHPUT | bc)MiB/s

	# See note below why the non-fio throughput value is meaningless, so hide the value
	#	echo -e "\n                [*] This took $LAST_TC_DURATION, IOPS/process was about $LAST_TC_IOPS (first occurrence), during which\n" \
	#		"                   $LAST_TC_LOGICALUSED of user data was stored (logicalused) at $LAST_TC_LOGTHROUGHPUT, but compression/metadata/ZFS magic\n" \
	#		"                   meant that $LAST_TC_USED was actually written to disk (used) at $LAST_TC_THROUGHPUT." | tee -a $LOGFILENAME
	echo -e "\n                [*] This took $LAST_TC_DURATION, IOPS/process was about $LAST_TC_IOPS (first occurrence), during which\n" \
		"                   $LAST_TC_LOGICALUSED of user data was stored (logicalused), but compression/metadata/ZFS magic\n" \
		"                   meant that $LAST_TC_USED was actually written to disk (used)." | tee -a $LOGFILENAME
	if [ "$LAST_TC_PROCESSES" == "1" ]; then
		PLURALSTR=""
	else
		PLURALSTR="es"
	fi
	echo -e "                    Accurate fio results showed that the $LAST_TC_PROCESSES process$PLURALSTR had a total bandwidth/throughput\n" \
		"                   of $LAST_TC_WRITEBANDWIDTH_TOTAL ($LAST_TC_WRITEBANDWIDTH_MEAN per process) and $LAST_TC_IOPS_TOTAL IOPS in total ($LAST_TC_IOPS_MEAN IOPS per process).\n\n" \
		| tee -a $LOGFILENAME

	if [ "$(pwd | tail -c 9 | head -c 8)" == "Subtest$SUBTESTCASENUMBER" ] ; then
		cd ..
	else
		echo " [*] ERROR: Was expecting to be in a directory called \"Subtest$SUBTESTCASENUMBER\", but was in $(pwd)." | tee -a $LOGFILENAME $ERRORNAME
	fi
}
# End [ of UpdateCurrentTestcaseAnalysisValues() ]


# All variables are set, start the actual test:

mkdir -p $LOGDIRECTORY
touch $LOGFILENAME
touch $ERRORNAME
touch $TESTCASELIST >> $LOGFILENAME 2>> $ERRORNAME
touch $PERTESTCASE >> $LOGFILENAME 2>> $ERRORNAME
touch $TIMEPERTESTCASE >> $LOGFILENAME 2>> $ERRORNAME

echo -e "***********************************************" | tee -a $LOGFILENAME $ERRORNAME $TESTCASELIST
echo -e "$0, started at $TIMESTAMP" | tee -a $LOGFILENAME $ERRORNAME $TESTCASELIST
echo -e "***********************************************" | tee -a $LOGFILENAME $ERRORNAME $TESTCASELIST
echo -e "\t[Any errors detected during script execution are listed below]" >> $ERRORNAME
echo -e "\nList of test cases (>= 1 measurement per TC, each of which is >= $TESTRUNTIME seconds):" | tee -a $LOGFILENAME $TESTCASELIST


# This loop is mostly for cosmetic reasons:
NO_TESTCASES=0
for TESTDS in ${TESTOBJECTLIST[*]}; do
	NO_TESTCASES=$(($NO_TESTCASES + 1))
	COMPRESSION=$(echo -n $TESTDS | head -c 7 | tail -c 3)
	ENCRYPTION=$(echo -n $TESTDS | tail -c 11)
	if [ "off" == $(echo $ENCRYPTION | head -c 3) ] ; then ENCRYPTION="off"; fi
	echo -e "Test case #""$NO_TESTCASES"":\t$TESTDS\t($COMPRESSION / $ENCRYPTION)" | tee -a $LOGFILENAME $TESTCASELIST
done

if $PRINTCPUINFO ; then
	echo -e "\n\nCPU info:\n\t" \
		"$(lscpu | grep -iF 'Model name' | sed s/'   '//g);" \
		"$(lscpu | grep -iF 'Flags' | sed s/'  '//g).\n\t" \
		"$(lscpu | grep -iF 'Cpu(s):' | sed s/'  '//g);" \
		"$(lscpu | grep -iF 'Thread(s)' | sed s/'   '//g);" \
		"$(lscpu | grep -iF 'max' | sed s/'  '//g)."

	echo -e "ZFS kernel module information:" | tee -a $LOGFILENAME $ERRORNAME $TESTCASELIST
	echo -e "\t$(modinfo zfs | grep -iF author)" | tee -a $LOGFILENAME $ERRORNAME $TESTCASELIST
	echo -e "\t$(modinfo zfs | grep -iF version | grep -ivF srcversion)" | tee -a $LOGFILENAME $ERRORNAME $TESTCASELIST
	echo -e "\t$(modinfo zfs | grep -iF vermagic)" | tee -a $LOGFILENAME $ERRORNAME $TESTCASELIST

	# TBD/TODO: It would be nice to automatically get CPU utilization per test case,
	# but it needs to be taken while the fio processes are running. So perhaps a
	# separate worker thread, which dumps utilization to $LOGDIRECTORY, from which
	# data is read and stored in a SUBTEST_* variable.
	# Perhaps for the next release, since a separate htop window and manual logging also works.
	#
	# But if automated, code like this could be used (this shows the current CPU idle figure):
	# top -b -n 1 | sed -n "s/^%Cpu.*ni, \([0-9.]*\) .*$/\1% Idle/p"
fi

POOL_ASHIFT_VALUE=$(zpool get -H ashift "$POOLNAME" | cut -f 3)
echo -e -n "\n\nCreating the main test dataset on \"$POOLNAME\" (which has ashift=$POOL_ASHIFT_VALUE)" | tee -a $LOGFILENAME
if $SPECIFY_ZFS_COMMON_OPTIONS ; then
	zfs create $COMMON_ZFS_OPTIONS $TESTROOTDS >> $LOGFILENAME 2>> $ERRORNAME
	echo " (custom parameters to \"zfs create\": \"$COMMON_ZFS_OPTIONS\")" | tee -a $LOGFILENAME
else
	zfs create $TESTROOTDS >> $LOGFILENAME 2>> $ERRORNAME
	echo "" | tee -a $LOGFILENAME
fi
RC=$?
if (( $RC )) ; then echo "    [*] Error code $RC was returned from the last operation" | tee -a $LOGFILENAME $ERRORNAME; fi


echo -e "Creating an encryption key" | tee -a $LOGFILENAME
KEYBYTES=32
KEYBITS=$(($KEYBYTES * 8))
KEY_FULL_PATH="/$TESTROOTDS/hexkey_""$KEYBYTES""B_""$KEYBITS""b"
KEY_ZFS_FORMAT="file://""$KEY_FULL_PATH"
echo -n $(tr -dc a-f0-9 < /dev/random | dd bs=$(echo "2*$KEYBYTES" | bc) count=1 2> /dev/null) > $KEY_FULL_PATH 2>> $ERRORNAME
RC=$?
if (( $RC )) ; then echo "    [*] Error code $RC was returned from the last operation" | tee -a $LOGFILENAME $ERRORNAME; fi


echo -e "Creating all test case datasets" | tee -a $LOGFILENAME
CURRENT_TC=0
for TESTDS in ${TESTOBJECTLIST[*]}; do
	CURRENT_TC=$(($CURRENT_TC + 1))
	COMPRESSION=$(echo -n $TESTDS | head -c 7 | tail -c 3)
	ENCRYPTION=$(echo -n $TESTDS | tail -c 11)
	if [ "off" == $(echo $ENCRYPTION | head -c 3) ] ; then ENCRYPTION="off"; fi
	# echo -e "Test case #""$NO_TESTCASES"":\t$TESTDS\t($COMPRESSION / $ENCRYPTION)" | tee -a $LOGFILENAME $TESTCASELIST

	if [ "off" == "$ENCRYPTION" ] ; then
		zfs create -o compression=$COMPRESSION \
			"$TESTROOTDS""/""$TESTDS" >> $LOGFILENAME 2>> $ERRORNAME
	else
		zfs create -o compression=$COMPRESSION \
			-o encryption=$ENCRYPTION \
			-o keyformat=hex \
			-o keylocation=$KEY_ZFS_FORMAT \
			"$TESTROOTDS""/""$TESTDS" >> $LOGFILENAME 2>> $ERRORNAME
	fi
	RC=$?
	if (( $RC )) ; then echo "    [*] Error code $RC was returned, in iteration $CURRENT_TC / $NO_TESTCASES" | tee -a $LOGFILENAME $ERRORNAME; fi
done


# Now ready to start the actual performance test. Change to the test directory
cd "/$TESTROOTDS" >> $LOGFILENAME 2>> $ERRORNAME
RC=$?
if (( $RC )) ; then echo "    [*] Error code $RC was returned from the last operation" | tee -a $LOGFILENAME $ERRORNAME; fi


if (( $RC )); then
	echo -e "\n\t[ERROR]\tSomething has gone wrong, since the test directory was not available. Aborting.\n"
	exit 1
fi

echo -e "\n\t[*] All setup is done, hopefully no error codes above,\n\t\twill start the main test ($TESTRUNTIME s per subtest) after a short delay..."
sleep 3

CURRENT_TC=0
for TESTDS in ${TESTOBJECTLIST[*]}; do
	CURRENT_TC=$(($CURRENT_TC + 1))
	COMPRESSION=$(echo -n $TESTDS | head -c 7 | tail -c 3)
	ENCRYPTION=$(echo -n $TESTDS | tail -c 11)
	if [ "off" == $(echo $ENCRYPTION | head -c 3) ] ; then ENCRYPTION="off"; fi
	echo -e "\n\n***********************\n [*] Starting test case #$CURRENT_TC/$NO_TESTCASES:\t$TESTDS\t($COMPRESSION / $ENCRYPTION)\n" | tee -a $LOGFILENAME

	# Sanity-check: Are we were we think we are?
	if ! [ "$(pwd)" == "/""$TESTROOTDS" ] ; then
		echo -e "\t[*] ERROR: Expected to be in (/""$TESTROOTDS""), was in (""$(pwd)"")" | tee -a $LOGFILENAME $ERRORNAME
	fi
	# Failsafe: Go the the correct, intended directory even if we weren't in it from the start:
	cd "/""$TESTROOTDS" >> $LOGFILENAME 2>> $ERRORNAME

	cd $TESTDS >> $LOGFILENAME 2>> $ERRORNAME
	# Start the test in the current directory
	#echo -e "\t[*] DEBUG: Now in directory $(pwd)"
	##################### START OF ACTUAL DISK I/O TEST #####################

	        ZFS_GET_PARAMETER="$TESTROOTDS""/""$TESTDS""@BeforeTest"
        	zfs snapshot $ZFS_GET_PARAMETER >> $LOGFILENAME 2>> $ERRORNAME
		LAST_TC_USED_RAW=0				# Needed for the UpdateCurrentTestcaseAnalysisValues() function
		LAST_TC_LOGICALUSED_RAW=0


		# Based on https://arstechnica.com/gadgets/2020/02/how-fast-are-your-disks-find-out-the-open-source-way-with-fio/

		# Get the log output to this file, which is overwritten for each fio execution.
		# Extract meaningful parts, discard the rest.
		touch $PERTESTCASE
		touch $TIMEPERTESTCASE	# This file is used to get the output from "time" (redirected stderr)


		SUBTESTCASENUMBER="1"
		PreSubtestcaseStart
		echo -e "\n        [*] Starting subtest $SUBTESTCASENUMBER: Single 4 KiB random write process" | tee -a $LOGFILENAME
		{ time fio --name=random-write --ioengine=posixaio --rw=randwrite --bs=4k --size=4g --numjobs=1 \
			--iodepth=1 --runtime=$TESTRUNTIME --time_based --end_fsync=1 --output-format=normal,json; \
#			} 2> $TIMEPERTESTCASE | tee -a $PERTESTCASE
			} 2> $TIMEPERTESTCASE > $PERTESTCASE
		RC=$?		# RC is ignored except for the last subtest in each test case.
		echo -e "\n                [*] The most relevant part of the fio output is this:\n\t$(cat $PERTESTCASE | grep 'WRITE')" | tee -a $LOGFILENAME
		echo -e "\n                [*] Not so important parts of the fio output are these:" | tee -a $LOGFILENAME
		cat $PERTESTCASE | grep -i iops | grep -v -e '^[[:space:]]*"' | grep -vF "write:" | sed 's/^/\t\t\t/' | tee -a $LOGFILENAME
		cat $PERTESTCASE | grep -i write | grep -v -e '^[[:space:]]*"' | grep -vF "random-write: (" | sed 's/^/\t\t\t/' | tee -a $LOGFILENAME
		UpdateCurrentTestcaseAnalysisValues
		SUBTEST_1_TIME+=($LAST_TC_DURATION)
		SUBTEST_1_LOGICALUSED+=($LAST_TC_LOGICALUSED)
		SUBTEST_1_USED+=($LAST_TC_USED)
		SUBTEST_1_IOPS+=($LAST_TC_IOPS)
		SUBTEST_1_LOGTHROUGHPUT+=($LAST_TC_LOGTHROUGHPUT)
		SUBTEST_1_THROUGHPUT+=($LAST_TC_THROUGHPUT)
		SUBTEST_1_ACC_LOGICALUSED+=($LAST_TC_ACC_LOGICALUSED)
		SUBTEST_1_ACC_USED+=($LAST_TC_ACC_USED)
		SUBTEST_1_FIO_BW_MEAN+=("$LAST_TC_WRITEBANDWIDTH_MEAN")
		SUBTEST_1_FIO_BW_TOTAL+=("$LAST_TC_WRITEBANDWIDTH_TOTAL")
		SUBTEST_1_FIO_IOPS_MEAN+=("$LAST_TC_IOPS_MEAN")
		SUBTEST_1_FIO_IOPS_TOTAL+=("$LAST_TC_IOPS_TOTAL")


		SUBTESTCASENUMBER="2"
		PreSubtestcaseStart
		echo -e "\n        [*] Starting subtest $SUBTESTCASENUMBER: 16 parallel 64 KiB random write processes" | tee -a $LOGFILENAME
		{ time fio --name=random-write --ioengine=posixaio --rw=randwrite --bs=64k --size=256m --numjobs=16 \
			--iodepth=16 --runtime=$TESTRUNTIME --time_based --end_fsync=1 --output-format=normal,json; \
#			} 2> $TIMEPERTESTCASE | tee -a $PERTESTCASE
			} 2> $TIMEPERTESTCASE > $PERTESTCASE
		RC=$?		# RC is ignored except for the last subtest in each test case.
		echo -e "\n                [*] The most relevant part of the fio output is this:\n\t$(cat $PERTESTCASE | grep 'WRITE')" | tee -a $LOGFILENAME
		echo -e "\n                [*] Not so important parts of the fio output are these:" | tee -a $LOGFILENAME
		cat $PERTESTCASE | grep -i iops | grep -v -e '^[[:space:]]*"' | grep -vF "write:" | sed 's/^/\t\t\t/' | tee -a $LOGFILENAME
		cat $PERTESTCASE | grep -i write | grep -v -e '^[[:space:]]*"' | grep -vF "random-write: (" | sed 's/^/\t\t\t/' | tee -a $LOGFILENAME

		# Keep the old "uniq -c"? Probably not...
		#	echo -e "\n                [*] The most relevant parts of the fio output (writes via uniq -c, prefixed by counts):" | tee -a $LOGFILENAME
		#	cat $PERTESTCASE | ... | uniq -c | tee -a $LOGFILENAME

		UpdateCurrentTestcaseAnalysisValues
		SUBTEST_2_TIME+=($LAST_TC_DURATION)
		SUBTEST_2_LOGICALUSED+=($LAST_TC_LOGICALUSED)
		SUBTEST_2_USED+=($LAST_TC_USED)
		SUBTEST_2_IOPS+=($LAST_TC_IOPS)
		SUBTEST_2_LOGTHROUGHPUT+=($LAST_TC_LOGTHROUGHPUT)
		SUBTEST_2_THROUGHPUT+=($LAST_TC_THROUGHPUT)
		SUBTEST_2_ACC_LOGICALUSED+=($LAST_TC_ACC_LOGICALUSED)
		SUBTEST_2_ACC_USED+=($LAST_TC_ACC_USED)
		SUBTEST_2_FIO_BW_MEAN+=("$LAST_TC_WRITEBANDWIDTH_MEAN")
		SUBTEST_2_FIO_BW_TOTAL+=("$LAST_TC_WRITEBANDWIDTH_TOTAL")
		SUBTEST_2_FIO_IOPS_MEAN+=("$LAST_TC_IOPS_MEAN")
		SUBTEST_2_FIO_IOPS_TOTAL+=("$LAST_TC_IOPS_TOTAL")


		SUBTESTCASENUMBER="3"
		PreSubtestcaseStart
		echo -e "\n        [*] Starting subtest $SUBTESTCASENUMBER: Single 1 MiB random write process" | tee -a $LOGFILENAME
		{ time fio --name=random-write --ioengine=posixaio --rw=randwrite --bs=1m --size=16g --numjobs=1 \
			--iodepth=1 --runtime=$TESTRUNTIME --time_based --end_fsync=1 --output-format=normal,json; \
#			} 2> $TIMEPERTESTCASE | tee -a $PERTESTCASE
			} 2> $TIMEPERTESTCASE > $PERTESTCASE
		RC=$?		# RC is ignored except for the last subtest in each test case.
		echo -e "\n                [*] The most relevant part of the fio output is this:\n\t$(cat $PERTESTCASE | grep 'WRITE')" | tee -a $LOGFILENAME
		echo -e "\n                [*] Not so important parts of the fio output are these:" | tee -a $LOGFILENAME
		cat $PERTESTCASE | grep -i iops | grep -v -e '^[[:space:]]*"' | grep -vF "write:" | sed 's/^/\t\t\t/' | tee -a $LOGFILENAME
		cat $PERTESTCASE | grep -i write | grep -v -e '^[[:space:]]*"' | grep -vF "random-write: (" | sed 's/^/\t\t\t/' | tee -a $LOGFILENAME
		UpdateCurrentTestcaseAnalysisValues
		SUBTEST_3_TIME+=($LAST_TC_DURATION)
		SUBTEST_3_LOGICALUSED+=($LAST_TC_LOGICALUSED)
		SUBTEST_3_USED+=($LAST_TC_USED)
		SUBTEST_3_IOPS+=($LAST_TC_IOPS)
		SUBTEST_3_LOGTHROUGHPUT+=($LAST_TC_LOGTHROUGHPUT)
		SUBTEST_3_THROUGHPUT+=($LAST_TC_THROUGHPUT)
		SUBTEST_3_ACC_LOGICALUSED+=($LAST_TC_ACC_LOGICALUSED)
		SUBTEST_3_ACC_USED+=($LAST_TC_ACC_USED)
		SUBTEST_3_FIO_BW_MEAN+=("$LAST_TC_WRITEBANDWIDTH_MEAN")
		SUBTEST_3_FIO_BW_TOTAL+=("$LAST_TC_WRITEBANDWIDTH_TOTAL")
		SUBTEST_3_FIO_IOPS_MEAN+=("$LAST_TC_IOPS_MEAN")
		SUBTEST_3_FIO_IOPS_TOTAL+=("$LAST_TC_IOPS_TOTAL")

	##################### END OF ACTUAL DISK I/O TEST #####################
	if (( $RC )) ; then echo "    [*] Error code $RC was returned, for TC#$CURRENT_TC/$NO_TESTCASES" | tee -a $LOGFILENAME $ERRORNAME; fi

	# This test is finished, move back to the test root
	cd .. >> $LOGFILENAME 2>> $ERRORNAME
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


echo -e "Destroying all test case datasets, but not their parent dataset" | tee -a $LOGFILENAME
CURRENT_TC=0
for TESTDS in ${TESTOBJECTLIST[*]}; do
	CURRENT_TC=$(($CURRENT_TC + 1))

	zfs destroy -fvr "$TESTROOTDS/$TESTDS" >> $LOGFILENAME 2>> $ERRORNAME
	RC=$?
	if (( $RC )) ; then echo "    [*] Error code $RC was returned, in iteration $CURRENT_TC / $NO_TESTCASES" | tee -a $LOGFILENAME $ERRORNAME; fi
done



echo -e "\n\nResults summary:\n****************" | tee -a $LOGFILENAME $TESTCASELIST
echo -e "  Test case\tTest case name          Compr/Encr settings \t Subtest 1\t Subtest 2\t Subtest 3" | tee -a $LOGFILENAME $TESTCASELIST
echo -e "  ---------\t--------------          ------------------- \t ---------\t ---------\t ---------" | tee -a $LOGFILENAME $TESTCASELIST
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
                "${SUBTEST_3_TIME[$SUBTESTINDEX]}" | tee -a $LOGFILENAME $TESTCASELIST

	# Test result: Logical (logicalused) data size as written per subtest
	echo -e "                                          -Logical data size: \t" \
		" ${SUBTEST_1_LOGICALUSED[$SUBTESTINDEX]}  \t" \
		" ${SUBTEST_2_LOGICALUSED[$SUBTESTINDEX]}  \t" \
		" ${SUBTEST_3_LOGICALUSED[$SUBTESTINDEX]}" | tee -a $LOGFILENAME $TESTCASELIST

	# Test result: Actual (used) data size as written per subtest
	echo -e "                                          -Actual data size:  \t" \
		" ${SUBTEST_1_USED[$SUBTESTINDEX]}  \t" \
		" ${SUBTEST_2_USED[$SUBTESTINDEX]}  \t" \
		" ${SUBTEST_3_USED[$SUBTESTINDEX]}" | tee -a $LOGFILENAME $TESTCASELIST

	# The calculations are correct, but why would it be interesting? Hide it...
		#	# Test result: Accumulated, total logical (logicalused) data, for each test case (i.e., subtest 1 + subtest 2 + subtest 3)
		#	echo -e "                                          -Acc. logical data: \t" \
		#		" ${SUBTEST_1_ACC_LOGICALUSED[$SUBTESTINDEX]}  \t" \
		#		" ${SUBTEST_2_ACC_LOGICALUSED[$SUBTESTINDEX]}  \t" \
		#		" ${SUBTEST_3_ACC_LOGICALUSED[$SUBTESTINDEX]}" | tee -a $LOGFILENAME $TESTCASELIST
		#
		#	# Test result: Accumulated, total actual (used) data, for each test case (i.e., subtest 1 + subtest 2 + subtest 3)
		#	echo -e "                                          -Acc. actual data:  \t" \
		#		" ${SUBTEST_1_ACC_USED[$SUBTESTINDEX]}  \t" \
		#		" ${SUBTEST_2_ACC_USED[$SUBTESTINDEX]}  \t" \
		#		" ${SUBTEST_3_ACC_USED[$SUBTESTINDEX]}" | tee -a $LOGFILENAME $TESTCASELIST


	# Replaced by more accurate fio output below (the output is the same for single-process
	# fio tests, but the fio IOPS values below are more accurate for multi-process tests)
		#	# Test result: Input/output operations per second, per process (not an exact value)
		#	# (Cosmetic preparation: Might need to lengthen the IOPS strings, for vertical alignment.)
		#                                                                     IOPSPAD=${SUBTEST_1_IOPS[$SUBTESTINDEX]}
		#	if (( ${#IOPSPAD} < 7 )) ; then IOPSPAD="      "; else IOPSPAD=""; fi; IOPSPAD_1=$IOPSPAD
		#                                                                     IOPSPAD=${SUBTEST_2_IOPS[$SUBTESTINDEX]}
		#	if (( ${#IOPSPAD} < 7 )) ; then IOPSPAD="      "; else IOPSPAD=""; fi; IOPSPAD_2=$IOPSPAD
		#                                                                     IOPSPAD=${SUBTEST_3_IOPS[$SUBTESTINDEX]}
		#	if (( ${#IOPSPAD} < 7 )) ; then IOPSPAD="      "; else IOPSPAD=""; fi; IOPSPAD_3=$IOPSPAD
		#	echo -e "                                          -IOPS/process:      \t" \
		#		" ${SUBTEST_1_IOPS[$SUBTESTINDEX]}$IOPSPAD_1  \t" \
		#		" ${SUBTEST_2_IOPS[$SUBTESTINDEX]}$IOPSPAD_2  \t" \
		#		" ${SUBTEST_3_IOPS[$SUBTESTINDEX]}$IOPSPAD_3" | tee -a $LOGFILENAME $TESTCASELIST

	# Irrelevant result, until the code is changed to take snapshots more frequently
	# than the fio pre-allocated files can be overwritten. For slow USB HDDs, this
	# might not happen for some combinations of recordsize and subtest, but for NVMes,
	# this will likely happen. In other words, this doesn't work as expected, so don't print it.
		#	# Test result: Logical (logicalused) data written per time unit, i.e., throughtput
		#	echo -e "                                          -Logical throughput:\t" \
		#		" ${SUBTEST_1_LOGTHROUGHPUT[$SUBTESTINDEX]}  \t" \
		#		" ${SUBTEST_2_LOGTHROUGHPUT[$SUBTESTINDEX]}  \t" \
		#		" ${SUBTEST_3_LOGTHROUGHPUT[$SUBTESTINDEX]}" | tee -a $LOGFILENAME $TESTCASELIST
		#
		#	# Test result: Actual (used) data written per time unit, i.e., throughtput
		#	echo -e "                                          -Actual throughput: \t" \
		#		" ${SUBTEST_1_THROUGHPUT[$SUBTESTINDEX]}  \t" \
		#		" ${SUBTEST_2_THROUGHPUT[$SUBTESTINDEX]}  \t" \
		#		" ${SUBTEST_3_THROUGHPUT[$SUBTESTINDEX]}" | tee -a $LOGFILENAME $TESTCASELIST


	# Test result: Accurate bandwidth/throughput results according to fio
	echo -e "                                          -Fio BW (/proc):  \t" \
		" ${SUBTEST_1_FIO_BW_MEAN[$SUBTESTINDEX]}\t" \
		" ${SUBTEST_2_FIO_BW_MEAN[$SUBTESTINDEX]}\t" \
		" ${SUBTEST_3_FIO_BW_MEAN[$SUBTESTINDEX]}" | tee -a $LOGFILENAME $TESTCASELIST
	# Test result: Accurate bandwidth/throughput results according to fio
	echo -e "                                          -Fio BW (total):  \t" \
		" ${SUBTEST_1_FIO_BW_TOTAL[$SUBTESTINDEX]}\t" \
		" ${SUBTEST_2_FIO_BW_TOTAL[$SUBTESTINDEX]}\t" \
		" ${SUBTEST_3_FIO_BW_TOTAL[$SUBTESTINDEX]}" | tee -a $LOGFILENAME $TESTCASELIST
	# Test result: Accurate IOPS results according to fio
	echo -e "                                          -Fio IOPS (/proc):\t" \
		" ${SUBTEST_1_FIO_IOPS_MEAN[$SUBTESTINDEX]}   \t" \
		" ${SUBTEST_2_FIO_IOPS_MEAN[$SUBTESTINDEX]}   \t" \
		" ${SUBTEST_3_FIO_IOPS_MEAN[$SUBTESTINDEX]}" | tee -a $LOGFILENAME $TESTCASELIST
	# Test result: Accurate bandwidth/throughput results according to fio
	echo -e "                                          -Fio IOPS (total):\t" \
		" ${SUBTEST_1_FIO_IOPS_TOTAL[$SUBTESTINDEX]}     \t" \
		" ${SUBTEST_2_FIO_IOPS_TOTAL[$SUBTESTINDEX]}     \t" \
		" ${SUBTEST_3_FIO_IOPS_TOTAL[$SUBTESTINDEX]}" | tee -a $LOGFILENAME $TESTCASELIST
	RC=$?
	if (( $RC )) ; then echo "    [*] Error code $RC was returned, in iteration $CURRENT_TC / $NO_TESTCASES" | tee -a $LOGFILENAME $ERRORNAME; fi
done


ENDTIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")
echo -e "\nThis test sequence, which started at $TIMESTAMP, ended at $ENDTIMESTAMP." | tee -a $LOGFILENAME $ERRORNAME $TESTCASELIST
echo -e "Logfiles are stored here: /""$TESTROOTDS" | tee -a $LOGFILENAME $TESTCASELIST
echo -e "***********************************************" | tee -a $LOGFILENAME $ERRORNAME $TESTCASELIST


# Silent final cleanup: Move all log files to the main test directory, before returning to the original directory:
# Failsafe: Go the the correct, intended directory even if we weren't in it from the start (which we should've been):
cd "/""$TESTROOTDS" >> $LOGFILENAME 2>> $ERRORNAME
mv "$LOGDIRECTORY"/* .

cd "${SCRIPT_PWD}"

# Done.
