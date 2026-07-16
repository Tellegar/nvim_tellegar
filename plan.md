# `:Cpp` menu — next iteration

## Context

The `:Cpp` floating menu (`lua/cpp.lua` + `lua/cpp/menu.lua`) already drives
per-project cmake + clangd: pick a root, configure/build/run/debug, choose build
kit/type, restart clangd, open ccmake. This iteration reframes the **config**
section as a **build-directory editor** (each build dir under
`<project_root>/build/*`, coexisting with CLion / command-line cmake), adds a
**build-dir** element, tightens **when config is written to disk**, teaches kit
selection about **CMakePresets.json**, and restarts clangd after **build** (not
just configure). DAP support comes later.

Current menu, for reference:

```
╭ nvim_tellegar ────────────────────────────────────────╮
│                                                       │
│▌ p  Project root           ~/.config/nvim_tellegar ●  │
│                                                       │
│  build ─────────────────────────────────────────────  │
│  c  Configure                                         │
│  b  Build                                  no target  │
│  B  Rebuild                            clean + build  │
│  r  Run                                               │
│  d  Debug                                             │
│  x  Cancel task                                       │
│                                                       │
│  config ────────────────────────────────────────────  │
│  K  Build kit                           clang-libc++  │
│  t  Build type                                 Debug  │
│                                                       │
│  tools ─────────────────────────────────────────────  │
│  R  Restart clangd                                    │
│  m  Open ccmake                                       │
│                                                       │
│ ───────────────────────────────────────────────────── │
│  ● guessed, not saved   ↵ change   ^s save   q close  │
╰───────────────────────────────────────────────────────╯
```

---

## 1. Build-directory element

Add a `build dir` element to the **config** section, below build type. All build
dirs live at **`<project_root>/build/<name>`** (see §2 for why this fixed layout
matters for coexisting with external tools).

- **Default = generated** from `build_kit` + `build_type`, i.e.
  `{short_kit}-{build_type}`, e.g. `clang-debug`.
  - Generated value is rendered **dark** (`Comment` hl, like an unsaved/derived
    value) to signal "this follows kit/type, I didn't pick it".
  - It is **regenerated** whenever build kit or build type changes.
- **Selecting a build dir sets the active kit + type** to that dir's pair;
  conversely, changing kit/type re-selects (or generates) the matching dir — the
  two views stay in sync. The config section always reflects **one active build
  dir**.

**Short-kit naming rule (decided).** The three kits are treated as **static**
(exactly as defined in the nvim config), so the kit → short-name map is handled
**explicitly**:

| build_kit         | short name |
| ----------------- | ---------- |
| `gcc`             | `gcc`      |
| `clang-libc++`    | `clang`    |
| `clang-libstdc++` | `clang`    |

So `build_dir = {short_kit}-{build_type}` yields `clang-debug` for **both** clang
kits. neovim-tasks' `getBuildDirFromConfig` substitutes `{build_kit}` with the
full lowercased kit name (→ `clang-libc++-debug`), so we generate the name
ourselves from this map rather than relying on the `{build_kit}` token
(`~/.local/share/nvim/lazy/neovim-tasks/lua/tasks/cmake_utils/cmake_utils.lua:23`).

> **Collision to handle:** both clang kits map to the same `clang-<type>` name,
> so a libc++ and a libstdc++ build at the same type want the same directory.
> Resolution: the second one needs an **explicit name** (`Build.name`, §2) — the
> generated default only covers the common single-clang case.

---

## 2. State model

Persisted state holds **only data this menu can modify**, and (per §3) **only
what was explicitly saved**.

```
State (keyed by project_root):
  project_root   [path]
  target         [str]          -- selected build/run/debug target, if set
  builds         [list[Build]]  -- one entry per build directory

Build:  -- the full configuration of ONE build directory;
        -- also defines the layout of the menu's "config" section
  name        [str | nil]       -- dir under <project_root>/build/; nil => generated (§1)
  build_kit   [option]          -- compiler + generator/maketool + preset -D args
  build_type  [option]          -- Debug / RelWithDebInfo / Release ...
  -- extensible: future per-build config knobs live here (see below)
```

**Mental model — the config section *is* a build-directory editor.** Each
`Build` is one directory under `<project_root>/build/`. The **config** section of
the menu shows/edits the currently active `Build`; "(re)configure" means
"configure *this* build directory with *these* settings". `build_kit` and
`build_type` are just the two basic knobs today —

- `build_kit` bundles compiler, generator/make tool, and a set of `-D` cmake
  args (see `cmake/build_kits.json`);
- `build_type` maps to `CMAKE_BUILD_TYPE` plus its own `-D` args
  (`cmake/build_types.json`).

The `Build` shape is meant to **grow** to cover any build-directory configuration
need (extra one-off `-D` args, generator override, etc. — the §7 direction), so
the config section should be built as a list of `Build` fields, not two
hard-coded rows.

- `builds` is always a **list** (uniform shape even for one build). A single
  build may leave `name` nil and use the generated name.
- `build_type` options stay the existing limited set (`debug`, `dev-release`,
  `release` from `cmake/build_types.json`).

### Coexisting with external tools (CLion, command line)

The same project is often configured **simultaneously** by CLion or a raw
`cmake -B build/...` from the shell. The menu must not assume it owns the build
tree:

- **Fixed layout:** all build dirs live under `<project_root>/build/*` (personal
  convention — stick with it for now). This gives one predictable place to look.
