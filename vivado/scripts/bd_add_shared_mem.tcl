# ============================================================================
# 在**已打开的**官方基线 BD 上增加 PS/PL 共享内存。
#
# 用法（BD 必须先 open_bd_design）：
#     source bd_add_shared_mem.tcl
#     bd_add_shared_memory extend      ;# 或 insert
#
# 增加的内容（照只读参考工程 PQM/FPGA/scripts/create_pqm_ps_bd.tcl 的接法）：
#   axi_bram_ctrl_0        xilinx.com:ip:axi_bram_ctrl:4.1
#                          DATA_WIDTH=32、SINGLE_PORT_BRAM=1
#   blk_mem_gen_shared     xilinx.com:ip:blk_mem_gen:8.4
#                          True_Dual_Port_RAM、32bit 宽、16384 深、
#                          Enable_B=Use_ENB_Pin、字节写使能、Byte_Size=8
#   axi_bram_ctrl_0/BRAM_PORTA <-> blk_mem_gen_shared/BRAM_PORTA
#   blk_mem_gen_shared/BRAM_PORTB -> BD 外部接口端口 PL_SHARED_BRAM
#   PS 地址空间 /processing_system7_0/Data 里分配 0x40000000 / 64K
#
# 两个挂 AXI 的模式：
#   extend —— 把 ps7_0_axi_periph 的 NUM_MI 由 4 扩到 5，新 MI 接 BRAM 控制器。
#             改动最小，但要 Vivado 接受对 interconnect 层级直接改 NUM_MI。
#   insert —— 在 PS M_AXI_GP0 与 ps7_0_axi_periph/S00_AXI 之间插一个
#             NUM_SI=1/NUM_MI=2 的普通 axi_interconnect，一路给原互联，一路给
#             BRAM 控制器。参考工程的 axi_interconnect_ctrl 就是这种普通互联。
#
# 幂等：blk_mem_gen_shared 已存在时直接返回。
# ============================================================================

