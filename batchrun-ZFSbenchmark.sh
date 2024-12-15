#!/bin/bash

# About:                Version 0.9.0           GPLv3
# 2024-12-10
#
# Helper/companion script to ZFSbenchmark.sh, to automate the benchmarks.


cat << END_OF_TEXT

Batch run of ZFSbenchmark.sh:
-----------------------------
	In order to use this script to run ZFSbenchmark.sh to test performance on datasets
	with different recordsizes, and auto-name the test filesystems accordingly, first
	edit the ZFSbenchmark.sh file in the same directory as this, and define the following:
		SPECIFY_ZFS_COMMON_OPTIONS=true
		COMMON_ZFS_OPTIONS="-o recordsize=\$1"
		APPEND_PARAMETER_2_TO_TESTROOTDS=true
	(Alternatively, add the above to the /etc/zfsbenchmark.conf file, but if so, make
		sure 'if \$APPEND_PARAMETER_2_TO_TESTROOTDS; then TESTROOTDS="\$TESTROOTDS\$2"; fi'
		is also part of that configuration file.)

END_OF_TEXT

read -p "Are the above conditions fulfilled? [y/n]? " -n 1 -r; echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
	echo -e "\nAborting since you didn't enter \"y\"\n"
	exit 10
else
	echo -e "\nStarting the test sequence...\n\n"
fi



# The code below will run the same tests (although using unique encryption keys)
# on several datasets that have unique recordsizes, and name the datasets accordingly:
INTER_TEST_DELAY=10

echo -e "\n\n\t[*]\tAbout to start the next batch, after a delay of $INTER_TEST_DELAY seconds..."; sleep $INTER_TEST_DELAY
./ZFSbenchmark.sh    4k       _recordsize_4k
echo -e "\n\n\t[*]\tAbout to start the next batch, after a delay of $INTER_TEST_DELAY seconds..."; sleep $INTER_TEST_DELAY
./ZFSbenchmark.sh    16k      _recordsize_16k
echo -e "\n\n\t[*]\tAbout to start the next batch, after a delay of $INTER_TEST_DELAY seconds..."; sleep $INTER_TEST_DELAY
./ZFSbenchmark.sh    64k      _recordsize_64k
echo -e "\n\n\t[*]\tAbout to start the next batch, after a delay of $INTER_TEST_DELAY seconds..."; sleep $INTER_TEST_DELAY
./ZFSbenchmark.sh    128k     _recordsize_128k
echo -e "\n\n\t[*]\tAbout to start the next batch, after a delay of $INTER_TEST_DELAY seconds..."; sleep $INTER_TEST_DELAY
./ZFSbenchmark.sh    512k     _recordsize_512k
echo -e "\n\n\t[*]\tAbout to start the next batch, after a delay of $INTER_TEST_DELAY seconds..."; sleep $INTER_TEST_DELAY
./ZFSbenchmark.sh    1M       _recordsize_1M




echo -e "\nDone, test sequence complete.\n\n"
exit 0
