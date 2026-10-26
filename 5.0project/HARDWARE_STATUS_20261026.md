# Hardware status (2026-10-26)

The user reports that the title still displays the original text after flashing both matching A/B firmware images and using a 2048-byte TITLE2.BIN. This upload preserves that revision; the hardware issue has not been fixed and its root cause is not confirmed.

Follow-up: the user confirmed that the bottom ticker changes while the top-left title appears unchanged. The previously supplied example used `100米`, which is also the default project title. The replacement example uses `标题测试` and `底部独立文字` to make both changes distinguishable. This explains an unchanged appearance when using the old example; it does not establish the cause for any other user-generated configuration.

A new integration regression passes the generated four SD records through the real A/B UART controllers, both banks of the supplier RAM model, and the real OSD. All 512 font rows and 10,240 independently expected output pixels match, including the top-left title. No FPGA RTL, constraints or firmware images changed. The generator prompts and save summary now identify both display locations explicitly. Hardware confirmation using the replacement example remains pending.

The local example passes all four SXTTL002 record CRC32 checks. Pending hardware checks include the SD configuration's physical sector placement, scanning and validation, and font transfer between boards. A missing or invalid configuration falls back to the original text. The file must physically reside within the first 512 MiB of the SD card; placing it in the root directory does not establish this.

Passing simulation and place-and-route results do not constitute hardware acceptance of the reported title behavior. A pre-existing audio regression failure is documented separately. No files were deleted and the user's SD card was not modified.
