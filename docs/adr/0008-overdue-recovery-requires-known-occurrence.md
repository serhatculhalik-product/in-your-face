# Overdue recovery requires a known occurrence

**Status**: accepted

An ongoing Commitment resumes as an Overdue Commitment after Pause or an unavailable period only when that Occurrence was already known to the protection flow from a confirmed calendar. An occurrence first discovered after its scheduled start during recovery, relaunch, reconnect, or newly added calendar coverage remains quiet for the current Occurrence. Initial Protection Confirmation is different: it evaluates current eligible commitments immediately, including commitments already underway.

This preserves recovery for commitments the product was already responsible for while avoiding a surprise overdue interruption for a commitment that entered the product's knowledge only after it had started.
