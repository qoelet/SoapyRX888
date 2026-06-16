# RX888 MkII on macOS (Apple Silicon) — Driver Resurrection Design

**Date:** 2026-06-17
**Author:** Kenny Shen (with Claude Code)
**Status:** Draft — awaiting review
**Goal:** Receive HF in **gqrx** on an Apple Silicon Mac using an **RX888 MkII**, via the SoapySDR stack (`SoapyRX888` → `librx888` → libusb).

## Background

Two forked repos under `qoelet`:

- `SoapyRX888` (`/home/kenny/K/SoapyRX888`) — thin SoapySDR wrapper. ~600 lines of glue translating SoapySDR API calls into `rx888_*()`. No hardware code.
- `librx888` (`/home/kenny/K/librx888`) — the engine. C, based on librtlsdr. Talks to hardware over libusb.

The RX888 MkII hardware path: **LTC2208 16-bit ADC → Cypress/Infineon EZ-USB FX3 (CYUSB3014) GPIF II → USB3 bulk endpoint 0x81 → host (libusb)**. The FX3 is a vendor-class USB device requiring **no kernel driver on any OS**; macOS drives it entirely through libusb. The hardware path is therefore macOS-compatible (SDR++ already proves this). The blocker is abandoned software, not silicon.

## Hard constraint (shapes the whole plan)

Development happens on a **Linux box with no RX888 attached**. We cannot run the driver against hardware locally. Therefore:

- **Build correctness** is verified two ways without the user's Mac:
  1. Local gcc build (libusb 1.0.27 installed) — fast inner loop.
  2. **arm64 macOS GitHub Actions CI** (`macos-14`/`macos-15` runners are Apple Silicon) — authoritative clang/arm64 signal that we can read ourselves.
- **Hardware behavior** (detection, streaming) is verified only by the user on their Mac, in a tight iterative loop: we change code → user builds & runs → user pastes output → repeat.

This is what makes the mission tractable: ~90% (everything up to "samples actually flow") is self-verifiable via CI; only the final streaming validation needs the physical device.

## Confirmed findings

### Bug #1 — build killer (CONFIRMED on this machine)
`SoapyRX888/CMakeLists.txt:5` → `cmake_minimum_required(VERSION 2.8.12)`. Current Homebrew CMake is 4.x, which hard-errors on `< 3.5`. Reproduced locally with CMake 4.3.2:
```
CMake Error at CMakeLists.txt:5 (cmake_minimum_required):
  Compatibility with CMake < 3.5 has been removed from CMake.
```
This is the user's reported build failure.

### Bug #2 — warning-as-error fragility (compiler-specific; CI will confirm)
`librx888/CMakeLists.txt:16` → `-std=c11 -pedantic-errors -Wall -Wextra -Werror`. Builds **clean on gcc 13**, but `-Werror` makes the build hostage to Apple clang's differing default warnings (e.g. signed/unsigned comparisons at `librx888.c:380`, `rx888_rec.c:105`). May or may not bite; we harden defensively and let CI arbitrate.

### Bug #3 — no firmware loader (the real reason it "doesn't work")
`librx888.c:103` knows only `0x04b4:0x00f1` (post-firmware). The MkII FX3 boots with empty RAM as bootloader `0x04b4:0x00f3`. **No firmware upload code exists.** Without it, gqrx finds nothing even after a clean build.

## Approach (chosen)

Resurrect the SoapySDR stack (gqrx target). Fix both repos; add firmware loading; use macOS CI as the build harness.

**Note on SDR++ (verified 2026-06-17):** SDR++ has **no native RX888 source module** — confirmed absent from its `CMakeLists.txt` and community threads. The only way the RX888 reaches SDR++/CubicSDR/etc. on macOS is **through SoapySDR**, i.e. this exact stack. So fixing `SoapyRX888` is not gqrx-only; it is the single bridge for the whole SoapySDR app ecosystem on macOS. There is no easier shortcut to abandon this for.

**Reference to mine in Phase 2:** a NextGenSDRs/groups.io thread ("A Soapy driver for the RX888 has been written for MacOS") and the SDDC_FX3 firmware loader — both potential reference implementations for the FX3 firmware-upload sequence.

Rejected alternative: rewrite the Soapy module from scratch dropping librx888 — held only as an escape hatch if librx888 internals prove unsalvageable.

## Phased design

### Phase 1 — Make it build (CI-verified, no hardware)

