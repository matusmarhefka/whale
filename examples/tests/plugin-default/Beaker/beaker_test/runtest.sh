#!/bin/bash

. /usr/share/beakerlib/beakerlib.sh || exit 1


rlJournalStart
    rlPhaseStartSetup
        rlRun "touch asd.txt" 0 "Creating test file"
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "ls | grep asd.txt" 0 "File exists"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "rm -f asd.txt" 0 "Removing test file"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