proc bd_add_shared_memory {mode} {
    if {[llength [get_bd_cells -quiet blk_mem_gen_shared]] > 0} {
        puts "BD-SHM: blk_mem_gen_shared 已存在，跳过增补"
        return 1
    }

    puts "BD-SHM: 模式 = $mode"

    # ---------------- 1. 共享内存本体 ----------------
    set shared_bram [create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 blk_mem_gen_shared]
    set_property -dict [list \
        CONFIG.Memory_Type            {True_Dual_Port_RAM} \
        CONFIG.Write_Width_A          {32} \
        CONFIG.Read_Width_A           {32} \
        CONFIG.Write_Depth_A          {16384} \
        CONFIG.Write_Width_B          {32} \
        CONFIG.Read_Width_B           {32} \
        CONFIG.Enable_B               {Use_ENB_Pin} \
        CONFIG.Use_Byte_Write_Enable  {true} \
        CONFIG.Byte_Size              {8} \
    ] $shared_bram
    puts "BD-SHM: blk_mem_gen_shared 已创建"

    # ---------------- 2. AXI BRAM 控制器 ----------------
    set bram_ctrl [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_bram_ctrl_0]
    set_property -dict [list CONFIG.DATA_WIDTH {32} CONFIG.SINGLE_PORT_BRAM {1}] $bram_ctrl
    puts "BD-SHM: axi_bram_ctrl_0 已创建"

    # ---------------- 3. 控制器 BRAM 口 <-> 共享内存 PORTA ----------------
    connect_bd_intf_net [get_bd_intf_pins $bram_ctrl/BRAM_PORTA] \
                        [get_bd_intf_pins $shared_bram/BRAM_PORTA]

    # ---------------- 4. PORTB 引出为 BD 外部接口端口 ----------------
    set shm_port [create_bd_intf_port -mode Slave \
                      -vlnv xilinx.com:interface:bram_rtl:1.0 PL_SHARED_BRAM]
    catch {
        set_property -dict [list \
            CONFIG.MASTER_TYPE  {BRAM_CTRL} \
            CONFIG.MEM_SIZE     {8192} \
            CONFIG.MEM_WIDTH    {32} \
            CONFIG.READ_LATENCY {1} \
        ] $shm_port
    }
    connect_bd_intf_net $shm_port [get_bd_intf_pins $shared_bram/BRAM_PORTB]
    puts "BD-SHM: PL_SHARED_BRAM 外部端口已引出"

    # ---------------- 5. AXI 挂接 ----------------
    set clk_pin   [get_bd_pins processing_system7_0/FCLK_CLK0]
    set rst_pin   [get_bd_pins rst_ps7_0_100M/peripheral_aresetn]

    if {$mode eq "extend"} {
        set periph [get_bd_cells ps7_0_axi_periph]
        set_property -dict [list CONFIG.NUM_MI {5}] $periph

        set m04 [get_bd_intf_pins -quiet $periph/M04_AXI]
        if {[llength $m04] == 0} {
            error "BD-SHM: 扩 NUM_MI 后没有出现 ps7_0_axi_periph/M04_AXI，extend 模式不成立"
        }
        connect_bd_intf_net $m04 [get_bd_intf_pins $bram_ctrl/S_AXI]
        foreach p {M04_ACLK M04_ARESETN} {
            if {[llength [get_bd_pins -quiet $periph/$p]] == 0} {
                error "BD-SHM: 缺少 $periph/$p"
            }
        }
        connect_bd_net $clk_pin [get_bd_pins $periph/M04_ACLK]
        connect_bd_net $rst_pin [get_bd_pins $periph/M04_ARESETN]
        puts "BD-SHM: ps7_0_axi_periph NUM_MI=5，M04_AXI -> axi_bram_ctrl_0/S_AXI"
    } else {
        # insert：普通 2-MI 互联插在 PS GP0 与原互联之间
        set ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_periph_shm]
        set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] $ic

        # 断开 PS M_AXI_GP0 -> ps7_0_axi_periph/S00_AXI
        set old_net [get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins processing_system7_0/M_AXI_GP0]]
        if {[llength $old_net] > 0} { delete_bd_objs $old_net }

        connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] [get_bd_intf_pins $ic/S00_AXI]
        connect_bd_intf_net [get_bd_intf_pins $ic/M00_AXI] [get_bd_intf_pins ps7_0_axi_periph/S00_AXI]
        connect_bd_intf_net [get_bd_intf_pins $ic/M01_AXI] [get_bd_intf_pins $bram_ctrl/S_AXI]

        connect_bd_net $clk_pin [get_bd_pins $ic/ACLK] [get_bd_pins $ic/S00_ACLK] \
                                [get_bd_pins $ic/M00_ACLK] [get_bd_pins $ic/M01_ACLK]
        connect_bd_net $rst_pin [get_bd_pins $ic/ARESETN] [get_bd_pins $ic/S00_ARESETN] \
                                [get_bd_pins $ic/M00_ARESETN] [get_bd_pins $ic/M01_ARESETN]
        puts "BD-SHM: 已插入 axi_periph_shm（NUM_SI=1 NUM_MI=2）"
    }

    connect_bd_net $clk_pin [get_bd_pins $bram_ctrl/s_axi_aclk]
    connect_bd_net $rst_pin [get_bd_pins $bram_ctrl/s_axi_aresetn]

    # ---------------- 6. 地址分配 ----------------
    assign_bd_address -target_address_space [get_bd_addr_spaces processing_system7_0/Data] \
        -offset 0x40000000 -range 64K \
        [get_bd_addr_segs $bram_ctrl/S_AXI/Mem0] -force
    puts "BD-SHM: 地址 0x40000000 / 64K 已分配"

    regenerate_bd_layout
    puts "BD-SHM: 增补完成"
    return 1
}