**librx888 changes:**
- Keep `cmake_minimum_required` ≥ 3.10 (already done).
- Make warning flags non-fatal across compilers: drop `-Werror`/`-pedantic-errors` from the default build (or gate behind a `RX888_STRICT` option, off by default). Keep `-Wall -Wextra` as warnings.
- Ensure libusb include dirs propagate to the `rx888_test` / `rx888_rec` executables (they `#include` library headers but only link `${LIBUSB_LINK_LIBRARIES}`, not `PkgConfig::LIBUSB`). On Homebrew arm64, libusb headers live under `/opt/homebrew/.../include/libusb-1.0/`.
- Confirm `librtlsdr`-style `rt` linkage stays Apple-excluded (already handled in `src/CMakeLists.txt:34`).

**SoapyRX888 changes:**
- Bump `cmake_minimum_required` to a modern floor (e.g. `3.10`).
- Verify `FindRX888.cmake` locates the librx888 we build/install (pkg-config `librx888` + `/opt/homebrew` paths).

**CI:**
- Replace the dead `macOS.yml` (depends on a likely-dead `brew tap cozycactus/tap`, uses removed `macos-11/12/13` runners) with an arm64 workflow on `macos-14`/`macos-15` that: installs `libusb soapysdr cmake` via Homebrew, builds **our** `librx888` from the sibling fork (not the tap), installs it, then builds `SoapyRX888` against it.
- **Provenance note:** CI must build the *fork we control*. Decide at implementation time whether to reference it via a pinned git URL or a vendored submodule.

**Phase 1 exit criteria:** CI green on arm64 macOS; on the user's Mac, `SoapySDRUtil --info` lists the `rx888` module without error.

### Phase 2 — Make it detect (firmware loading)

**Firmware sourcing (decision: bundle the blob):**
- Vendor the **RX888 MkII FX3 firmware** image into `librx888` (matches the `STARTFX3`/`STARTADC`/`STOPFX3`/`GPIOFX3`/`R820T2STDBY` vendor command set already in `librx888.c:45`, which is the SDDC firmware command protocol).
- Source from the official **SDDC_FX3 / ExtIO_sddc** GPLv3 release. **Record the exact source URL and SHA-256** of the committed blob in the repo (e.g. `firmware/PROVENANCE.md`) so the user can independently verify what is being flashed. License compatible (librx888 is GPLv2+).
- Embed as a C byte array (generated header) so no runtime file dependency.

**Loader implementation in librx888:**
- Add bootloader PID `0x04b4:0x00f3` to recognition.
- Implement FX3 RAM download via the Cypress vendor protocol (control request `0xA0`): parse the firmware image format (CYFX `CY`-signature sections of `{length, address, data}` terminating with an entry-point transfer), upload in chunks, trigger execution.
- After upload, wait for re-enumeration to `0x04b4:0x00f1` (poll with timeout; FX3 re-enumerates in ~1–2 s), then open the application device as today.
- `rx888_open` (and/or device enumeration) gains: detect state → if bootloader, upload firmware + wait → proceed.

**First step of Phase 2 (user, 30 s):** plug RX888 into the Mac, run `system_profiler SPUSBDataType` (or check System Information → USB) and report what appears — confirms whether the Mac sees `0x04b4:0x00f3`, `0x00f1`, or nothing. Establishes the starting USB state empirically.

**Phase 2 exit criteria:** on the user's Mac, plug in → `SoapySDRUtil --find` lists the RX888 (firmware auto-loaded).

### Phase 3 — Make it stream (user hardware loop)

- User runs gqrx with the `rx888` SoapySDR device; we debug streaming together.
- Anticipated work: USB3 async-transfer buffer tuning for sustained throughput on macOS (`xfer_buf_num` / `xfer_buf_len`), sample-rate/`STARTADC` init ordering (`librx888.c:443` sends `STARTADC` with sample_rate `0` at open), and verifying the S16/CF32 conversion in `Streaming.cpp:314`.
- **Phase 3 exit criteria (mission success):** HF band audible/visible in gqrx on the Mac.

## Out of scope

- VHF/UHF via the R820T2 tuner (HF direct-sampling first; tuner path is a later enhancement).
- Windows / Intel-Mac support (Apple Silicon is the target; we avoid *breaking* others but don't actively test them).
- Frequency-correction, advanced gain modes, TX (device is RX-only).

## Risks

- **Apple clang surprises** beyond Bug #2 — mitigated by CI as authoritative arm64 signal.
- **Firmware blob mismatch** — wrong/incompatible image bricks detection; mitigated by sourcing from the canonical SDDC release matching librx888's command set, and recording provenance/hash.
- **USB3 throughput on macOS** — the genuine unknown; isolated to Phase 3 and tunable.
- **librx888 internals unsalvageable** — escape hatch: rewrite the Soapy module to do firmware-load + libusb streaming directly.
