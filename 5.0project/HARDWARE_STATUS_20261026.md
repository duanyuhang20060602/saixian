# Hardware status (2026-10-26)

The user reported that the previous complete-scan revision stayed on FONT3/3 for over five minutes. A deterministic simulation reproduces a circular wait: silent audio preload fills the A FIFO, ordinary SPI exchanges stop, and late B scan completion never updates A's music catalog status. This revision keeps status-only A8 queries active while held, buffered and waiting for scan completion. No PCM is consumed or overwritten. Real boot-screen exit and the first audible sample are checked at the actual 2048-frame capacity. Hardware confirmation remains pending.

The user confirmed that the top-left title changes after a startup delay and that the center label remained fixed. This revision keeps the loading screen visible until full catalog scanning and A-board font publication/acknowledgement finish. Missing custom text stays blank. During carousel playback, the center label now shares the top-left title; competition state labels remain controlled by the event state machine.

The startup bar uses PHOTO1/3, MUSIC2/3 and FONT3/3 milestones, with blank labels for confirmed missing resources. The moving white highlight is removed; the rotating dots and existing photo effects remain. Autoplay starts after loading exits.

Color ripple and circular portal transitions snapshot the existing pointer position at each transition's start. Moving the pointer during a transition changes the next transition's origin. Other directional/partitioned effects retain their geometry. No USB mouse driver is added.

Matching A and B firmware must both be updated. Existing 2048-byte TITLE2.BIN, photo, music and trophy assets remain compatible, including the existing first-512-MiB scan requirement. Passing simulation and place-and-route results are recorded in releases/boot_catalog_poll_20261026. Hardware acceptance remains pending. The documented pre-existing audio regression failure has not been fixed. No files were deleted and the user's SD card was not modified.
