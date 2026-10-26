# Hardware status (2026-10-26)

The user reports that the title still displays the original text after flashing both matching A/B firmware images and using a 2048-byte TITLE2.BIN. This upload preserves that revision; the hardware issue has not been fixed and its root cause is not confirmed.

The local example passes all four SXTTL002 record CRC32 checks. Pending hardware checks include the SD configuration's physical sector placement, scanning and validation, and font transfer between boards. A missing or invalid configuration falls back to the original text. The file must physically reside within the first 512 MiB of the SD card; placing it in the root directory does not establish this.

Passing simulation and place-and-route results do not constitute hardware acceptance of the reported title behavior. A pre-existing audio regression failure is documented separately. No files were deleted and the user's SD card was not modified.
