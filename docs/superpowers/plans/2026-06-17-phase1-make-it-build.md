# Phase 1: Make It Build (Apple Silicon) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `librx888` and `SoapyRX888` configure and compile on Apple Silicon macOS (Homebrew CMake 4.x / Apple clang), verified by an arm64 macOS GitHub Actions workflow that builds our forks.

**Architecture:** Two sibling repos. `librx888` (C, libusb engine) builds first and installs; `SoapyRX888` (C++ SoapySDR module) builds against it. The dead `cozycactus/tap` brew dependency is removed — CI builds our own `librx888` fork from source. The "test" at each step is a successful build (local gcc inner loop + authoritative arm64 macOS CI).

**Tech Stack:** CMake, C11 (clang/gcc), C++11, libusb-1.0, SoapySDR, GitHub Actions (`macos-15` arm64 runner).

**Repos:**
- `SoapyRX888`: `/home/kenny/K/SoapyRX888` (remote `git@github.com:qoelet/SoapyRX888`), branch `macos-arm64-resurrection`
- `librx888`: `/home/kenny/K/librx888` (remote `git@github.com:qoelet/librx888`)

---

### Task 1: Make librx888 build robust across compilers (kill -Werror fatality)

**Why:** `librx888/CMakeLists.txt:16` forces `-pedantic-errors -Werror`. Builds clean on gcc 13 but makes the build hostage to any Apple clang warning. Keep warnings visible; stop them being fatal by default. Add an opt-in `RX888_STRICT` for maintainers.

**Files:**
- Modify: `/home/kenny/K/librx888/CMakeLists.txt:16`

- [ ] **Step 1: Replace the hard flag line**

Replace:
```cmake
set(CMAKE_C_FLAGS "-std=c11 -pedantic-errors -Wall -Wextra -Werror")
```
with:
```cmake
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

option(RX888_STRICT "Treat warnings as errors (maintainers)" OFF)
add_compile_options(-Wall -Wextra)
if(RX888_STRICT)
    add_compile_options(-Werror)
endif()
```

- [ ] **Step 2: Verify local gcc build still succeeds**

Run:
```bash
cd /home/kenny/K/librx888 && command rm -rf build && cmake -S . -B build && cmake --build build 2>&1 | tail -5
```
Expected: `[100%] Built target rx888_rec` and exit 0, no errors.

- [ ] **Step 3: Commit**

```bash
cd /home/kenny/K/librx888 && git add CMakeLists.txt
git commit -m "build: make warnings non-fatal by default; add RX888_STRICT opt-in

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Ensure libusb headers reach the CLI utilities on Homebrew arm64

**Why:** `rx888_test`/`rx888_rec` include library headers but `src/CMakeLists.txt` links them only to `${LIBUSB_LINK_LIBRARIES}`, not `PkgConfig::LIBUSB`. The `rx888` target carries `${LIBUSB_INCLUDE_DIRS}` PUBLICly so it *usually* propagates, but on Homebrew arm64 libusb headers live in `/opt/homebrew/.../include/libusb-1.0/`. Make the dependency explicit so includes propagate deterministically.

**Files:**
- Modify: `/home/kenny/K/librx888/src/CMakeLists.txt:25-32`

- [ ] **Step 1: Link the imported target to the executables**

Replace:
```cmake
target_link_libraries(rx888_test rx888
    ${LIBUSB_LINK_LIBRARIES}
    ${CMAKE_THREAD_LIBS_INIT}
)
target_link_libraries(rx888_rec rx888
    ${LIBUSB_LINK_LIBRARIES}
    ${CMAKE_THREAD_LIBS_INIT}
)
```
with:
```cmake
target_link_libraries(rx888_test rx888
    PkgConfig::LIBUSB
    ${CMAKE_THREAD_LIBS_INIT}
)
target_link_libraries(rx888_rec rx888
    PkgConfig::LIBUSB
    ${CMAKE_THREAD_LIBS_INIT}
)
```

- [ ] **Step 2: Verify local gcc build still succeeds**

Run:
```bash
cd /home/kenny/K/librx888 && command rm -rf build && cmake -S . -B build && cmake --build build 2>&1 | tail -5
```
Expected: exit 0, all three targets built.

- [ ] **Step 3: Commit**

```bash
cd /home/kenny/K/librx888 && git add src/CMakeLists.txt
git commit -m "build: link libusb imported target to CLI tools for Homebrew arm64 include propagation

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Fix SoapyRX888 CMake minimum version (THE confirmed build wall)

**Why:** `SoapyRX888/CMakeLists.txt:5` requires CMake `2.8.12`; Homebrew CMake 4.x hard-errors on `< 3.5`. Reproduced locally with CMake 4.3.2. This is the user's reported failure.

**Files:**
- Modify: `/home/kenny/K/SoapyRX888/CMakeLists.txt:5`

- [ ] **Step 1: Bump the minimum**

Replace:
```cmake
cmake_minimum_required(VERSION 2.8.12)
```
with:
```cmake
cmake_minimum_required(VERSION 3.10)
```

