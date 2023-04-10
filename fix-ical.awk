#!/bin/awk -f

BEGIN {
    uid_serial = 10000
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

function process_summary(summary_orig, nr,
                         M, N, m, n, a, b, msum, ampm,
                         missing_cap, missing_cap_loc, time_range, desc,
                         time, T, t)  {
    # Global (array) return values: dtstarttime, dtstarttime, summary

    if ( summary_orig !~ /[0-9]+:[0-9]+ ?[ap]m/ ) return (0)

    # DATA-QUIRK: if the value starts with \n (junk), remove it.
    sum = gensub("^(\\\\n)+", "", 1, summary_orig)
    # DATA-QUIRK: if the value has \n with no time immmediately after
    # (the test here is really "with no number immediately after"),
    # then replace the \n with "; ".
    sum = gensub("\\\\n([^0-9])", "; \\1", "g", sum)

    ###DEBUG
    ###print "**** summary_orig=" summary_orig
    ###print "**** sum=" sum

    # Split SUMMARY value along embedded \n.
    # Example: 8:45 am - Matins\n10:00 am - Holy Liturgy\nNo Sunday School
    M = split(sum, b, "\\\\n")

    ###DEBUG
    ###printf("****"); for (m = 1; m <= M; m++) printf(" b[" m "]=" b[m] " "); print ""

    for (m = 1; m <= M; m++) {
        msum = b[m]
        msum = gensub("&ndash\\\\;", "-", "g", msum)  # DATA-QUIRK: remove this HTML entity code
        msum = gensub("noon", "pm", 1, msum)          # DATA-QUIRK: use pm vice noon
        msum = gensub(" \\(Midnight\\)", "", 1, msum) # DATA-QUIRK: " (Midnight)" was added to "12:00 am" (facepalm)

        N = split(msum, a, "[ap]m (- )?[A-Z]")  # DATA-QUIRK: "- " is optional b/c sometimes it wasn't there.
        if ( N != 2 ) {
            print "Problem parsing line " nr "." >> "/dev/stderr"
            print "N=" N ", M=" M ", m=" m ", msum=" msum >> "/dev/stderr"
            print "b[" m "]=" b[m] >> "/dev/stderr"
            print >> "/dev/stderr"
            exit(1)
        }

        # Recover some info that fell out of the split().
        match(msum, "[ap]m (- )?[A-Z]")
        ampm = substr(msum, RSTART, 2)
        missing_cap_loc = RSTART + RLENGTH - 1
        missing_cap = missing_cap_loc > 0 ? substr(msum, missing_cap_loc, 1) : ""

        time_range  = a[1] ampm
        desc        = missing_cap a[2]

        ###DEBUG
        ###print "**** NR = " nr ", m = " m ", time_range = " time_range ", desc = " desc

        T = split(time_range, time, " ?- ?")
        if ( T > 2 ) {
            print "Problem parsing line " nr " for time ranges." >> "/dev/stderr"
            exit(2)
        }

        # DATA-QUIRK: If there are 2 times (start and end times) and
        # the start time doesn't have the am/pm indicator, steal it
        # from the end time (which seems to always have it).
        if ( T == 2 && !match(time[1], " [ap]m")) {
            match(time[2], " [ap]m")
            time[1] = time[1] substr(time[2], RSTART, RLENGTH)
        }

        # Pass back multiple answers to globals.
        dtstarttime[m] = to24(time[1]) "00"  # the last "00" is seconds
        dtendtime[m]   = T == 2 ? to24(time[2]) "00" : ""
        summary[m]     = desc
    }
    return(M)
}

# If the line ends in ^M (carriage return), remove it.
# ("Thanks", Bill Gates, for the unwanted garbage.)
{ sub(/\r$/, "") }

/^BEGIN:VEVENT/ {
    delete(recvar); delete(recval)
    delete(dtstarttime); delete(dtendtime); delete(summary)
    recidx = 0
    recdate = ""
    alldayidx = 0
    processing_vevent = 1
}
/^END:VEVENT/ {
    # Print the VEVENT record.

    # IF we have a SUMMARY in the VEVENT record (I believe we always
    # do), parse it and return how many DTSTART times it yields (from
    # the text of SUMMARY). If there is more than 1 start time, the
    # SUMMARY text read somehting like this:
    # 8:45 am - Matins\n10:00 am - Holy Liturgy\nNo Sunday School
    num_dtstarttime = "SUMMARY" in recval ?
        process_summary(recval["SUMMARY"], recNR["SUMMARY"]) :
        1
    # num_dtstarttime==0 means that the processor didn't find anything to do.
    M = num_dtstarttime ? num_dtstarttime : 1

    for ( i = 1; i <= M; i++ ) {
        for ( j = 1; j <= recidx; j++ ) {
            var = recvar[j]
            if ( num_dtstarttime && var == "DTSTART;VALUE=DATE" ) {
                recdate = substr(recval["DTSTART;VALUE=DATE"], 1, 8)
                print "DTSTART:" recdate "T" dtstarttime[i]
                if (dtendtime[i]) {
                    print "DTEND:" recdate "T" dtendtime[i]
                }
            } else if ( num_dtstarttime && var == "SUMMARY" ) {
                print var ":" summary[i]
            } else if ( var == "UID" ) {
                print var ":" ++uid_serial recval[var]
            } else {
                print var ":" recval[var]
            }
        }
    }
    processing_vevent = 0
}
processing_vevent {
    match($0, ":")
    var = substr($0, 1, RSTART - 1)
    val = substr($0, RSTART + 1, length($0) - RSTART)
    recvar[++recidx] = var  # variable name, e.g., "DTSTAMP"
    recval[var]      = val  # value, e.g., "20230407T194437"
    recNR[var]       = NR   # save this for error messages
}
!processing_vevent  # pass through non-VEVENT lines.
