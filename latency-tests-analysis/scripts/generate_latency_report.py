import os
import sys
import subprocess
import glob
import argparse
import matplotlib.pyplot as plt
import textwrap
import numpy as np

ADOC_FILE_PATH = "latency-tests-report.adoc"

def compute_latency(vm, output):
    # Execute the AWK command to calculate latencies
    process = subprocess.run(f"awk -F : -v vm={vm} -v output={output}/ \
                             -f compute_latency.awk \
                             {output}/ts_sv_publisher.txt\
                             {output}/ts_{vm}.txt",
                             shell=True,
                             stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE)

    # Check if there was an error executing the command
    if process.returncode != 0:
        print("Error executing AWK script", process.stderr.decode())
        sys.exit(process.returncode)

    # Read the differences file
    filename = os.path.join(output, f"differences_{vm}.txt")
    latencies = np.genfromtxt(filename, delimiter=":", usecols=[2], dtype=int)
    return latencies

def get_stream_count(vm, output):
    filename = os.path.join(output, f"differences_{vm}.txt")
    data = np.genfromtxt(filename, delimiter=":", usecols=[0], dtype=str)
    return np.unique(data).size

def compute_min(latencies):
    return np.min(latencies) if latencies.size > 0 else None

def compute_max(latencies):
    return np.max(latencies) if latencies.size > 0 else None

def compute_average(latencies):
    return np.round(np.mean(latencies)) if latencies.size > 0 else None

def save_latency_histogram(latencies, vm, output):
    # Plot latency histograms
    plt.hist(latencies, bins=20, alpha=0.7)

    # Add titles and legends
    plt.xlabel("Latency (us)")
    plt.ylabel("Frequency")
    plt.title(f"Latency Histogram for {vm}")

    # Save the plot
    if not os.path.exists(output):
        os.makedirs(output)
    filename = os.path.realpath(f"{output}/latency_histogram_{vm}.png")
    plt.savefig(filename)
    print(f"Histogram saved as 'latency_histogram_{vm}.png'.")
    return filename

def generate_adoc(output):
    with open(ADOC_FILE_PATH, "w", encoding="utf-8") as adoc_file:
        vm_result_files = glob.glob(str(output) + "/ts_guest*.txt")
        vm_names = [file.split("ts_")[1].split(".txt")[0]
                    for file in vm_result_files]

        adoc_file.write("== Latency tests\n")
        vm_line = textwrap.dedent(
                """
                === VM {_vm_}
                |===
                |Number of stream |Minimum latency |Maximum latency |Average latency
                |{_stream_} |{_minlat_} us |{_maxlat_} us |{_avglat_} us
                |===
                image::{_output_}/latency_histogram_{_vm_}.png[]
                """
        )
        for vm in vm_names:
            latencies = compute_latency(vm, output)
            filename = save_latency_histogram(latencies,vm,output)
            adoc_file.write(
                    vm_line.format(
                        _vm_=vm,
                        _stream_= get_stream_count(vm,output),
                        _minlat_= compute_min(latencies),
                        _maxlat_= compute_max(latencies),
                        _avglat_= compute_average(latencies),
                        _output_= filename
                    )
            )

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate Latency tests report in AsciiDoc format.")
    parser.add_argument("--output", "-o", default="../results/", type=str, help="Output directory for the generated files.")
    args = parser.parse_args()
    generate_adoc(args.output)
