# steps.md — the loop

The repeatable cycle for one task. Read `CLAUDE.md` for project context and
`task.md` for the backlog. One task per loop iteration. Stay on one feature
branch per task.

## 0. Pick

- Open `task.md`. Take the top **unblocked** item under `## Now`.
- If it touches a shared file (`Recipe`, `KitchenScene`, `KitchenSession`,
  `NetProtocol`), confirm the teammate is OK with it before editing. If not
  confirmed → mark it `blocked: waiting on <name>` and take the next item.

## 1. Branch

- New feature → new branch off `main`: `agung/<feature>`.
- Discard signing churn first so the switch is clean:
  ```bash
  git checkout -- Cooked.xcodeproj/project.pbxproj
  git switch -c agung/<feature> main
  ```
- Continuing a started feature → stay on its branch.

## 2. Build the change

- Smallest change that satisfies the task. Match surrounding code style.
- Presentation vs logic stays separated (SwiftUI reads snapshot + inventory;
  host owns mutations).
- New netcode → guest sends intent, host mutates a table, it rides the snapshot.
  Wire types go in `NetProtocol` as `nonisolated`.

## 3. Verify

- **Always** build green:
  ```bash
  xcodebuild -scheme Cooked -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
  ```
- UI-visible change → screenshot it: temp-point `CookedApp` root at the view,
  `simctl` install + launch + screenshot, then **revert the root**.
- Multiplayer logic → note it needs a 2-device test (can't verify on one sim).
  Don't claim it works when it's only compiled.

## 4. Record outcome

- Update `task.md`: move the item to `## Done` with a one-line result, or leave
  it in `## Now` with a `blocked:` / `needs 2-device test` note.
- New problems found mid-task → add them to `## Later`, don't scope-creep the
  current task.

## 5. Commit

- Only when the build is green.
- One logical change per commit. Message ends with:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  ```
- **Do not push mid-feature.** Push only when the feature is complete and the
  user says so. Merge to `main` via a reviewed PR, never a direct push.

## Loop guardrails

- Green build before every commit — no exceptions.
- Never edit a teammate's shared file without a green light.
- Don't push or open a PR without the user's go-ahead.
- If a task is ambiguous or a design tradeoff appears, surface it — don't guess.
- One task in flight at a time. Finish or park it before the next.
