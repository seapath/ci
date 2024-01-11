# Copyright (C) 2023, RTE (http://www.rte-france.com)
# SPDX-License-Identifier: Apache-2.0
#
## Data class for SV timestamps
import argparse
import statistics
from sys import argv


class SV:
    pub_bts=None
    pub_ats=None
    pub_hwts=None
    sub_ts=None

    def __init__(self, pub_hwts, pub_bts=None, pub_ats=None):
        self.pub_hwts = pub_hwts
        if pub_bts:
            self.pub_bts=pub_bts
        if pub_ats:
            self.pub_ats=pub_ats

    def __str__(self):
        return f'(pub_bts={self.pub_bts}, pub_hwts={self.pub_hwts}, pub_ats={self.pub_ats}, sub_ts={self.sub_ts})'


def results_reader(file_name):
    with open(file_name) as f:
        for l in f:
            data = l.strip("\n").split(" ")
            yield list([data[0]] + [int(data[2*i+1])*1000000000 + int(data[2*(i+1)]) for i in range(int((len(data)-1)/2))])


## Output a series based on a list of data
def hist(data):
    dataset = set(data)
    hist_x = sorted(list(dataset))
    hist_y = [data.count(k) for k in hist_x]
    return hist_x, hist_y

## TS in format hh:mm:ss.us (first tcpdump string) changed to time integer
def ts_as_int(ts):
    split_ts = ts.split(":")
    assert len(split_ts) == 3, "Error expected time format hh:mm:ss.us"
    split_sec = split_ts[2].split(".")
    assert len(split_sec) == 2, "Error expected time format hh:mm:ss.us"

    return int(split_sec[1]) + int(split_sec[0])*1000000 + int(split_ts[1]) * 60 * 1000000 + int(split_ts[0]) * 3600 * 1000000