- [ ] **Step 2: Verify the configure no longer dies on the version gate**

Run:
```bash
cd /home/kenny/K/SoapyRX888 && command rm -rf build && cmake -S . -B build 2>&1 | head -8
```
Expected: it now passes the version check and proceeds to `find_package(SoapySDR CONFIG)` (which will WARN "SoapySDR development files not found - skipping support" on this Linux box — that is fine and expected here; the version error is gone).

- [ ] **Step 3: Commit**

```bash
cd /home/kenny/K/SoapyRX888 && git add CMakeLists.txt
git commit -m "build: bump cmake_minimum_required to 3.10 (CMake 4.x removed <3.5 compat)

Fixes hard configure failure on Homebrew Apple Silicon:
  'Compatibility with CMake < 3.5 has been removed from CMake.'

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Replace the dead macOS CI with an arm64 build harness

**Why:** `SoapyRX888/.github/workflows/macOS.yml` uses removed runners (`macos-11/12/13`) and a likely-dead `brew tap cozycactus/tap`. We need an arm64 workflow that builds **our** `librx888` fork, installs it, then builds `SoapyRX888`. This is our self-serve compiler for the whole phase.

**Files:**
- Modify (overwrite): `/home/kenny/K/SoapyRX888/.github/workflows/macOS.yml`

- [ ] **Step 1: Overwrite the workflow**

```yaml
name: macOS CI (Apple Silicon)
on:
  push:
    branches: [ main, macos-arm64-resurrection ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:

jobs:
  build-arm64:
    name: macOS arm64 build
    runs-on: macos-15   # Apple Silicon
    permissions:
      contents: read
    steps:
      - name: Checkout SoapyRX888
        uses: actions/checkout@v4

      - name: Install dependencies
        run: brew install cmake pkg-config libusb soapysdr

      - name: Build & install librx888 (our fork)
        run: |
          git clone --depth 1 https://github.com/qoelet/librx888.git
          cmake -S librx888 -B librx888/build -DCMAKE_BUILD_TYPE=Release
          cmake --build librx888/build
          sudo cmake --install librx888/build

      - name: Configure SoapyRX888
        run: cmake -S . -B build -DCMAKE_BUILD_TYPE=Release

      - name: Build SoapyRX888
        run: cmake --build build

      - name: Show built module
        run: ls -l build && file build/*.so 2>/dev/null || true
```

NOTE: the `librx888` clone uses branch `main` of our fork; ensure Task 1/2 fixes are pushed to `librx888` `main` (or update the clone to `--branch <branch>`) before relying on CI. See Task 5.

- [ ] **Step 2: Validate the YAML parses**

Run:
```bash
cd /home/kenny/K/SoapyRX888 && python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/macOS.yml')); print('YAML OK')"
```
Expected: `YAML OK`

- [ ] **Step 3: Commit**

```bash
cd /home/kenny/K/SoapyRX888 && git add .github/workflows/macOS.yml
git commit -m "ci: arm64 macOS build harness; build our librx888 fork instead of dead brew tap

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Push both forks and trigger CI

**Why:** CI is the authoritative arm64 signal. librx888 fixes must be on the branch CI clones; SoapyRX888 branch push triggers the workflow.

**Files:** none (git operations)

- [ ] **Step 1: Push librx888 fixes**

```bash
cd /home/kenny/K/librx888 && git push origin HEAD
```
Expected: push succeeds to `git@github.com:qoelet/librx888`. (If Task 1/2 were committed on a non-default branch, either push to `main` or update Task 4's clone to that branch and re-commit.)

- [ ] **Step 2: Push SoapyRX888 branch**

```bash
cd /home/kenny/K/SoapyRX888 && git push -u origin macos-arm64-resurrection
```
Expected: push succeeds; GitHub Actions starts the macOS workflow.

- [ ] **Step 3: Watch the run**

```bash
cd /home/kenny/K/SoapyRX888 && gh run list --workflow "macOS CI (Apple Silicon)" --limit 1
gh run watch $(gh run list --workflow "macOS CI (Apple Silicon)" --limit 1 --json databaseId -q '.[0].databaseId')
```
Expected: green. If red, read the log, fix, re-push — iterate until green.

---

## Phase 1 exit criteria

- arm64 macOS CI is green (both repos build).
- On the user's Mac: `SoapySDRUtil --info` lists the `rx888` module without error (manual check, user-run).

## Follow-on (separate plans, after Phase 1 green)

- **Phase 2 plan** — FX3 firmware loading: source + bundle SDDC blob (record URL + SHA-256), add bootloader PID `0x04b4:0x00f3`, implement Cypress RAM download (vendor request `0xA0`), wait for re-enumeration to `0x00f1`, run on every `rx888_open`. Gated on the user's `system_profiler SPUSBDataType` USB-state check.
- **Phase 3 plan** — streaming into gqrx: USB3 async buffer tuning, `STARTADC` init ordering, real-sample (Q=0) handling. Requires hardware loop with user.
