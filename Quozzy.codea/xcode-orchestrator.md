---
name: xcode-orchestrator
description: >
  Orchestrates Xcode/Codea-exported project fixes using subagents for code
  generation and xcrun/xcodebuild for testing. Use when fixing bugs or adding
  features to a Codea-exported Xcode project running in the iOS simulator.
---

# Xcode Orchestrator Skill

You are the orchestrator. You plan, delegate, test, and integrate.
You do not write implementation code yourself.
Subagents write code. You test it via xcodebuild and xcrun.

## Project Constants

Read these from **HANDOFF.md** → "Project Constants" section.
They are defined there (not here) so this skill stays project-agnostic.

```
SCHEME     = <from HANDOFF.md>
BUNDLE_ID  = <from HANDOFF.md>
BUILD_PATH = <from HANDOFF.md>
SIM_ID     = <from HANDOFF.md, or confirm with: xcrun simctl list | grep Booted>
```

If HANDOFF.md lists multiple SIM_ID values, use the one marked "primary for this project."

## Prerequisites
- CLAUDE.md exists and has been read
- HANDOFF.md exists and has been read (contains project constants)
- STRUCTURE.md exists and has been read
- Simulator is booted (verify with `xcrun simctl list | grep Booted`)

## Workflow

### 1. PLAN
Read HANDOFF.md only. Do not read all Lua files.
Identify the single next task from HANDOFF.md.
If the task touches more than one file, split into atomic subtasks
— one file per subtask.

### 2. SPECIFY
For each subtask, grep the relevant file(s) to find the exact code site.
Do not guess. Do not read entire files — use grep to locate the relevant
function or block, then read only that section.

Write a task spec containing:
  - Exact filename to modify
  - Current behavior (one sentence)
  - Required behavior (one sentence)
  - Constraints (Lua, Codea Legacy 3.x runtime, no external libs)
  - Acceptance criteria (observable, testable)
  - Relevant code context (paste only the relevant function/block)

### 3. DELEGATE
Spawn a subagent via Task tool for each subtask:

  Task({
    prompt: <task spec>,
    description: "Fix [specific thing] in [filename]"
  })

When spawning subagents, pass only `prompt` and `description`.
Do not pass thinking, reasoning_effort, or any model parameters.
If the Task call returns an API error, trigger HARD STOP immediately.

Subagent contract — subagent MUST return:
  - The complete modified file content
  - A one-line summary of what changed
  - Any assumptions made

Do not spawn more than 2 subagents in parallel.

### 4. INTEGRATE
Receive subagent result.
Write the returned file content to disk.
Do not modify it. If it needs changes, send back to a new subagent
with specific correction notes.

### 5. TEST
Build, terminate any running instance, relaunch fresh, then screenshot.
All project-specific values (scheme, bundle ID, build path, sim ID)
come from HANDOFF.md.

```bash
# Build
xcodebuild -scheme $SCHEME \
           -destination "platform=iOS Simulator,id=$SIM_ID" \
           -derivedDataPath $BUILD_PATH \
           -quiet build 2>&1 > /tmp/build.log

# Short-circuit on build failure
grep -q "BUILD FAILED" /tmp/build.log && cat /tmp/build.log && exit 1

# Terminate stale instance
xcrun simctl terminate $SIM_ID $BUNDLE_ID

# Launch fresh
xcrun simctl launch $SIM_ID $BUNDLE_ID

sleep 5

# Screenshot
xcrun simctl io $SIM_ID screenshot /tmp/test.png

# Logs (read persisted ring buffer — see HANDOFF.md Diagnostic Log Access)
CONTAINER=$(xcrun simctl get_app_container $SIM_ID $BUNDLE_ID data)
plutil -p "$CONTAINER/Library/Preferences/${BUNDLE_ID}.plist" | grep DevLogBuffer

# System log (last 30s of devLog output)
xcrun simctl spawn $SIM_ID log show --last 30s --predicate 'process == "Quozzy"' > /tmp/test.log
```

### 6. EVALUATE
Examine screenshot and logs.
Pass criteria: BUILD SUCCEEDED + no runtime crashes in log + visual
result matches acceptance criteria.

Do not self-declare success based on screenshot alone.
Report your screenshot observation to the user and wait for confirmation.

If PASS (pending user confirmation):
  Report screenshot observation.
  Update HANDOFF.md marking task complete.
  Wait for user to confirm before proceeding to next task.

If FAIL:
  Do not fix code yourself.
  Identify the specific error from logs or screenshot.
  Write a correction spec: what failed, what the error says, what to fix.
  Spawn a new subagent with the correction spec.
  Maximum 3 correction attempts before escalating to user.

## Escalation
If a task fails 3 correction attempts:
  Report to user: what was attempted, what failed each time,
  what the current state of the file is.
  Wait for human guidance before continuing.

## HARD STOP
If subagent spawning fails for any reason:
  DO NOT write implementation code yourself.
  DO NOT rationalize exceptions to this rule.
  Report the error to the user and stop.
  Wait for human guidance.

## HANDOFF.md Updates
After each confirmed-complete task, update HANDOFF.md with:
  - Task completed
  - File(s) modified
  - Current state
  - Next task
