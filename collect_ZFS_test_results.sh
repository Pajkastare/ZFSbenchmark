#!/bin/bash

# About:                Version 0.8.2           GPLv3
# 2020-05-25
#
# Helper/companion script to ZFSbenchmark.sh/batchrun-ZFSbenchmark.sh, to dump
# the test results into a file suitable for importing into Excel/equivalent.

for DIRNAME in ./Test_*; do
	[ -e "$DIRNAME" ] || continue
	echo -e "Current directory: \t$(echo -n $DIRNAME | tail -c+3)"

	# From a sample Testcaselist:
	#	This test sequence, which started at 2020-05-23_225354, ended at 2020-05-23_234625.
	#	Logfiles are stored here: /backuppool/ZFSbenchmark/Test_2020-05-23_225354_recordsize_4k
	echo -e "\tPool name:        \t$(cat $DIRNAME/Testcaselist | grep -F 'Logfiles are stored here' | cut -d '/' -f 2)"
	echo -e "\tStart timestamp:  \t$(cat $DIRNAME/Testcaselist | grep -F 'This test sequence, which' | cut -d ' ' -f 7 | head -c-2 )"
	echo -e "\tEnd timestamp:    \t$(cat $DIRNAME/Testcaselist | grep -F 'This test sequence, which' | cut -d ' ' -f 10 | head -c-2 )"
	# From a sample Testcaselist:
	#	TC #12/14:
	NO_OF_TESTCASES="$(cat $DIRNAME/Testcaselist | grep -F 'TC #' | head -n 1 | cut -d ':' -f 1 | cut -d '/' -f 2)"
	echo -e "\tNumber of TCs:    \t$NO_OF_TESTCASES"
	echo -e "\tZFS version:      \t<TBD, manual edit>"
	echo -e "\tPhysical/vdev:    \t<TBD, manual edit>"
	echo -e "\tRecordsize:       \t$(echo -n $DIRNAME | tail -c+3 | cut -d '_' -f 5)"


	for ((TCNO=1; TCNO<=NO_OF_TESTCASES; TCNO++)); do
		# From a sample Testcaselist:
		#	  TC #14/14:    COMPlz4ENCaes-256-gcm   lz4 / aes-256-gcm        1m7.087s        1m16.977s       1m13.252s
		#	                                          -Logical data size:     991MiB          1381MiB         1524MiB
		#	                                          -Actual data size:      1009MiB         1402MiB         1548MiB
		#	                                          -Acc. logical data:     991MiB          2372MiB         3897MiB
		#	                                          -Acc. actual data:      1009MiB         2411MiB         3960MiB
		#	                                          -IOPS/process:          3846            18              21
		#	                                          -Logical throughput:    14.7MiB/s       17.9MiB/s       20.8MiB/s
		#	                                          -Actual throughput:     15.0MiB/s       18.2MiB/s       21.1MiB/s
		TCSTRING="TC #$TCNO/$NO_OF_TESTCASES:"
		PREFIX="\t\t$TCSTRING\t"
		#echo -e "\t\t$(cat $DIRNAME/Testcaselist | grep -F \#$TCNO/$NO_OF_TESTCASES | head -n $TCNO | tail -n 1)"
		echo -e "$PREFIX""Compression: \t$(cat $DIRNAME/Testcaselist | grep -F \#$TCNO/$NO_OF_TESTCASES | head -n $TCNO | tail -n 1 | cut -d '/' -f 2 | tail -c 6)"
		echo -e "$PREFIX""Encryption:  \t$(cat $DIRNAME/Testcaselist | grep -F \#$TCNO/$NO_OF_TESTCASES | head -n $TCNO | tail -n 1 | cut -d '/' -f 3 | head -c 14)"
		echo -e "$PREFIX$(cat $DIRNAME/Testcaselist | grep -F \#$TCNO/$NO_OF_TESTCASES | head -n $TCNO | tail -n 1 | tail -c 70)"
		echo -e "$PREFIX$(cat $DIRNAME/Testcaselist | grep -F 'Logical data size' | head -n $TCNO | tail -n 1)"
		echo -e "$PREFIX$(cat $DIRNAME/Testcaselist | grep -F 'Actual data size' | head -n $TCNO | tail -n 1)"
		echo -e "$PREFIX$(cat $DIRNAME/Testcaselist | grep -F 'Acc. logical data' | head -n $TCNO | tail -n 1)"
		echo -e "$PREFIX$(cat $DIRNAME/Testcaselist | grep -F 'Acc. actual data' | head -n $TCNO | tail -n 1)"
		echo -e "$PREFIX$(cat $DIRNAME/Testcaselist | grep -F 'IOPS/process' | head -n $TCNO | tail -n 1)"
		echo -e "$PREFIX$(cat $DIRNAME/Testcaselist | grep -F 'Logical throughput' | head -n $TCNO | tail -n 1)"
		echo -e "$PREFIX$(cat $DIRNAME/Testcaselist | grep -F 'Actual throughput' | head -n $TCNO | tail -n 1)"
	done

done

