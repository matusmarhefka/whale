#!/bin/bash

. /usr/share/beakerlib/beakerlib.sh || exit 1


rlJournalStart
    rlPhaseStartSetup
        rlRun "touch asd.txt" 0 "Creating test file"
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "sleep 20" 0 "Sleeping done"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "rm -f asd.txt" 0 "Removing test file"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
