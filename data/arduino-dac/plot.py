import numpy as np
import matplotlib.pyplot as plt

# Load file
def parse_mfli(file_path):

    freq = []
    psd = []

    with open(file_path, "r") as f:
        for line in f:
            if line.startswith("%") or line.strip() == "":
                continue
            parts = line.strip().split(";")
            if len(parts) < 2:
                continue
            try:
                fval = float(parts[0])
                pval = float(parts[1])
                freq.append(fval)
                psd.append(pval)
            except:
                continue

    freq = np.array(freq)
    psd = np.array(psd)

    return freq, psd

def parse_fsva3030(file_path):
    freq = []
    psd = []
    in_data = False

    with open(file_path, "r") as f:
        for line in f:
            line = line.strip()
            if line == "":
                continue

            parts = line.split(";")
            if len(parts) < 2:
                continue

            if parts[0] == "Values":
                in_data = True
                continue

            if not in_data:
                continue

            try:
                fval = float(parts[0])
                pval = float(parts[1])
                freq.append(fval)
                psd.append(pval)
            except ValueError:
                continue

# Plot
plt.figure()

for ch in range(1, 25):
    for v in [0, 5, 9]:
        file_path = f"mfli/ch{ch}-{v}V-1000gain.txt"
        freq, psd = parse_mfli(file_path)
        plt.plot(freq, psd, label=f"ch{ch}, {v}V")

    file_path = f"mfli/noise-floor.txt"
    freq, psd = parse_mfli(file_path)
    plt.plot(freq, psd, label=f"open")

    plt.yscale('log')
    plt.xlabel("Frequency (Hz)")
    plt.ylabel("Spectral Density (V/√Hz)")
    plt.title("Noise Spectrum (log scale)")
    plt.legend(loc="upper right")
    # plt.show()

    plt.savefig(f"plots/mfli-ch{ch}-1000gain.png", dpi=300, bbox_inches="tight")
    plt.close()

