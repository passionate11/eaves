#!/usr/bin/env python3
"""Writes the demo checklist used in the README screenshots.

Kept out of Tools/shoot.sh so the sample content is editable on its own, and
so nobody has to read shell heredocs to see what ends up in the pictures.

Deliberately English and deliberately generic: these images go in a public
README, and the author's real notes are neither.
"""
import json
import sys
import uuid


def item(text, done=False, nxt=None):
    d = {"id": str(uuid.uuid4()).upper(), "text": text, "done": done}
    if nxt:
        d["next"] = nxt
    return d


def note(title, color, items, tags=None):
    return {
        "id": str(uuid.uuid4()).upper(),
        "title": title,
        "color": color,
        "items": items,
        "tags": tags or [],
        "collapsed": False,
        "dock": "none",
        "floatOnTop": True,
        "x": 1700, "y": 700, "width": 380, "height": 420,
    }


NOTES = [
    # Two done out of five: a half-finished list is what shows off the progress
    # line and the strike-through at the same time.
    note("Writing", "red", [
        item("Draft the intro", done=True),
        item("Pareto-front figure", done=True),
        item("Rewrite section 3", nxt="start from the ablation table"),
        item("Ask Wei for a read-through"),
        item("Submit before the deadline"),
    ]),
    note("Work", "blue", [
        item("Ship the routing patch", done=True),
        item("Reply on the design doc"),
        item("Weekly sync notes"),
    ]),
    note("Life", "green", [
        item("Book the flight"),
        item("Badminton, Thursday 8pm"),
    ]),
]


def main():
    path = sys.argv[1]
    json.dump(NOTES, open(path, "w"), indent=2, ensure_ascii=False, sort_keys=True)
    print(f"demo content -> {path}")


if __name__ == "__main__":
    main()
