<Project Version="3" Minor="2" Path="C:/Users/MR.HUSKY/Desktop/qian/saixian-dual-photo/dual_photo_720_link6m25_read_align/projects/board_b/src/td_project">
    <Project_Created_Time />
    <TD_Version>6.2.168116</TD_Version>
    <Name>PHOTO_BOARD_B</Name>
    <HardWare>
        <Family>EG4</Family>
        <Device>EG4S20BG256</Device>
        <Speed />
    </HardWare>
    <MiscSettings>
        <Setting Key="farm" Val="disable" />
    </MiscSettings>
    <Source_Files><Verilog>
<File Path="../user_source/hdl_source/SD/frame_read_write.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="1" /></FileInfo></File><File Path="../user_source/hdl_source/SD/frame_fifo_read.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="2" /></FileInfo></File><File Path="../user_source/hdl_source/SD/frame_fifo_write.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="3" /></FileInfo></File><File Path="../user_source/hdl_source/SD/sdram.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="4" /></FileInfo></File><File Path="../user_source/hdl_source/IP/sys_pll.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="5" /></FileInfo></File><File Path="../user_source/hdl_source/IP/afifo_16_32_256.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="6" /></FileInfo></File><File Path="../user_source/hdl_source/IP/afifo_32_16_256.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="7" /></FileInfo></File><File Path="../user_source/hdl_source/include/global_def.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="8" /></FileInfo></File><File Path="../user_source/hdl_source/include/sdr_as_ram.enc.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="9" /></FileInfo></File><File Path="../user_source/hdl_source/include/sdr_init_ref.enc.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="10" /></FileInfo></File><File Path="../user_source/hdl_source/include/sdr_wrrd.enc.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="11" /></FileInfo></File><File Path="../user_source/hdl_source/frame_store.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="12" /></FileInfo></File><File Path="../user_source/hdl_source/dual_still_reset_sync.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="13" /></FileInfo></File><File Path="../user_source/hdl_source/builtin_link_pll.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="14" /></FileInfo></File><File Path="../../../../common/photo_uart.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="15" /></FileInfo></File><File Path="../../../../common/photo_link.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="16" /></FileInfo></File><File Path="../../../../common/photo_control.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="17" /></FileInfo></File><File Path="../../../../common/photo_status.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="18" /></FileInfo></File><File Path="../../../../common/top_photo_b.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="19" /></FileInfo></File><File Path="../../../../common/photo_sd_cache.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="20" /></FileInfo></File><File Path="../../../../common/photo_processing.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="21" /></FileInfo></File><File Path="../../../../common/photo_b_processing.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="22" /></FileInfo></File><File Path="../../../../common/photo_audio_link.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="23" /></FileInfo></File><File Path="../../../../common/photo_sd_audio_stream.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="24" /></FileInfo></File><File Path="../../../../common/photo_sd/bmp_read.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="25" /></FileInfo></File><File Path="../../../../common/photo_sd/saixian_media_header.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="26" /></FileInfo></File><File Path="../../../../common/photo_sd/sd_card_cmd.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="27" /></FileInfo></File><File Path="../../../../common/photo_sd/sd_card_sec_read_write.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="28" /></FileInfo></File><File Path="../../../../common/photo_sd/sd_card_top.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="29" /></FileInfo></File><File Path="../../../../common/photo_sd/spi_master.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="30" /></FileInfo></File></Verilog></Source_Files>
    <FileSets>
        <FileSet Name="design_1" Type="DesignFiles">
        </FileSet>
        <FileSet Name="constraint_1" Type="ConstrainFiles">
        </FileSet>
    </FileSets>
    <TOP_MODULE>
        <LABEL>top_photo_b</LABEL>
        <MODULE>top_photo_b</MODULE>
        <CREATEINDEX>user</CREATEINDEX>
    </TOP_MODULE>
    <Property>
    </Property>
    <Device_Settings>
    </Device_Settings>
    <Configurations>
    </Configurations>
    <Runs>
        <Run Name="syn_1" Type="Synthesis" ConstraintSet="constraint_1" Description="" Active="true">
            <Strategy Name="Default_Synthesis_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="phy_1" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_1" Active="true">
            <Strategy Name="Default_PhysicalDesign_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
    </Runs>
    <Project_Settings>
    </Project_Settings>
</Project>