# First file
NR == FNR {
        iteration = $1;
        stream = $2;
        count = $3
        timestamps[iteration, stream, count] = $4;
        next;
}

# Second file
NR != FNR {
        iteration = $1;
        stream = $2;
        count = $3;
        timestamp = $4;
        diff = timestamp - timestamps[iteration, stream, count];
        print iteration ":" stream ":" diff > output "differences_" vm ".txt";
        next;
}
