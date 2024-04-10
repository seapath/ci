# First file
NR == FNR {
    stream = $1;
    counter = $2;
    timestamp = $3;

    timestamps[stream, counter] = timestamp;

    next;
}

# Second file
NR != FNR {
    stream = $1;
    counter = $2;
    timestamp = $3;

    if ((stream, counter) in timestamps) {
        diff = timestamp - timestamps[stream, counter];

        print stream ":" counter ":" diff > output "differences_" vm ".txt";
    }

    next;
}
