#!/bin/bash

echo -e "\nBatch run of ZFSbenchmark.sh:"
echo -e   "-----------------------------"
echo -e "\tIn order to use this script to run ZFSbenchmark.sh to test performance on datasets"
echo -e "\twith different recordsizes, and auto-name the test filesystems accordingly, first"
echo -e "\tedit the ZFSbenchmark.sh file in the same directory as this, and define the following:"
echo -e "\t\tSPECIFY_ZFS_COMMON_OPTIONS=true"
echo -e "\t\tCOMMON_ZFS_OPTIONS=\"-o recordsize=\$1\""
echo -e "\t\tAPPEND_PARAMETER_2_TO_TESTROOTDS=true"
echo
read -p "Are the above conditions fulfilled? [y/n]? " -n 1 -r; echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
	echo -e "\nAborting since you didn't enter \"y\"\n"
	exit 10
else
	echo "\nStarting the test sequence...\n\n"
fi



# The code below will run the same tests (although using unique encryption keys)
# on several datasets that have unique recordsizes, and name the datasets accordingly:

./ZFSbenchmark.sh    4k       _recordsize_4k
./ZFSbenchmark.sh    16k      _recordsize_16k
./ZFSbenchmark.sh    64k      _recordsize_64k
./ZFSbenchmark.sh    128k     _recordsize_128k
./ZFSbenchmark.sh    512k     _recordsize_512k
./ZFSbenchmark.sh    1M       _recordsize_1M




echo "\nDone, test sequence complete.\n\n"
exit 0

