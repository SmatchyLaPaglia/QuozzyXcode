---
name: xcode-orchestrator
description: >
  Orchestrates Xcode/Codea-exported project fixes using delegated Haiku
  processes for investigation and code generation, and xcodebuild/xcrun
  for testing. Use when fixing bugs or adding features to a Codea-exported
  Xcode project running in the iOS simulator.
---
# Xcode Orchestrator Skill

You are the orchestrator. You review, plan, delegate, test, and integrate.
You do not write implementation code yourself.
Delegated Haiku processes do the context-heavy work. You test it via
xcodebuild and xcrun.

This skill is project-agnostic — it derives project-specific values at the
start of a session rather than hardcoding them, so it works the same way
across different Codea-exported Xcode projects.

## Delegation economics — what to delegate and why

The savings mechanism is **keeping the orchestrator's context small**, not
just Haiku's cheaper rate. Everything the orchestrator reads stays in its
context and is re-processed on every subsequent turn, at the most
expensive model's rate. Bulk reads delegated to a throwaway Haiku process
are paid once, cheaply, and only the compressed result enters this
context.

Two delegate types:

- **Investigator** — reads files/logs/greps widely and returns a
  structured evidence brief. Delegate investigation only when it means
  reading multiple files or bulk output (logs, wide greps). A single
  grep or one small file read is cheaper done inline — each spawn pays
  a fresh system prompt and re-reads files with no shared cache.
- **Implementer** — writes code changes, returned as text for review.

