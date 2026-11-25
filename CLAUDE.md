# TrueBend

## Tests

The tests are TestUp tests and only run inside SketchUp. There is no
command-line runner.

When you add a test for a fix, confirm that it fails without the fix, and say in
your report whether you did.

Tests must not write to the SketchUp preferences. `isolate_settings` in
`TC_TrueBendTool.rb` shows how to keep option changes in memory.

Give every length in a test a unit, such as `'254mm'`, because the units of the
model the tests run in vary.

## RuboCop

The `Metrics/*` cops are advisory. Report their offenses, but don't restructure
code just to satisfy them. For any other offense in existing code, list the
offenses with a proposed handling before you fix or disable anything.

## Commits

Each commit contains one behaviour change together with its tests. An issue
reference goes at the end of the subject line, as in
`Fix errors after setting bend to zero. Fixes #19`.

## Writing

Write comments, documentation and commit messages as complete, grammatical
English sentences, in the terms an experienced developer would use. Make text
shorter by leaving out what the reader doesn't need, never by dropping words
from sentences. Prefer the established technical term, such as "clamp",
"persist" or "tooltip", over a paraphrase, and the literal word over a
figurative one: "contain", not "hold" or "carry".

For example, write "The first group selects the VCB input mode. The second
contains the bend options." and not "VCB input modes, then bend options."

## Comments

- Don't write a comment that restates what a name or the code already says.
- Don't describe where something is drawn or what it looks like, because such
  descriptions go stale.
- Before you present a change, re-read every comment line you added
  (`git diff -U0 | grep '^+\s*#'`) and check it against these points and the
  Writing section.
