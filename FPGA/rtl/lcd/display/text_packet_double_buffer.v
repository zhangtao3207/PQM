/*
 * 模块: text_packet_double_buffer
 * 功能:
 *   在 wave_clk 域写入完整文字结果包，在 lcd_pclk 域按帧边界切换前台显示 bank。
 *   跨时钟域仅同步单 bit 的提交与应答控制，避免宽总线直接跨域采样。
 */
module text_packet_double_buffer #(
    parameter integer PACKET_WIDTH = 339
)(
    input                         wave_clk,
    input                         lcd_pclk,
    input                         rst_n,
    input      [PACKET_WIDTH-1:0] packet_in_wave,
    input                         packet_commit_toggle_wave,
    input                         frame_edge_lcd,
    output reg                    lcd_swap_ack_toggle,
    output reg                    packet_pending_lcd,
    output reg [PACKET_WIDTH-1:0] packet_front_lcd
);

reg [PACKET_WIDTH-1:0] packet_buf0;
reg [PACKET_WIDTH-1:0] packet_buf1;

reg                    packet_commit_toggle_d1_wave;
reg                    packet_ready_toggle_wave;
reg                    write_bank_wave;
reg                    pending_bank_wave;
reg                    packet_inflight_wave;
reg                    ack_toggle_sync1_wave;
reg                    ack_toggle_sync2_wave;
reg                    ack_toggle_sync3_wave;

reg                    packet_ready_sync1_lcd;
reg                    packet_ready_sync2_lcd;
reg                    packet_ready_sync3_lcd;
reg                    pending_bank_sync1_lcd;
reg                    pending_bank_sync2_lcd;
reg                    packet_bank_pending_lcd;

wire commit_edge_wave;
wire ack_edge_wave;
wire packet_ready_update_lcd;

assign commit_edge_wave        = packet_commit_toggle_wave ^ packet_commit_toggle_d1_wave;
assign ack_edge_wave           = ack_toggle_sync2_wave ^ ack_toggle_sync3_wave;
assign packet_ready_update_lcd = packet_ready_sync2_lcd ^ packet_ready_sync3_lcd;

always @(posedge wave_clk or negedge rst_n) begin
    if (!rst_n) begin
        packet_buf0                  <= {PACKET_WIDTH{1'b0}};
        packet_buf1                  <= {PACKET_WIDTH{1'b0}};
        packet_commit_toggle_d1_wave <= 1'b0;
        packet_ready_toggle_wave     <= 1'b0;
        write_bank_wave              <= 1'b1;
        pending_bank_wave            <= 1'b0;
        packet_inflight_wave         <= 1'b0;
        ack_toggle_sync1_wave        <= 1'b0;
        ack_toggle_sync2_wave        <= 1'b0;
        ack_toggle_sync3_wave        <= 1'b0;
    end else begin
        packet_commit_toggle_d1_wave <= packet_commit_toggle_wave;
        ack_toggle_sync1_wave        <= lcd_swap_ack_toggle;
        ack_toggle_sync2_wave        <= ack_toggle_sync1_wave;
        ack_toggle_sync3_wave        <= ack_toggle_sync2_wave;

        if (ack_edge_wave)
            packet_inflight_wave <= 1'b0;

        if (commit_edge_wave && !packet_inflight_wave) begin
            if (write_bank_wave)
                packet_buf1 <= packet_in_wave;
            else
                packet_buf0 <= packet_in_wave;

            pending_bank_wave        <= write_bank_wave;
            packet_ready_toggle_wave <= ~packet_ready_toggle_wave;
            write_bank_wave          <= ~write_bank_wave;
            packet_inflight_wave     <= 1'b1;
        end
    end
end

always @(posedge lcd_pclk or negedge rst_n) begin
    if (!rst_n) begin
        packet_ready_sync1_lcd  <= 1'b0;
        packet_ready_sync2_lcd  <= 1'b0;
        packet_ready_sync3_lcd  <= 1'b0;
        pending_bank_sync1_lcd  <= 1'b0;
        pending_bank_sync2_lcd  <= 1'b0;
        packet_bank_pending_lcd <= 1'b0;
        packet_pending_lcd      <= 1'b0;
        packet_front_lcd        <= {PACKET_WIDTH{1'b0}};
        lcd_swap_ack_toggle     <= 1'b0;
    end else begin
        packet_ready_sync1_lcd <= packet_ready_toggle_wave;
        packet_ready_sync2_lcd <= packet_ready_sync1_lcd;
        packet_ready_sync3_lcd <= packet_ready_sync2_lcd;
        pending_bank_sync1_lcd <= pending_bank_wave;
        pending_bank_sync2_lcd <= pending_bank_sync1_lcd;

        if (packet_ready_update_lcd) begin
            packet_bank_pending_lcd <= pending_bank_sync2_lcd;
            packet_pending_lcd      <= 1'b1;
        end

        if (packet_pending_lcd && frame_edge_lcd) begin
            if (packet_bank_pending_lcd)
                packet_front_lcd <= packet_buf1;
            else
                packet_front_lcd <= packet_buf0;

            packet_pending_lcd  <= 1'b0;
            lcd_swap_ack_toggle <= ~lcd_swap_ack_toggle;
        end
    end
end

endmodule
