import os
import glob
import argparse
import matplotlib.pyplot as plt
import textwrap
import numpy as np
import subprocess

GREEN_COLOR = "#90EE90"
RED_COLOR = "#F08080"

def count_line(filename):
    out = subprocess.Popen(['wc', '-l', filename],
                         stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT
                         ).communicate()[0]
    return int(out.partition(b' ')[0])

def compute_latency(sub_sv_path, pub_sv_path):
    latencies = np.zeros(2000)

    sub_file = open(sub_sv_path, 'r')
    pub_file = open(pub_sv_path, 'r')

    line_count = 0
    max_line = max(count_line(sub_sv_path), count_line(pub_sv_path))
    while line_count < max_line:
        line_count += 1
        pub_line = pub_file.readline()
        sub_line = sub_file.readline()
        pub_it, pub_stream, pub_index, pub_ts = pub_line.split(':')
        sub_it, sub_stream, sub_index, sub_ts = sub_line.split(':')
        if((pub_it, pub_stream, pub_index) == (sub_it, sub_stream, sub_index)):
            lat = int(sub_ts) - int(pub_ts)
            if lat < 2001:
                latencies[lat] += 1
            else:
                raise NameError('Latency out of range')
    sub_file.close()
    pub_file.close()
    return latencies

def get_stream_count(sub_sv_path, pub_sv_path):
    stream_ID = []

    sub_file = open(sub_sv_path, 'r')
    for line in sub_file:
        _, stream, _, _ = line.split(':')
        if stream not in stream_ID:
            stream_ID.append(stream)
    sub_file.close()

    pub_file = open(pub_sv_path, 'r')
    for line in pub_file:
        _, stream, _, _ = line.split(':')
        if stream not in stream_ID:
            stream_ID.append(stream)
    pub_file.close()
    return len(stream_ID)

def compute_min(latencies):
    if latencies.size > 0:
        for i in range(latencies.size):
            if latencies[i] != 0:
                return i
    return None

def compute_max(latencies):
    if latencies.size > 0:
        for i in reversed(range(latencies.size)):
            if latencies[i] != 0:
                return i
    return None

def compute_average(latencies):
    mean_num = 0
    mean_den = 1 / sum(latencies)
    for i in range(latencies.size):
        mean_num += i * latencies[i]
    return np.round(mean_num * mean_den) if latencies.size > 0 else None

def save_latency_histogram(latencies, vm, output, limit=None):
    # Plot latency histograms
    plt.bar(np.arange(latencies.size),latencies)

    # Add titles and legends
    plt.xlabel("Latency (us)")
    plt.ylabel("Frequency")
    plt.title(f"Latency Histogram for {vm}")

    # Add a red vertical line for the limit
    if limit is not None:
        plt.axvline(x=limit, color='red', linestyle='dashed', linewidth=2, label=f'Limit ({limit} us)')
        plt.legend()

    # Save the plot
    if not os.path.exists(output):
        os.makedirs(output)
    filename = os.path.realpath(f"{output}/latency_histogram_{vm}.png")
    plt.savefig(filename, format='png')
    plt.close()
    print(f"Histogram saved as 'latency_histogram_{vm}.png'.")

def generate_adoc(output, limit):
    with open(f"{output}/latency_tests.adoc", "w", encoding="utf-8") as adoc_file:
        vm_result_files = glob.glob(str(output) + "/ts_guest*.txt")
        vm_names = [file.split("ts_")[1].split(".txt")[0]
                    for file in vm_result_files]

        vm_line = textwrap.dedent(
            """
            ===== VM {_vm_}
            {{set:cellbgcolor!}}
            |===
            |Number of IEC61850 Sampled Value |Minimum latency |Maximum latency |Average latency
            |{_stream_} |{_minlat_} us |{_maxlat_} us |{_avglat_} us
            |===
            image::latency_histogram_{_vm_}.png[]
            """
        )
        pass_line = textwrap.dedent(
            """
            [cols="1,1",frame=all, grid=all]
            |===
            |Max latency < {_limit_} us
            {{set:cellbgcolor!}}
            |{_result_}
            {{set:cellbgcolor:{_color_}}}
            |===
            """
        )

        for vm in vm_names:
            sub_sv_path = f"{output}/ts_{vm}.txt"
            pub_sv_path = f"{output}/ts_sv_publisher.txt"
            latencies = compute_latency(sub_sv_path, pub_sv_path)
            save_latency_histogram(latencies,vm,output, limit)
            maxlat= compute_max(latencies)
            adoc_file.write(
                    vm_line.format(
                        _vm_=vm,
                        _stream_= get_stream_count(sub_sv_path, pub_sv_path),
                        _minlat_= compute_min(latencies),
                        _maxlat_= maxlat,
                        _avglat_= compute_average(latencies),
                    )
            )
            if maxlat < limit:
                adoc_file.write(
                    pass_line.format(
                        _limit_=limit,
                        _result_="PASS",
                        _color_=GREEN_COLOR,
                    )
                )
            else:
                adoc_file.write(
                    pass_line.format(
                        _limit_=limit,
                        _result_="FAILED",
                        _color_=RED_COLOR,
                    )
                )

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate Latency tests report in AsciiDoc format.")
    parser.add_argument("--output", "-o", default="../results/", type=str, help="Output directory for the generated files.")
    parser.add_argument("--limit", "-l", default="1000", type=int, help="Latency limit to unvalidate the test." )
    args = parser.parse_args()
    generate_adoc(args.output, args.limit)
