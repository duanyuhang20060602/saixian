# K2 blue-victory mode (supersedes the earlier A/B battle animation)

## Split-title revision

The Chinese title now enters as three diagonal screen-space slices with
staggered left/right offsets (frames 90, 98, 106). All offsets settle to zero;
the final title remains complete and legible. The background is three separated
slanted plates rather than a full-width rectangle. This is an original
Apex-inspired treatment, not an exact reproduction.
The vertical title baseline is fixed to keep the ROM address path short.
The original K2 PLAY/HOLD/return behavior and HMI filter adaptation are retained.
tests/tb_victory_slice.v checks staggered motion and settled offsets and exports
doc/hmi_ui/blue_victory_slice_entry.ppm; the existing blue-victory test checks HOLD.
Timing/resource numbers below describe the earlier unsplit revision; consult
src/td_project/final_timing.rpt for current build signoff.

Updated: 2026-09-22.

- Boot retains the existing automatic carousel. K2 no longer means previous image.
- K2 in carousel mode (outside settings) queues the blue-victory scene at a frame boundary.
- During battle, the scene replaces all incoming carousel/OSD pixels. Automatic image changes and BGM playback are disabled; new match starts are blocked.
- Existing SD transfers finish normally. SDRAM refresh, framebuffer scanout and HDMI timing remain running. This is exclusive presentation, not dynamic FPGA resource reallocation.
- The 360-frame scene contains a match-ended introduction, blue diagonal wipe, shield emblem, antialiased Chinese victory title, and one sheen pass. There is no red team, opponent, cross, or fragmentation.
- Repeated K2 presses during PLAY are ignored (including the final PLAY frame). At completion the module enters HOLD and freezes animation counters. Carousel and BGM remain disabled indefinitely.
- A fresh K2 press in HOLD returns to carousel at a frame boundary. The carousel interval restarts rather than preserving its partial timer. Reset always returns to idle.
- Typography uses a generated 512x128 2bpp atlas (four additional 32K BRAMs). Rebuild with doc/tools/generate_victory_atlas.py; MIF is for synthesis, HEX is for simulation. Existing project OSD font assets are unchanged.

## Verification

Tang Dynasty full synthesis, placement, routing and bit generation completed.
Final blue-victory rebuild: setup WNS +0.195 ns; hold WNS +0.003 ns; STA coverage 99.95%.
Resources: 13234 / 19600 LUTs, 6981 registers, 22 BRAM9K, 5 BRAM32K, 2 DSPs.
Changed RTL passes scoped git diff --check (line-ending warnings only).

Bitstream: `src/td_project/HDMI1.4b_Transmitter_v1.0.bit`.
Icarus RTL simulation passes reset, RGB/sync passthrough, queued and same-cycle start, ignored PLAY presses, 360-frame completion, 600 further frames of HOLD, frame-aligned K2 return, and replay. Testbench: tests/tb_blue_victory.v.
Simulation commands (run from project root):

    iverilog -g2012 -DVICTORY_SIM -s tb_blue_victory -o tests/blue_victory.vvp tests/tb_blue_victory.v src/user_source/hdl_source/saixian_battle_result_fx_pipelined.v
    vvp tests/blue_victory.vvp

The test exports doc/hmi_ui/blue_victory_rtl.ppm. A PNG conversion is provided alongside it.
Not programmed or visually validated on hardware in this revision. Simulation uses a behavioral synchronous atlas ROM; HDMI PHY and physical keys still require hardware acceptance. Browser preview is a visual reference, not a pixel-identical promise.

## Hardware acceptance

1. Boot and confirm automatic image cycling and ordinary controls.
2. Press K2 mid-carousel: confirm a clean full-screen scene with no OSD or spectrum showing through, and no background music.
3. Confirm blue-only scene, shield, diagonal wipe, Chinese title and sheen; watch for timing/pixel alignment defects.
4. Repeatedly press K2 during playback: it must not restart the scene.
5. After roughly six seconds, confirm the final screen stays indefinitely and shows the K2 return prompt.
6. Press K2 again: confirm carousel/BGM recover. Press K2 once more to repeat the animation.
