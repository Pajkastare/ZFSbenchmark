#!/bin/bash

# About:                Version 0.9.0           GPLv3
# 2024-12-10
#
# Helper/companion script to ZFSbenchmark.sh/batchrun-ZFSbenchmark.sh, to dump
# the test results into a single output for manual review, grep:ing to easily
# compare recordsize impact on various tests, or to more easily import the
# test results into Excel/equivalent.
#
# Run this script from "$BENCHMARKROOTDS" (which, by default, is "pool/ZFSbenchmark").
# See the various command-line options below ("--compact" or "--compactfio" or nothing).

if [ -e "/tmp/define-replacement-poolnames.sh" ]; then
	# A file that contains the equal-length arrays POOLNAMELIST and REPLACEMENTNAMELIST, which will swap the former poolnames for the latter
	. /tmp/define-replacement-poolnames.sh
fi



DoStuff() {
	for DIRNAME in ./Test_*; do
		[ -e "$DIRNAME" ] || continue
		echo -e "Current directory: \t$(echo -n $DIRNAME | tail -c+3)"

		POOLNAME_ALT1="$(cat $DIRNAME/Testcaselist | grep -F 'Logfiles are stored here' | cut -d '/' -f 2)"
		# POOLNAME_ALT2=$(cat "$DIRNAME/Logfile.log" | grep 'Creating the main test dataset on "' | head -n 1 | sed 's/^.*"//' | sed 's/" \(which has ashift/ \(which has ashift/' | sed 's/\).*$/\)/')
		POOLNAME_ALT2=$(cat "$DIRNAME/Logfile.log" | grep 'Creating the main test dataset on "' | head -n 1 | grep -F 'which has ashift')
		POOLNAME_ALT2="$(echo $POOLNAME_ALT2 | sed 's/^Creating the main test dataset on //' | cut -d ')' -f 1))"
		POOLNAME_ALT2="$(echo $POOLNAME_ALT2 | sed 's/"//g')"
		if [ -z "POOLNAME_ALT2" ]; then
			POOLNAME_WITH_EXTRA="$POOLNAME_ALT1";
		else
			POOLNAME_WITH_EXTRA="$POOLNAME_ALT2";
		fi
		POOLNAME="$(echo $POOLNAME_WITH_EXTRA | sed 's/[[:space:]].*$//')"

		CHECK_POOLNAME_OUTPUT_RENAMING=true
		declare -p POOLNAMELIST > /dev/null 2>&1 || CHECK_POOLNAME_OUTPUT_RENAMING=false
		declare -p REPLACEMENTNAMELIST > /dev/null 2>&1 || CHECK_POOLNAME_OUTPUT_RENAMING=false
		if $CHECK_POOLNAME_OUTPUT_RENAMING; then
			for (( POOLINDEX=0; POOLINDEX<"${#POOLNAMELIST[@]}"; POOLINDEX++ )); do
				if [ "$POOLNAME" == "${POOLNAMELIST[$POOLINDEX]}" ]; then
					POOLNAME_WITH_EXTRA=$(echo "$POOLNAME_WITH_EXTRA" | sed "s#$POOLNAME#${REPLACEMENTNAMELIST[$POOLINDEX]}#")
					POOLNAME="${REPLACEMENTNAMELIST[$POOLINDEX]}"
					break
				fi
			done
		fi

		echo -e "\tPool name:        \t$POOLNAME_WITH_EXTRA"
		echo -e "\tStart timestamp:  \t$(cat $DIRNAME/Testcaselist | grep -F 'This test sequence, which' | cut -d ' ' -f 7 | head -c-2 )"
		echo -e "\tEnd timestamp:    \t$(cat $DIRNAME/Testcaselist | grep -F 'This test sequence, which' | cut -d ' ' -f 10 | head -c-2 )"
		NO_OF_TESTCASES="$(cat $DIRNAME/Testcaselist | grep -F 'TC #' | head -n 1 | cut -d ':' -f 1 | cut -d '/' -f 2)"
		echo -e "\tNumber of TCs:    \t$NO_OF_TESTCASES"
		RECORDSIZE_ACCORDING_TO_DIRNAME="$(echo -n $DIRNAME | tail -c+3 | cut -d '_' -f 5)"
		if [ -z "$RECORDSIZE_ACCORDING_TO_DIRNAME" ]; then
			RECORDSIZE_ACCORDING_TO_DIRNAME="<Not part of directory name>"
		fi
		echo -e "\tRecordsize:       \t$RECORDSIZE_ACCORDING_TO_DIRNAME"
		echo -e "\tN.B.: Subtest 1 is 1 process/4 KiB, subtest 2 is 16 processes/64 KiB, and subtest 3 is 1 process/1 MiB"


		for ((TCNO=1; TCNO<=NO_OF_TESTCASES; TCNO++)); do
			# From a sample Testcaselist - Although some values were removed from the default output:
			#	  TC #4/4:	COMPlz4ENCaes-256-gcm   lz4 / aes-256-gcm	 1m0.343s	 1m3.416s	 1m1.335s
			#	                                          -Logical data size: 	  4096MiB  	  4061MiB  	  5570MiB
			#	                                          -Actual data size:  	  146MiB  	  1212MiB  	  5597MiB
			#	                                          -Acc. logical data: 	  4096MiB  	  8157MiB  	  13728MiB
			#	                                          -Acc. actual data:  	  146MiB  	  1359MiB  	  6956MiB
			#	                                          -IOPS/process:      	  1137        	  19        	  91
			#	                                          -Logical throughput:	  67.8MiB/s  	  64.0MiB/s  	  90.8MiB/s
			#	                                          -Actual throughput: 	  2.4MiB/s  	  19.1MiB/s  	  91.2MiB/s
			#	                                          -Fio BW (/proc):  	  4.4 MiB/s	  1.2 MiB/s	  91.3 MiB/s
			#	                                          -Fio BW (total):  	  4.4 MiB/s	  20.1 MiB/s	  91.3 MiB/s
			#	                                          -Fio IOPS (/proc):	  1137.0  	  19.5  	  91.0
			#	                                          -Fio IOPS (total):	  1137  	  313  	  	  91
			TCSTRING="TC #$TCNO/$NO_OF_TESTCASES:"
			PREFIX="\t\t$TCSTRING\t"
			#echo -e "\t\t$(cat $DIRNAME/Testcaselist | grep -F \#$TCNO/$NO_OF_TESTCASES | head -n $TCNO | tail -n 1)"
			echo -e "$PREFIX""Compression: \t$(cat $DIRNAME/Testcaselist | grep -F \#$TCNO/$NO_OF_TESTCASES | head -n $TCNO | tail -n 1 | cut -d '/' -f 2 | tail -c 6)"
			echo -e "$PREFIX""Encryption:  \t$(cat $DIRNAME/Testcaselist | grep -F \#$TCNO/$NO_OF_TESTCASES | head -n $TCNO | tail -n 1 | cut -d '/' -f 3 | head -c 14)"
			echo -e "$PREFIX$(cat $DIRNAME/Testcaselist | grep -F \#$TCNO/$NO_OF_TESTCASES | head -n $TCNO | tail -n 1 | sed 's/^.*COMP/\t\tCOMP/')"
			echo -e "$PREFIX$(cat $DIRNAME/Testcaselist | grep -F 'Logical data size' | head -n $TCNO | tail -n 1)"
			echo -e "$PREFIX$(cat $DIRNAME/Testcaselist | grep -F 'Actual data size' | head -n $TCNO | tail -n 1)"
			echo -e "$PREFIX$(cat $DIRNAME/Testcaselist | grep -F 'Acc. logical data' | head -n $TCNO | tail -n 1)"
			echo -e "$PREFIX$(cat $DIRNAME/Testcaselist | grep -F 'Acc. actual data' | head -n $TCNO | tail -n 1)"
			echo -e "$PREFIX$(cat $DIRNAME/Testcaselist | grep -F 'IOPS/process' | head -n $TCNO | tail -n 1)"
			echo -e "$PREFIX$(cat $DIRNAME/Testcaselist | grep -F 'Logical throughput' | head -n $TCNO | tail -n 1)"
			echo -e "$PREFIX$(cat $DIRNAME/Testcaselist | grep -F 'Actual throughput' | head -n $TCNO | tail -n 1)"
			echo -e "$PREFIX$(cat $DIRNAME/Testcaselist | grep 'Fio [bB][wW] (/proc)' | head -n $TCNO | tail -n 1)"
			echo -e "$PREFIX$(cat $DIRNAME/Testcaselist | grep 'Fio [bB][wW] (total)' | head -n $TCNO | tail -n 1)"
			echo -e "$PREFIX$(cat $DIRNAME/Testcaselist | grep -F 'Fio IOPS (/proc)' | head -n $TCNO | tail -n 1)"
			echo -e "$PREFIX$(cat $DIRNAME/Testcaselist | grep -F 'Fio IOPS (total)' | head -n $TCNO | tail -n 1)"
		done

	done
}


