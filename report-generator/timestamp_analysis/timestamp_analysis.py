# Copyright (C) 2023, RTE (http://www.rte-france.com)
# SPDX-License-Identifier: Apache-2.0

# This script analyzes timestamp of subscriber and publisher tests results,
# and generates graph and stats from it.
import os
import matplotlib.pyplot as plt
import statistics
from post_processing_utils import *
from sys import argv
import argparse

def main(argv):

    parser = argparse.ArgumentParser()
    parser.add_argument("pub_timestamp_file",
                        help="file path to the output of SV publication stream timestamps, with lines in the format <packet id> <tv_sec> <tv_nsec>")
    parser.add_argument("sub_timestamp_file",
                        help="file path to the output of SV subscriber stream timestamps, with lines in the format <packet id> <tv_sec> <tv_nsec>")
    args = parser.parse_args()


    input_file_name_sub = os.path.expanduser(args.sub_timestamp_file)
    input_file_name_pub = os.path.expanduser(args.pub_timestamp_file)
    skip_first_n = 0
    debug = False
    extra_ts = False
    pub_only = False

    input_file_sub = os.path.expanduser(input_file_name_sub)
    input_file_pub = os.path.expanduser(input_file_name_pub)


    pub_data = {}
    sv_data = {}
    key_doublon = []
    interval_between_pub_us = []
    interval_hw2aclock = []
    interval_bclock2hw = []
    prev = None
    for fields in results_reader(input_file_pub):
        rid = fields[0]
        hw_ts = fields[1]
        if extra_ts:
            clock_ts_before = fields[2]
            clock_ts_after = fields[3]
            interval_hw2aclock.append(clock_ts_after-hw_ts)
            interval_bclock2hw.append(hw_ts-clock_ts_before)

        if rid in pub_data:
                print(f'pas de chance: id {rid} déjà présent')
                key_doublon.append(rid)
        else:
            pub_data[rid]=hw_ts
            sv_data[rid] = SV(hw_ts, clock_ts_before, clock_ts_after) if extra_ts else SV(hw_ts)

        if prev:
            interval_between_pub_us.append(round((hw_ts-prev)/1000))
            if debug:
                print("diff = " + str(hw_ts-prev))
        prev = hw_ts

    lat_pub_sub = []
    missed_rid_list = []
    if not pub_only:
        for fields in results_reader(input_file_sub):
            rid = fields[0]
            sub_ts = fields[1]
            if rid not in key_doublon:
                if rid in pub_data:
                    lat_pub_sub.append(sub_ts-pub_data[rid])
                    sv_data[rid].sub_ts = sub_ts
                else:
                    missed_rid_list.append(rid)

    
    interval_between_pub_us = interval_between_pub_us[skip_first_n:]
    interval_hw2aclock = interval_hw2aclock[skip_first_n:]
    interval_bclock2hw = interval_bclock2hw[skip_first_n:]
    lat_pub_sub = lat_pub_sub[skip_first_n:]



    x, y = hist([round(v/1000) for v in lat_pub_sub])
    plt.bar(x, y)
    plt.xlabel('delay (µs)')
    plt.ylabel('occurences')
    plt.title('pub(hw ts) -> sub (REALTIME) (1 stream)')
    plt.yscale("log")

    sub_name_parts = input_file_sub.split("_") # Spliting parts of subscriber data file name
    sub_machine_name = sub_name_parts[-1].split(".")[0] # And getting subscriber machine name field
    
    if not os.path.isdir('include'):
        os.mkdir('include')

    plt.savefig('include/sub_' + sub_machine_name + '_delay.png')
    plt.close()

    x, y = hist(interval_between_pub_us)
    plt.bar(x, y)
    plt.xlabel('time between packets (µs)')
    plt.ylabel('occurences')
    plt.title('trafgen SEAPATH (1 stream)')
    plt.yscale("log")


    pub_name_parts = input_file_pub.split("_") # Spliting parts of publisher data file name
    pub_machine_name = pub_name_parts[-1].split(".")[0] # And getting publisher machine name field

    plt.savefig('include/pub_' + pub_machine_name + '_interval_between.png')
    plt.close()
    print(f'Latency publication-reception ({len(lat_pub_sub)} frames)\n'
        f'    missed sv: {len(missed_rid_list)}\n'
        f'    std dev pub-sub time: {round(statistics.pstdev(lat_pub_sub))} ns\n'
        f'    median: {statistics.median(lat_pub_sub)} ns\n'
        f'    mean: {round(statistics.mean(lat_pub_sub))} ns\n'
        f'    min: {min(lat_pub_sub)} ns\n'
        f'    max: {max(lat_pub_sub)} ns\n')

    print(f'Interval between published frames ({len(interval_between_pub_us)} frame pairs)\n'
        f'    std dev of frame-to-frame time: {round(statistics.pstdev(interval_between_pub_us))} µs\n'
        f'    median: {statistics.median(interval_between_pub_us)} µs\n'
        f'    mean: {round(statistics.mean(interval_between_pub_us))} µs\n'
        f'    min: {min(interval_between_pub_us)} µs\n'
        f'    max: {max(interval_between_pub_us)} µs\n')

if __name__ == "__main__":
    main(argv)
