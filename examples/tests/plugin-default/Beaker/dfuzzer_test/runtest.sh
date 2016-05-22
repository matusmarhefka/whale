#!/bin/bash

. /usr/share/beakerlib/beakerlib.sh || exit 1


rlJournalStart
    rlPhaseStartSetup
        rlRun "dfuzzer -l" 0 "Lists all available D-Bus connection names."
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "dfuzzer -vn org.freedesktop.systemd1" 0 "Fuzz testing finished"
	rlRun "systemctl status >systemd.status" 0 "systemd status OK"
	rlRun "cat systemd.status" 0 "systemd status after testing"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
