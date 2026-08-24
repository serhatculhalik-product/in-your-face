# Late acceptance does not start protection

**Status**: accepted

When a timed event is first observed as unaccepted and later becomes Accepted after its scheduled start, the app does not create a new Early Reminder or Strong Alert for that Occurrence. This avoids turning a late RSVP change into a surprise interruption and preserves the boundary that protection is based on observed eligible calendar state rather than retroactively treating an already-started event as newly protected.
