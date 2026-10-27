# Hardware status (2026-10-27)

Current release: preserve-functions-optimized-20261027. HMI command formatting runs on B; A relays verified chunks. Both boards use 230400 for their control UART and must be updated as a pair. The HMI UART remains 115200. Existing SD assets and TITLE2.BIN remain compatible.

The title/ticker, blank center label, startup scan/font gates, pointer effects and music-picture synchronization are retained. See releases/preserve_functions_optimized_20261027 for current resource, routed timing and simulation evidence. Physical hardware acceptance and actual SD/image latency measurements are pending.

Historical startup stall and baseline audio regression reports remain in earlier release records; this release does not claim to have reproduced or resolved every historical hardware symptom.