Keep for yourself: anything short and judgment-dense (root-cause calls,
plan composition, evaluating evidence). Verification of a delegate's
*validity* claims (evidence-backed, citation-checkable) is cheap;
verification of *completeness* or *judgment* claims ("this is the root
cause", "this is the best approach") costs nearly as much as redoing the
reasoning — so don't delegate those.

**Delegation log — so the human can see whether this is paying off:**
after every delegation, append one line to `DELEGATION_LOG.tsv` in the
project root:

```
date  type(investigate|implement)  step  attempts  input_tokens  output_tokens  total_cost_usd
```

(fields from the delegate's JSON output). When reporting a finished goal,
include the session totals: tokens and cost pushed to Haiku, i.e. context
the orchestrator never had to carry.

## Prerequisites

- Simulator is booted (verify with `xcrun simctl list | grep Booted`)

## Workflow

### 0. CONFIGURE (once per session)

Shell variables die with the session, so persist the derived values to a
file and `source` it in later blocks:

```bash
SCHEME=$(xcodebuild -list -json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); k='project' if 'project' in d else 'workspace'; print(d[k]['schemes'][0])")
BUNDLE_ID=$(xcodebuild -showBuildSettings -scheme "$SCHEME" 2>/dev/null | awk -F' = ' '/PRODUCT_BUNDLE_IDENTIFIER/{print $2; exit}')
SIM_UDID=$(xcrun simctl list devices | grep Booted | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1)
DERIVED_DATA="/tmp/${SCHEME}-build"
cat > .orchestrator-env <<EOF
SCHEME="$SCHEME"
BUNDLE_ID="$BUNDLE_ID"
SIM_UDID="$SIM_UDID"
DERIVED_DATA="$DERIVED_DATA"
EOF
cat .orchestrator-env
```

`-showBuildSettings` is used for BUNDLE_ID (rather than grepping the
pbxproj) because it resolves build variables and won't accidentally grab
a test target's identifier.

This block hasn't been run against a real Xcode project —
`xcodebuild`/`xcrun` only exist on macOS, so it couldn't be tested ahead
of time. Run it alone first and check the four echoed values look right
before trusting it inside a real task; if `SCHEME` or `BUNDLE_ID` come
back empty or wrong, fix the extraction rather than falling back to
hardcoding.

If multiple schemes exist and the first one isn't the right one, ask the
user which to use instead of guessing.

**One-time delegate-invocation probe (once per machine, not per task):**
the exact `claude -p` flag names below (`--allowedTools`,
`--max-budget-usd`) may differ across CLI versions. Before the first real
delegation, run:

```bash
claude -p "Reply with exactly: DELEGATE_OK" \
  --model claude-haiku-4-5-20251001 \
  --output-format json \
  --allowedTools "Read,Grep" \
  --max-budget-usd 0.50 \
  > /tmp/delegate_probe.json
```

If it errors on an unknown flag, check `claude --help` for the current
name (e.g. `--tools` vs `--allowedTools`; the budget flag may not exist
in your version — if so, drop it; it's a safety cap, not load-bearing)
and record the working invocation in HANDOFF.md. Do not proceed to real
delegations until the probe returns parseable JSON with `result`
containing `DELEGATE_OK`.

### 1. REVIEW

- If HANDOFF.md, CLAUDE.md, and/or STRUCTURE.md exist in the project root,
  read them. Do not read all Lua files.
- Before doing anything else, ask any clarifying questions you need about
  the goal. Resolving ambiguity now is cheaper than discovering it three
  steps in.
- If understanding the goal requires reading more than one or two files,
  delegate that reading to an Investigator (see EXECUTE) rather than
  pulling it all into your own context.

### 2. COMPOSE

- Write a step-by-step plan for achieving the goal.
- **Root cause check:** for each step that fixes a bug, ask — is the root
  cause already confirmed, or is this a guess? If it's a guess, insert a
  diagnostic step before the fix step. Do not guess at fixes for runtime
  behavior you haven't confirmed.

  Diagnostic strategies available:

  | Strategy | How | Use when |
  |----------|-----|----------|
  | Codea-side read-back | After `saveImage`/`saveText`, immediately call `readImage`/`readText` on the same path and `print()` success/failure, resolved path, dimensions, errors. | Need to know if save itself succeeds |
  | File-existence probe | Write a small text file to the suspected sandbox path (`Documents:probe.txt`), read it back. | Need to confirm the path prefix works |
  | On-screen indicator | Draw a colored rectangle or status text on-screen, visible in screenshot. | Log stream capture is unreliable, or unverified (see below) |
  | Host-side file check | `xcrun simctl get_app_container`, then `find`/`ls` the Documents directory. | Need to confirm files actually landed on disk |
  | NSLog print() capture | See below. **Unverified — confirm once before relying on it.** | After the one-time probe below has confirmed it works for this project |

  **No touch injection exists.** `simctl` cannot simulate taps, so
  nothing that requires interaction can be observed by this workflow.
  Every diagnostic and every verifiable outcome must be reachable at or
  shortly after launch: auto-trigger it from `setup()` or an early
  `draw()` frame (a temporary auto-run flag is fine — plan its removal
  as a later step), or make the state visible on the first screen.
  Never write a plan step whose verification depends on tapping the app.

  **NSLog print() capture — unverified, confirm once per project before
  trusting it:** run the log-capture block from the test section below,
  with a single `print("PROBE_12345")` added somewhere reachable at
  launch (e.g. `setup()`). NSLog output typically has an **empty
  subsystem**, so try predicates in this order and keep the first that
  captures the probe line:

  1. `process == "<AppName>"` (AppName = the .app basename — most likely to work)
  2. `processImagePath CONTAINS "<AppName>"`
  3. `subsystem == "<bundle id>"`

  Record the working predicate in HANDOFF.md. If none capture it, use
  the on-screen-indicator or file-existence-probe strategies instead.
  Do this once per project, not once per diagnosis.

  **Execute a diagnostic:**
  1. Write instructions for diagnostic instrumentation (NOT a fix) and
     delegate it (see EXECUTE). The instrumentation must auto-trigger at
     launch, per the no-touch-injection rule.
  2. Integrate, build, install, launch with log capture running, grab
     the screenshot.
  3. Read the result to determine root cause.
  4. Report findings to the user before proceeding to the fix step.

- **Testability check:** is every step in the plan observably verifiable
  (build success, a screenshot, specific log content) *without touching
  the app*? Revise any step that isn't until it is.
- **Approval check:** list every point where execution would pause for
  the user, then engineer as many of them away as possible — the goal is
  that once the plan is approved, the whole loop runs unattended.
  Tactics, in order of value:

  1. **Front-load decisions.** Any choice the user would face
     mid-execution (which of two approaches, what a threshold should be,
     whether to keep temporary instrumentation) gets asked at plan
     review instead. Present the options with the plan; never discover a
     decision three steps in that could have been asked now.
  2. **Pre-approve the recurring commands.** The loop runs the same
     command shapes every cycle: `xcodebuild`, `xcrun simctl …`,
     `claude -p …`, `python3 check_codea_api_calls.py …`, `source`/`cp`/
     `diff`/`find`. At plan presentation, ask the user to allowlist
     these once (project `.claude/settings.json` permission rules, or
     "always allow" on the first prompt for each) so permission prompts
     don't gate every iteration.
  3. **Batch what can't be pre-approved.** If a step genuinely needs a
     one-off risky action, group such actions into a single step with
     one approval rather than scattering them.

  Within safe limits — these stops are deliberate and stay: reporting
  diagnostic findings before implementing a fix, Escalation after 3
  failed corrections, HARD STOP on spawn failure, and the user's final
  confirmation before a goal is logged done. Minimize interruptions, not
  oversight.
- Present the plan to the user. Incorporate their changes before executing
  anything.

### 3. EXECUTE

**Delegate via subprocess — Haiku, on the existing subscription, no
separate billing.** Do not use the built-in Task tool. Spawn an
independent `claude` process via the Bash tool. No `ANTHROPIC_BASE_URL`
is set on this command, so it authenticates exactly like this session
does — same login, no new credential.

```bash
claude -p "<instructions>" \
  --model claude-haiku-4-5-20251001 \
  --output-format json \
  --allowedTools "Read,Grep" \
  --max-budget-usd 0.50 \
  > /tmp/delegate_result.json
```

(Use whatever flag names the one-time probe in CONFIGURE confirmed.)

`--allowedTools "Read,Grep"` means the delegate can investigate but
cannot touch the filesystem — it can only answer in text, which is what's
needed anyway to review before anything hits disk. The budget flag is a
safety cap, not an expected cost.

Parse `/tmp/delegate_result.json`. Confirmed field names: `result` (the
delegate's answer text), `is_error` (bool), `total_cost_usd`,
`session_id`, `usage.input_tokens` / `usage.output_tokens`. If `is_error`
is true, treat the step as failed — go to the correction path below, do
not integrate the content. Append the log line to `DELEGATION_LOG.tsv`
either way.

**If the `claude -p` command itself exits non-zero or produces no
parseable JSON**, that's a spawn failure, not a task failure — see HARD
STOP. Do not do the work yourself as a workaround.

#### Investigator delegations

Use when a step needs multiple files read, logs analyzed, or wide greps.
The `<instructions>` should state, in prose: the question to answer,
which files/directories to look in, and that the deliverable is a
**structured evidence brief** — findings stated as facts with `file:line`
citations and short quoted excerpts, plus an explicit "things I could not
determine" section. Instruct it to report evidence, not conclusions or
recommendations; the judgment call stays here.

**Verify by spot-check:** pick one or two citations from the brief and
confirm them with a targeted Read. Do not re-read everything the
investigator read — that would defeat the purpose. If a spot-check fails,
the brief is untrusted; re-delegate with a correction note.

#### Implementer delegations

The `<instructions>` should cover, in prose — no rigid template required,
but the delegate needs enough to work from:

- which file to modify
- what it currently does and what it should do instead
- constraints (Lua, Codea Legacy 3.x runtime, no external libs)
- what "done" looks like for this step
- relevant code (paste only the function/block that matters)
- an explicit instruction not to edit or write files directly, and to
  return the complete modified file content as the final answer
- an explicit instruction to only use Codea API calls it's confident
  exist, and to say so plainly in its summary if it's unsure about any
  function name it used

**Integrate:** back up the original first (`cp file.lua
/tmp/file.lua.bak`), write the returned file content to disk yourself,
then **diff against the backup** (`diff /tmp/file.lua.bak file.lua`) and
confirm the diff contains only the requested change. Watch specifically
for truncation: placeholder comments like `-- rest unchanged`, or whole
functions silently missing — a delegate returning a large file can drop
content. If the diff shows anything beyond the step's scope, send it back
with a correction note rather than editing it directly. Do not modify the
delegate's code yourself.

**Check API calls before building — free, no model cost:**

```bash
python3 check_codea_api_calls.py <modified_file.lua> codea-api-globals.txt
```

`codea-api-globals.txt` is the reference list generated once from a real
Codea runtime (`dump` of `_G` in a blank project — see project setup
notes). The check script is plain text matching, not a Lua parser: it
flags any function-call-shaped identifier that's neither in the reference
list nor defined locally in the same file. It won't catch everything
(method calls like `obj:touched()` aren't flagged), so it's a cheap first
pass, not a guarantee — but it catches the common case of an invented
function name before wasting a build-and-test cycle on it. If it flags
something, check whether it's a genuine miss in the reference list or an
actual invented call before deciding whether to send it back for
correction.

#### Build, install, launch, observe — every implementation step

```bash
source .orchestrator-env

xcodebuild -scheme "$SCHEME" \
           -destination "platform=iOS Simulator,id=$SIM_UDID" \
           -derivedDataPath "$DERIVED_DATA" \
           -quiet build > /tmp/build.log 2>&1 \
  || { echo "BUILD FAILED"; tail -50 /tmp/build.log; exit 1; }

# xcodebuild build does NOT install to the simulator. Without this
# install step, simctl launch runs the PREVIOUS binary and every test
# silently passes against stale code.
APP_PATH=$(find "$DERIVED_DATA/Build/Products" -maxdepth 3 -name "*.app" | head -1)
[ -n "$APP_PATH" ] || { echo "No .app under $DERIVED_DATA"; exit 1; }
APP_NAME=$(basename "$APP_PATH" .app)

xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null
xcrun simctl install "$SIM_UDID" "$APP_PATH"

# Log capture must start BEFORE launch — log stream only sees new
# messages, and diagnostics fire in setup(), i.e. at launch.
# Use the predicate the one-time NSLog probe confirmed for this project.
xcrun simctl spawn "$SIM_UDID" log stream \
  --predicate "process == \"$APP_NAME\"" \
  > /tmp/test.log 2>&1 &
LOGPID=$!

xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"
sleep 8
xcrun simctl io "$SIM_UDID" screenshot /tmp/test.png
kill $LOGPID 2>/dev/null
wait $LOGPID 2>/dev/null
```

Notes on this block:

- Build failure is detected by **exit code**, not by grepping the log —
  `-quiet` plus redirection can leave the log unhelpful on failure, and
  a missed failure means launching stale code and trusting a green
  result that tested nothing.
- Always `kill` the log-stream PID in the same block that started it.
  Never leave a `log stream &` running without a recorded PID — orphaned
  streams accumulate.

Use the screenshot for anything visual; use the log for runtime behavior
(once the one-time NSLog probe has confirmed a working predicate for this
project). Do not self-declare success from the screenshot alone — report
what you observe and, for the plan as a whole, wait for the user's
confirmation before marking it done (see HANDOFF.md rule below).

**If a test fails:** identify the specific error from the log or
screenshot, write a correction note (what failed, what the error says,
what to fix), and re-delegate the same step. This is normal iteration
within one step — several rounds of small adjustment (e.g. nudging
on-screen text placement) are expected and do not need individual
reporting. Maximum 3 correction attempts per step before escalating (see
Escalation).

---

**Standby path — DeepSeek via local proxy. Not active. Do not use unless
the user has explicitly started the proxy and asked for it this
session.**

```bash
ANTHROPIC_BASE_URL="http://127.0.0.1:8787" ANTHROPIC_AUTH_TOKEN="unused-but-required" \
  claude -p "<instructions>" \
  --output-format json \
  --allowedTools "Read,Grep" \
  --max-budget-usd 0.50 \
  > /tmp/delegate_result.json
```

This bypasses the subscription entirely and bills a separate DeepSeek
account behind the proxy, with automatic Haiku fallback if DeepSeek's
balance is out — see deepseek-fallback-setup.md. Leave this block unused
until turned back on deliberately.

## HANDOFF.md — update once per goal, not per step

A goal from COMPOSE may take several delegated steps and several
correction rounds within those steps to land. That back-and-forth is
normal iteration, not separate events worth logging individually.

Update HANDOFF.md exactly once: after reporting the finished result to
the user and they confirm the whole goal is done. Not after each
delegated file change. Not after each correction attempt. If unsure
whether the user considers it done, ask before logging it as done.

When updating it, include: task completed, file(s) modified, current
state, next task — plus the delegation totals for the goal (from
DELEGATION_LOG.tsv) so there's a running record of what delegation is
actually costing/saving.

## HARD STOP

This is specifically about the delegation mechanism breaking — the
`claude -p` command failing to run at all (crash, non-zero exit, no
parseable output) — not about a delegated step failing its test, which is
handled by the normal correction path above.

If spawning ever fails for any reason:

  Do NOT write the implementation yourself as a workaround.
  Do NOT rationalize exceptions to this rule.
  Report exactly what broke to the user and stop.
  Wait for human guidance before continuing.

This exists so delegation never silently stops happening without the user
knowing — if it breaks, they should be told, not left assuming Haiku is
still doing the work when it isn't.

## Escalation

If a step fails 3 correction attempts:

  Report to the user: what was attempted, what failed each time, and the
  current state of the file.
  Wait for human guidance before continuing.

## Project setup notes (one-time, not part of the per-task workflow)

- `codea-api-globals.txt` should exist alongside this file. To (re)generate
  it: run a `dump(_G)`-style traversal in a **blank** Codea project (not
  the real game project, so the list reflects Codea's own built-ins
  without the project's own globals mixed in), save the printed output as
  this file, one `name : type` pair per line.
- The NSLog print() capture method needs its one-time per-project
  predicate probe (described in COMPOSE) before EXECUTE relies on it for
  a real diagnosis.
- The delegate-invocation probe (described in CONFIGURE) needs to pass
  once per machine before the first real delegation.