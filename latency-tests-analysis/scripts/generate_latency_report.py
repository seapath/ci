import os
import glob
import argparse
import matplotlib.pyplot as plt
import textwrap
import numpy as np

GREEN_COLOR = "#90EE90"
RED_COLOR = "#F08080"

def compute_latency(vm,output):
    vm_path = f"{output}/ts_{vm}.txt"
    pub_path = f"{output}/ts_sv_publisher.txt"
    latencies = np.array([])
    with open(vm_path, buffering=10**4) as vm_file, open(pub_path, buffering=10**4) as pub_file:
        vm_lines = vm_file.readlines()
        pub_lines = pub_file.readlines()
        for vm_line, pub_line in zip(vm_lines, pub_lines):
            iteration_vm, stream_vm, count_vm, ts_vm = vm_line.split(':')
            iteration_pub, stream_pub, count_pub, ts_pub = pub_line.split(':')
            if (iteration_vm, stream_vm, count_vm) == (iteration_pub, stream_pub, count_pub):
                diff = int(ts_vm) - int(ts_pub)
                latencies = np.append(latencies, diff)
    return latencies

def get_stream_count(output):
    filename = os.path.join(output, f"ts_sv_publisher.txt")
    data = np.genfromtxt(filename, delimiter=":", usecols=[1], dtype=str)
    return np.unique(data).size

def compute_min(latencies):
    return np.min(latencies) if latencies.size > 0 else None

def compute_max(latencies):
    return np.max(latencies) if latencies.size > 0 else None

def compute_average(latencies):
    return np.round(np.mean(latencies)) if latencies.size > 0 else None

def save_latency_histogram(latencies, vm, output, limit=None):
    # Plot latency histograms
    plt.hist(latencies, bins=20, alpha=0.7, range=(0, np.max(latencies)))

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
    return filename

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
            latencies = compute_latency(vm, output)
            filename = save_latency_histogram(latencies,vm,output, limit)
            maxlat= compute_max(latencies)
            adoc_file.write(
                    vm_line.format(
                        _vm_=vm,
                        _stream_= get_stream_count(output),
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
