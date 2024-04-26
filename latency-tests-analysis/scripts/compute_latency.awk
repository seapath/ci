# First file
NR == FNR {
        stream = $1;
        timestamps[stream, FNR] = $3;
        next;
}

# Second file
NR != FNR {
        stream = $1
        timestamp = $3;
        diff = timestamp - timestamps[stream, FNR];
        print stream ":" diff > output "differences_" vm ".txt";
        next;
}
