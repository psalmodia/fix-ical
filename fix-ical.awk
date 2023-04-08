#!/bin/awk -f

BEGIN {
    processing_vevent = 0
}
function ltrim(str) { return(gensub("^ +", "", 1, str)); }
function to24(time12,
              bare_time, ampm, time24)
# Convert 12-hour time (am/pm) to 24-hour time ("military time").
{
    match(time12, " ?[ap]m$")
    bare_time = substr(time12, 1, length(time12) - RLENGTH)
    time24 = gensub(":", "", 1, bare_time) + 0
    ampm = ltrim(substr(time12, RSTART, RLENGTH))
    if ( ampm == "pm") time24 += 1200
    # Add a leading zero and return the last 4.
    time24 = "0" time24
    return(substr(time24, length(time24)-3, 4))
}

# SUMMARY lines that start with a time
/^SUMMARY:[0-9]+:[0-9]/ {
    summary_with_time = gensub(/^SUMMARY:/, "", 1, $0)
    # split along embedded \n.
    # Example: 8:45 am - Matins\n10:00 am - Holy Liturgy\nNo Sunday School
    M = split(summary_with_time, b, "\\\\n[0-9]+:[0-9]")
    for (m = 1; m <= M; m++) {
        msum = b[m]
        msum = gensub("&ndash\\\\;", "-", "g", msum)
        msum = gensub("noon", "pm", 1, msum)
        msum = gensub(" \\(Midnight\\)", "", 1, msum) # " (Midnight)" was added to "12:00 am" (facepalm)

        N = split(msum, a, "[ap]m (- )?[A-Z]")  # "- " is optional b/c sometimes it wasn't there.
        if ( N != 2 ) {
            print "Problem parsing line " NR "."
            print "N=" N ", M=" M ", m=" m ", msum=" msum
            print "b[" m "]=" b[m]
            print
            exit(1)
        }

        # Recover some info that fell out of the split().
        match(msum, "[ap]m (- )?[A-Z]")
        ampm = substr(msum, RSTART, 2)
        missing_cap_loc = RSTART + RLENGTH - 1
        missing_cap = missing_cap_loc > 0 ? substr(msum, missing_cap_loc, 1) : ""

        time_range = a[1] ampm
        desc       =  missing_cap a[2]
        print "**** NR = " NR ", m = " m ", time_range = " time_range ", desc = " desc

        delete(time)
        T = split(time_range, time, " ?- ?")
        if ( T > 2 ) { print "Problem parsing line " NR " for time ranges."; exit(2); }
        if ( T == 2 && !match(time[1], " [ap]m")) {
            match(time[2], " [ap]m")
            time[1] = time[1] substr(time[2], RSTART, RLENGTH)
        }
        printf("*T=" T)
        for(t=1; t <= T; t++) printf(", *time[" t "]=" to24(time[t]))
        print ""
        dtstart = to24(time[1]) "00"  # the last "00" is seconds
        dtend   = T == 2 ? to24(time[2]) "00" : ""
     }
}
/^DTSTART;VALUE=DATE:/ {
    match_str = "DTSTART;VALUE=DATE:"
    recdate = substr($0,
                     length(match_str) + 1,
                     length($0) - length(match_str))
    recvar[++recidx] = "DTSTART"
    recval[recvar[recidx]] = recdate "T" dtstart
    if (dtend) {
        recvar[++recidx] = "DTEND"
        recval[recvar[recidx]] = recdate "T" dtend
    }
}
/^BEGIN:VEVENT/ {
    delete(recvar)
    delete(recval)
    recidx = 0
    recdate = ""
    alldayidx = 0
    processing_vevent = 1
}
/^END:VEVENT/ {
    # Print the VEVENT record.
    #print "BEGIN:VEVENT"
    for ( i = 1; i <= recidx; i++ ) {
        print recvar[i] ":" recval[recvar[i]]
    }
    print "END:VEVENT"
    processing_vevent = 0
}
processing_vevent && !/^DTSTART;VALUE=DATE:/ {
    N = split($0, a, ":")
    recvar[++recidx] = a[1]
    recval[a[1]]     = a[2]
}
!processing_vevent  # pass through non-VEVENT lines.
