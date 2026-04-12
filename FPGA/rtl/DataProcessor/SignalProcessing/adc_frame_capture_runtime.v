`timescale 1ns / 1ps

/*
 * Module: adc_frame_capture_runtime
 * Purpose:
 *   Capture a runtime-configurable frame of ADC samples into a ping-pong buffer.
 *   One bank is written by the front end while the other bank can be read back.
 *
 * Notes:
 *   - frame_samples_n is a runtime input, not a fixed parameter.
 *   - frame_samples_n is clamped into [1, MAX_FRAME_SAMPLES - 1].
 *   - The read port is synchronous so Vivado can infer block RAM cleanly.
 */
module adc_frame_capture_runtime #(
    parameter integer DATA_WIDTH        = 32,
    parameter integer MAX_FRAME_SAMPLES = 4096,
    parameter integer ADDR_WIDTH        = (MAX_FRAME_SAMPLES <= 2) ? 2 : $clog2(MAX_FRAME_SAMPLES)
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire [ADDR_WIDTH-1:0]     frame_samples_n,
    input  wire                      sample_valid,
    input  wire [DATA_WIDTH-1:0]     sample_data,
    input  wire                      rd_en,
    input  wire                      rd_bank,
    input  wire [ADDR_WIDTH-1:0]     rd_addr,
    output reg                       frame_ready,
    output reg                       ready_bank,
    output reg  [ADDR_WIDTH-1:0]     ready_sample_count,
    output reg                       wr_bank_active,
    output reg  [ADDR_WIDTH-1:0]     wr_addr_active,
    output wire [DATA_WIDTH-1:0]     rd_data
);

localparam integer TOTAL_SAMPLES  = (MAX_FRAME_SAMPLES << 1);
localparam integer MEM_ADDR_WIDTH = (TOTAL_SAMPLES <= 2) ? 2 : $clog2(TOTAL_SAMPLES);
localparam [ADDR_WIDTH-1:0] MAX_FRAME_SAMPLES_CONST = MAX_FRAME_SAMPLES - 1;

(* ram_style = "block" *) reg [DATA_WIDTH-1:0] frame_mem [0:TOTAL_SAMPLES-1];

reg  [ADDR_WIDTH-1:0] frame_sample_target;
reg  [DATA_WIDTH-1:0] rd_data_reg;
wire [MEM_ADDR_WIDTH-1:0] wr_mem_addr;
wire [MEM_ADDR_WIDTH-1:0] rd_mem_addr;
wire [ADDR_WIDTH-1:0]     frame_samples_clamped;
wire [ADDR_WIDTH-1:0]     frame_sample_target_now;

assign frame_samples_clamped =
    (frame_samples_n == {ADDR_WIDTH{1'b0}}) ? {{(ADDR_WIDTH - 1){1'b0}}, 1'b1} :
    (frame_samples_n > MAX_FRAME_SAMPLES_CONST) ? MAX_FRAME_SAMPLES_CONST :
                                                  frame_samples_n;

assign frame_sample_target_now = (wr_addr_active == {ADDR_WIDTH{1'b0}}) ?
                                 frame_samples_clamped :
                                 frame_sample_target;

assign wr_mem_addr = wr_bank_active ? (MAX_FRAME_SAMPLES + wr_addr_active) : wr_addr_active;
assign rd_mem_addr = rd_bank        ? (MAX_FRAME_SAMPLES + rd_addr)        : rd_addr;
assign rd_data     = rd_data_reg;

always @(posedge clk) begin
    if (sample_valid)
        frame_mem[wr_mem_addr] <= sample_data;
end

always @(posedge clk) begin
    if (rd_en)
        rd_data_reg <= frame_mem[rd_mem_addr];
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        frame_ready         <= 1'b0;
        ready_bank          <= 1'b0;
        ready_sample_count  <= {{(ADDR_WIDTH - 1){1'b0}}, 1'b1};
        wr_bank_active      <= 1'b0;
        wr_addr_active      <= {ADDR_WIDTH{1'b0}};
        frame_sample_target <= {{(ADDR_WIDTH - 1){1'b0}}, 1'b1};
    end else begin
        frame_ready <= 1'b0;

        if (sample_valid) begin
            // Latch the current frame length only at frame start.
            if (wr_addr_active == {ADDR_WIDTH{1'b0}})
                frame_sample_target <= frame_samples_clamped;

            // When the current bank is full, publish it and switch banks.
            if (wr_addr_active == (frame_sample_target_now - 1'b1)) begin
                frame_ready        <= 1'b1;
                ready_bank         <= wr_bank_active;
                ready_sample_count <= frame_sample_target_now;
                wr_bank_active     <= ~wr_bank_active;
                wr_addr_active     <= {ADDR_WIDTH{1'b0}};
            end else begin
                wr_addr_active <= wr_addr_active + 1'b1;
            end
        end
    end
end

endmodule