- **Discover, don't only remember:** the real directories under
  `<project_root>/build/*` are the source of truth for "what builds exist". The
  saved `builds` list is the menu's *remembered configuration* for them; the two
  can diverge (a dir CLion made won't be in `builds` until adopted). The menu
  should surface on-disk dirs, not just its own saved set.
- **Never clobber:** picking/generating a build dir must not wipe or reconfigure
  a directory another tool owns without the user acting on it explicitly.

> **Open:** exact reconciliation between on-disk `build/*` dirs and the saved
> `builds` list — auto-adopt vs. show-as-unsaved-and-require-`^s`. Leaning: show
> discovered dirs as unsaved entries, adopt on `^s`.

---

## 3. Saving model — **explicit `^s` only** (decided)

Nothing is written to disk until `^s` is pressed on the relevant element.

- `^s` is shown on **every** element (root, target, kit, type, build dir).
- In-session changes are **live** (tasks and clangd use them immediately) but are
  **not persisted** until `^s`.
- Rationale: mis-selecting a project root, or trying out a kit/type, must never
  pollute the on-disk store. Selecting a root is "use for now"; `^s` is
  "remember forever" — these stay separate actions.

**Code impact:** today `pick_param` (`lua/cpp.lua:270`) calls `persist_root`
unconditionally on every kit/type/target change. That must be removed — writes
of any kind go **only** through `^s`. Session state (`project_state`,
`session_roots`) already exists to back the live-but-unsaved values.

---

## 4. Build-kit sources — **nvim kits + CMakePresets.json** (decided)

**neovim-tasks already does most of this — the menu mostly surfaces it, it
doesn't reimplement it.**

- **Mode selection is automatic.** `shouldUsePresets(module_config)` =
  `not module_config.ignore_presets and cmake_presets.check(source_dir)`
  (`cmake_utils/cmake_utils.lua:11`). If the project has a `CMakePresets.json`
  (and `ignore_presets` isn't set), Tasks *already* routes configure / build /
  run / etc. through `--preset` (`module/cmake.lua:62,147,195,…`).
- **The selectors already exist as Tasks params** (`module/cmake.lua:438`), and
  our menu's `pick_param` already calls `cmake_module.params[name]()`, so
  listing them is **no new plumbing**:
  - `configure_preset` → `cmake_presets.parse('configurePresets')`
  - `build_preset` → `cmake_presets.parse('buildPresets')`
  - `ignore_presets` → `{ true, false }` (force kit mode even when presets exist)
  - `build_kit` / `build_type` → as today (kit mode only)
- **In preset mode there is no kit / type / build_dir to choose** — the preset
  owns the compiler, build type, and build dir (`get_build_dir`). So §1/§2's
  generated-build-dir model applies **only in kit mode**.

**Menu work (the actual new part):** make the **config** section mode-aware —

- preset mode → show `configure preset`, `build preset`, and the `ignore_presets`
  toggle (instead of kit / type / build dir);
- kit mode → show kit / type / build dir as in §1.

Free-text / manual kit entry: **not now** (revisit if a project fits neither).

---

## 5. clangd restart on build — **yes** (decided)

Build regenerates the module map / `compile_commands.json`, so clangd should be
restarted after a **successful build**, the same way configure already does.

- Configure restarts clangd because its task sets `after_success =
  reconfigureClangd` (`module/cmake.lua:76–80`, gated by the
  `restart_clangd_after_configure` param), which we've patched to call
  `M.restart_clangd` (`lua/cpp.lua:199`).
- **Build has no `after_success` hook** (`module/cmake.lua:146–185`) and there is
  no `restart_clangd_after_build` param — so this can't be a flag flip. We wire
  it ourselves: restart clangd after a successful build from our `run_task`
  wrapper (`lua/cpp.lua:214`), reusing `M.restart_clangd(root)` (`lua/cpp.lua:175`).

---

## 6. Later — DAP support

Wire up `nvim-dap` behind the `Debug` (`d`) element so debugging launches a real
DAP session rather than the current `Task cmake debug`.

---

## 7. Later — dynamic / extra cmake args (**not now**, explored)

Idea: let the menu specify extra cmake `-D` args (or a build_kit) ad-hoc at
invoke time.

Findings from `module/cmake.lua:105–133` (kit-mode `configure`): cmake args are
assembled from the selected kit's and build type's `cmake_usr_args` (arbitrary
`-D...` flags) plus the kit's `environment_variables` and `generator`. So the
**only** hook Tasks gives for "extra args" is *defining them on a kit or build
type* — exactly what `cmake/build_kits.json` and `cmake/build_types.json` already
do.

There is **no** invoke-time ad-hoc `-D` param, and no way to set a kit
"dynamically" beyond picking an existing entry from the kits file. A one-off
override would require synthesizing a transient kit into the session config (or
extending `module_config` with an extra-args field Tasks doesn't natively read).
Keep as **not now**; documented here so the hook point is known.

---

## Open items

- **On-disk ↔ saved reconciliation** (§2): how discovered `<project_root>/build/*`
  dirs relate to the saved `builds` list (leaning: show discovered as unsaved,
  adopt on `^s`).
- **Clang name collision** (§1): both clang kits generate `clang-<type>`; confirm
  "explicit name for the second one" is the intended resolution.
- **`Build` extensibility** (§2): which config knobs beyond kit/type to expose
  first (extra `-D` args, generator) — ties into §7.
