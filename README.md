# ZFSbenchmark
ZFS benchmarking originally created for Ubuntu 20.04 LTS (ZFS 0.8.3).

The purpose is to measure the disk write performance for a certain
computer and drive, comparing the effect of various ZFS settings such
as recordsize, encryption type, compression etc. 
The testing, on ZFS datasets created for this purpose, is
performed using fio with three different settings.

In a recent code update, hoping for increased compatibility across fio
versions (even future ones), the output from fio was switched from 
human-readable (the default) to "json", and the JSON-based fio output
for bandwidth (throughput) and IOPS are presented.

It's a bit quick-and-dirty, but was tested on both slow (USB3 HDD),
medium (SATA SSD) and fast (NVMe) drives in 2024 under Ubuntu 22.04.

See comments primarily at the top of ZFSbenchmark.sh for more details.


# Batch mode
See the batchrun-ZFSbenchmark.sh file, followed by running
the collect_ZFS_test_results.sh script, to easily see how different
recordsizes, compression, encryption and disk write load 
settings affect each other.


# ZFS tuning
This is not the place to find information about how to optimally
tune a ZFS-based system, this repository only provides a mean to test
certain options under assumed load conditions.

However, getting the most out of a ZFS system means knowing how to
characterize the load the system is put under.

And if that information is not known, ZFS has some reasonable default
values (i.e., encryption=on and compression=on).


# Is higher bandwidth/througput and more IOPS always better?
Often yes, but not necessarily always. For very-high-speed NVMe drives, that
support 7+ GiB/s write speeds under optimal conditions, a multi-core 
desktop computer might freeze up during the most intensive disk access parts.
This might not happen at all if using slower drives, if the I/O queue
is emptied slowly enough to give the CPU sufficient time for non-disk-I/O tasks.

For that reason, artifically reducing disk write speeds by choosing
a suboptimal encryption algorithm might actually make the system
_seem_ smoother, at the cost of disk I/O performance. Unintuitive as it may seem.

So to measure the fastest possible speeds for the various ZFS options,
run these scripts without using the system while the tests are in progress,
and make sure no disk-intensive cron jobs will be running either.
But to get a feel for how well the system can cope with the various loads,
use the system "normally" while the test is in progress (keeping in mind that
test results will be less accurate, if other programs are competing for the
same computer resources that this test script uses).


# A note about older versions
The original version of the main measurement script accurately measured
bytes actually used on the zpool after each test case, but it failed
to present the actual, accurate write speeds (but it did show the
raw fio outputs, which were accurate, in a log file). The reason was that
the code incorrectly assumed that all data files were overwritten exactly
once. (fio pre-allocates data files which are then overwritten as many times 
as possible before the test timeout expires.) That output was commented out.

ZFS is a copy-on-write filesystem, so no matter how many times the fio
files are overwritten the data is still there on disk, but unless snapshots
are taken frequently enough, the zpool frees the bytes no longer referenced
by either file or snapshot (and these freed bytes were
not included in the throughput calculation).