# The sed commands below are to fix cosmetic alignment problems that may or may not be part of the output files,
# but probably not needed for the newest versions.

if [ ! -z "$1" ] && [ "$1" == "--compact" ]; then
	echo -e "\n\tCOMPACT OUTPUT\n\t**************"
	DoStuff | grep -F 'N.B.: Subtest 1 is' | head -n 1
	DoStuff | grep -e 'Pool name' -e 'Recordsize' -e '^[[:space:]]*TC #[0-9]*/[0-9]*:[[:space:]]*COMP' -e '\-Fio' -e '\-Logical data size' -e '\-Actual data size' \
		| sed -E '/[[:space:]]-Fio / s/ ([0-9][0-9.]*)[[:space:]][[:space:]]*([0-9][0-9.]*)/ \1     \t  \2/' \
		| sed -E '/[[:space:]]-Fio / s/ ([0-9][0-9.]*)[[:space:]][[:space:]]*([0-9][0-9.]*)$/ \1     \t  \2/'
elif [ ! -z "$1" ] && [ "$1" == "--compactfio" ]; then
	echo -e "\n\tCOMPACT OUTPUT - TOTAL FIO VALUES ONLY\n\t**************************************"
	DoStuff | grep -F 'N.B.: Subtest 1 is' | head -n 1
	DoStuff | grep -e 'Pool name' -e 'Recordsize' -e '^[[:space:]]*TC #[0-9]*/[0-9]*:[[:space:]]*COMP' -e '\-Fio' \
		| sed -E '/[[:space:]]-Fio / s/ ([0-9][0-9.]*)[[:space:]][[:space:]]*([0-9][0-9.]*)/ \1     \t  \2/' \
		| sed -E '/[[:space:]]-Fio / s/ ([0-9][0-9.]*)[[:space:]][[:space:]]*([0-9][0-9.]*)$/ \1     \t  \2/' \
		| grep -v -F "(/proc)"
else
	DoStuff | grep -v -e '^[[:space:]][[:space:]]*TC #[0-9]*/[0-9]*:[[:space:]]*$' \
		| sed -E '/[[:space:]]-Fio / s/ ([0-9][0-9.]*)[[:space:]][[:space:]]*([0-9][0-9.]*)/ \1     \t  \2/' \
		| sed -E '/[[:space:]]-Fio / s/ ([0-9][0-9.]*)[[:space:]][[:space:]]*([0-9][0-9.]*)$/ \1     \t  \2/'
fi

