`timescale 1ns / 1ps

module text_display_preprocess #(
    parameter integer SAMPLE_WIDTH          = 16,
    parameter integer RMS_MAX_FRAME_SAMPLES = 8192,
    parameter integer RMS_N_WIDTH           = (RMS_MAX_FRAME_SAMPLES <= 2) ? 2 : $clog2(RMS_MAX_FRAME_SAMPLES),
    parameter integer RMS_FRAME_SAMPLES     = 6144,
    parameter integer POWER_WINDOW_SAMPLES  = 8192,
    parameter integer U_FULL_SCALE_X100     = 1000,
    parameter integer I_FULL_SCALE_X100     = 30,
    parameter integer START_DELAY_CYCLES    = 1_250_000
)(
    input                          clk,
    input                          rst_n,
    input                          lcd_frame_done_toggle,
    input                          lcd_swap_ack_toggle,
    input                          u_sample_valid,
    input      [SAMPLE_WIDTH-1:0]  u_sample_code,
    input      [SAMPLE_WIDTH-1:0]  u_zero_code,
    input                          u_zero_valid,
    input                          i_sample_valid,
    input      [SAMPLE_WIDTH-1:0]  i_sample_code,
    input      [SAMPLE_WIDTH-1:0]  i_zero_code,
    input                          i_zero_valid,

    output reg                     text_result_commit_toggle,

    output reg [7:0]               u_rms_tens,
    output reg [7:0]               u_rms_units,
    output reg [7:0]               u_rms_decile,
    output reg [7:0]               u_rms_percentiles,
    output reg                     u_rms_digits_valid,
    output reg [7:0]               i_rms_tens,
    output reg [7:0]               i_rms_units,
    output reg [7:0]               i_rms_decile,
    output reg [7:0]               i_rms_percentiles,
    output reg                     i_rms_digits_valid,

    output reg [7:0]               phase_hundreds,
    output reg [7:0]               phase_tens,
    output reg [7:0]               phase_units,
    output reg [7:0]               phase_decile,
    output reg [7:0]               phase_percentiles,
    output reg signed [16:0]       phase_x100_signed,
    output reg                     phase_neg,
    output reg                     phase_valid,

    output reg [7:0]               freq_hundreds,
    output reg [7:0]               freq_tens,
    output reg [7:0]               freq_units,
    output reg [7:0]               freq_decile,
    output reg [7:0]               freq_percentiles,
    output reg                     freq_valid,

    output reg [7:0]               u_pp_tens,
    output reg [7:0]               u_pp_units,
    output reg [7:0]               u_pp_decile,
    output reg [7:0]               u_pp_percentiles,
    output reg                     u_pp_digits_valid,
    output reg [7:0]               i_pp_tens,
    output reg [7:0]               i_pp_units,
    output reg [7:0]               i_pp_decile,
    output reg [7:0]               i_pp_percentiles,
    output reg                     i_pp_digits_valid,

    output reg                     active_p_neg,
    output reg [7:0]               active_p_tens,
    output reg [7:0]               active_p_units,
    output reg [7:0]               active_p_decile,
    output reg [7:0]               active_p_percentiles,
    output reg                     reactive_q_neg,
    output reg [7:0]               reactive_q_tens,
    output reg [7:0]               reactive_q_units,
    output reg [7:0]               reactive_q_decile,
    output reg [7:0]               reactive_q_percentiles,
    output reg [7:0]               apparent_s_tens,
    output reg [7:0]               apparent_s_units,
    output reg [7:0]               apparent_s_decile,
    output reg [7:0]               apparent_s_percentiles,
    output reg                     power_factor_neg,
    output reg [7:0]               power_factor_units,
    output reg [7:0]               power_factor_decile,
    output reg [7:0]               power_factor_percentiles,
    output reg                     power_metrics_valid
);

localparam [3:0] ST_WAIT_FRAME   = 4'd0;
localparam [3:0] ST_WAIT_DELAY   = 4'd1;
localparam [3:0] ST_START_BASIC  = 4'd2;
localparam [3:0] ST_WAIT_BASIC   = 4'd3;
localparam [3:0] ST_START_POWER  = 4'd4;
localparam [3:0] ST_WAIT_POWER   = 4'd5;
localparam [3:0] ST_COMMIT       = 4'd6;
localparam [3:0] ST_WAIT_SWAP    = 4'd7;

localparam [RMS_N_WIDTH-1:0] RMS_FRAME_SAMPLES_VALUE = RMS_FRAME_SAMPLES;
localparam [SAMPLE_WIDTH-1:0] RMS_CENTER_DEFAULT = {1'b1, {(SAMPLE_WIDTH - 1){1'b0}}};

reg  [3:0]                    state;
reg  [31:0]                   start_delay_cnt;
reg                           frame_toggle_sync1;
reg                           frame_toggle_sync2;
reg                           frame_toggle_sync3;
reg                           swap_ack_sync1;
reg                           swap_ack_sync2;
reg                           swap_ack_sync3;
reg                           rms_start;
reg                           u_p2p_start;
reg                           i_p2p_start;
reg                           phase_start;
reg                           freq_start;
reg                           power_start;
reg                           rms_done_seen;
reg                           u_p2p_done_seen;
reg                           i_p2p_done_seen;
reg                           phase_done_seen;
reg                           freq_done_seen;
reg                           rms_valid_latched;
reg                           u_rms_digits_seen;
reg                           i_rms_digits_seen;
reg                           u_pp_digits_seen;
reg                           i_pp_digits_seen;
reg                           phase_valid_latched;
reg                           freq_valid_latched;
reg                           power_valid_latched;
reg  [7:0]                    u_rms_tens_pending;
reg  [7:0]                    u_rms_units_pending;
reg  [7:0]                    u_rms_decile_pending;
reg  [7:0]                    u_rms_percentiles_pending;
reg  [7:0]                    i_rms_tens_pending;
reg  [7:0]                    i_rms_units_pending;
reg  [7:0]                    i_rms_decile_pending;
reg  [7:0]                    i_rms_percentiles_pending;
reg  [7:0]                    u_pp_tens_pending;
reg  [7:0]                    u_pp_units_pending;
reg  [7:0]                    u_pp_decile_pending;
reg  [7:0]                    u_pp_percentiles_pending;
reg  [7:0]                    i_pp_tens_pending;
reg  [7:0]                    i_pp_units_pending;
reg  [7:0]                    i_pp_decile_pending;
reg  [7:0]                    i_pp_percentiles_pending;
reg                           phase_neg_pending;
reg  [7:0]                    phase_hundreds_pending;
reg  [7:0]                    phase_tens_pending;
reg  [7:0]                    phase_units_pending;
reg  [7:0]                    phase_decile_pending;
reg  [7:0]                    phase_percentiles_pending;
reg  signed [16:0]            phase_x100_signed_pending;
reg  [7:0]                    freq_hundreds_pending;
reg  [7:0]                    freq_tens_pending;
reg  [7:0]                    freq_units_pending;
reg  [7:0]                    freq_decile_pending;
reg  [7:0]                    freq_percentiles_pending;

wire                          frame_edge_wave;
wire                          ui_sample_valid;
wire [SAMPLE_WIDTH-1:0]       u_rms_zero_code;
wire [SAMPLE_WIDTH-1:0]       i_rms_zero_code;
wire signed [SAMPLE_WIDTH:0]  u_sample_delta_ext;
wire signed [SAMPLE_WIDTH:0]  i_sample_delta_ext;
wire signed [SAMPLE_WIDTH-1:0] u_sample_signed_for_rms;
wire signed [SAMPLE_WIDTH-1:0] i_sample_signed_for_rms;

wire                          rms_busy;
wire                          rms_done;
wire                          rms_valid_wire;
wire signed [SAMPLE_WIDTH-1:0] u_rms_code;
wire signed [SAMPLE_WIDTH-1:0] i_rms_code;
wire [7:0]                    u_rms_tens_wire;
wire [7:0]                    u_rms_units_wire;
wire [7:0]                    u_rms_decile_wire;
wire [7:0]                    u_rms_percentiles_wire;
wire                          u_rms_digits_valid_wire;
wire [7:0]                    i_rms_tens_wire;
wire [7:0]                    i_rms_units_wire;
wire [7:0]                    i_rms_decile_wire;
wire [7:0]                    i_rms_percentiles_wire;
wire                          i_rms_digits_valid_wire;

wire                          u_p2p_busy;
wire                          u_p2p_done;
wire [7:0]                    u_pp_tens_wire;
wire [7:0]                    u_pp_units_wire;
wire [7:0]                    u_pp_decile_wire;
wire [7:0]                    u_pp_percentiles_wire;
wire                          u_pp_digits_valid_wire;

wire                          i_p2p_busy;
wire                          i_p2p_done;
wire [7:0]                    i_pp_tens_wire;
wire [7:0]                    i_pp_units_wire;
wire [7:0]                    i_pp_decile_wire;
wire [7:0]                    i_pp_percentiles_wire;
wire                          i_pp_digits_valid_wire;

wire                          phase_busy;
wire                          phase_done;
wire                          phase_neg_wire;
wire [7:0]                    phase_hundreds_wire;
wire [7:0]                    phase_tens_wire;
wire [7:0]                    phase_units_wire;
wire [7:0]                    phase_decile_wire;
wire [7:0]                    phase_percentiles_wire;
wire signed [16:0]            phase_x100_signed_wire;
wire                          phase_valid_wire;

wire                          freq_busy;
wire                          freq_done;
wire [7:0]                    freq_hundreds_wire;
wire [7:0]                    freq_tens_wire;
wire [7:0]                    freq_units_wire;
wire [7:0]                    freq_decile_wire;
wire [7:0]                    freq_percentiles_wire;
wire                          freq_valid_wire;

wire                          power_busy;
wire                          power_done;
wire                          active_p_neg_wire;
wire [7:0]                    active_p_tens_wire;
wire [7:0]                    active_p_units_wire;
wire [7:0]                    active_p_decile_wire;
wire [7:0]                    active_p_percentiles_wire;
wire                          reactive_q_neg_wire;
wire [7:0]                    reactive_q_tens_wire;
wire [7:0]                    reactive_q_units_wire;
wire [7:0]                    reactive_q_decile_wire;
wire [7:0]                    reactive_q_percentiles_wire;
wire [7:0]                    apparent_s_tens_wire;
wire [7:0]                    apparent_s_units_wire;
wire [7:0]                    apparent_s_decile_wire;
wire [7:0]                    apparent_s_percentiles_wire;
wire                          power_factor_neg_wire;
wire [7:0]                    power_factor_units_wire;
wire [7:0]                    power_factor_decile_wire;
wire [7:0]                    power_factor_percentiles_wire;
wire                          power_metrics_valid_wire;
wire                          base_packet_valid;
wire                          rms_digits_valid;
wire                          p2p_digits_valid;
wire                          phase_packet_valid;
wire                          freq_packet_valid;
wire                          power_packet_valid;
wire                          base_commit_valid;

assign frame_edge_wave   = frame_toggle_sync2 ^ frame_toggle_sync3;
assign ui_sample_valid   = u_sample_valid && i_sample_valid;
assign u_rms_zero_code   = u_zero_valid ? u_zero_code : RMS_CENTER_DEFAULT;
assign i_rms_zero_code   = i_zero_valid ? i_zero_code : RMS_CENTER_DEFAULT;
assign u_sample_delta_ext = $signed({1'b0, u_sample_code}) - $signed({1'b0, u_rms_zero_code});
assign i_sample_delta_ext = $signed({1'b0, i_sample_code}) - $signed({1'b0, i_rms_zero_code});
assign u_sample_signed_for_rms = u_sample_delta_ext[SAMPLE_WIDTH-1:0];
assign i_sample_signed_for_rms = i_sample_delta_ext[SAMPLE_WIDTH-1:0];
assign base_packet_valid =
    rms_valid_latched      &&
    u_pp_digits_seen       &&
    i_pp_digits_seen;
assign rms_digits_valid = u_rms_digits_seen && i_rms_digits_seen;
assign p2p_digits_valid = u_pp_digits_seen && i_pp_digits_seen;
assign phase_packet_valid = phase_valid_latched;
assign freq_packet_valid  = freq_valid_latched;
assign power_packet_valid = power_valid_latched;
assign base_commit_valid = base_packet_valid && rms_digits_valid && p2p_digits_valid;

ui_rms_measure #(
    .DATA_WIDTH        (SAMPLE_WIDTH),
    .MAX_FRAME_SAMPLES (RMS_MAX_FRAME_SAMPLES),
    .N_WIDTH           (RMS_N_WIDTH),
    .U_FULL_SCALE_X100 (U_FULL_SCALE_X100),
    .I_FULL_SCALE_X100 (I_FULL_SCALE_X100)
) u_ui_rms_measure (
    .clk               (clk),
    .rst_n             (rst_n),
    .start             (rms_start),
    .frame_samples_n   (RMS_FRAME_SAMPLES_VALUE),
    .sample_valid      (ui_sample_valid),
    .u_sample_in       (u_sample_signed_for_rms),
    .i_sample_in       (i_sample_signed_for_rms),
    .busy              (rms_busy),
    .done              (rms_done),
    .rms_valid         (rms_valid_wire),
    .config_error      (),
    .frame_overflow    (),
    .u_rms_out         (u_rms_code),
    .i_rms_out         (i_rms_code),
    .u_rms_x100        (),
    .i_rms_x100        (),
    .u_rms_tens        (u_rms_tens_wire),
    .u_rms_units       (u_rms_units_wire),
    .u_rms_decile      (u_rms_decile_wire),
    .u_rms_percentiles (u_rms_percentiles_wire),
    .u_rms_digits_valid(u_rms_digits_valid_wire),
    .i_rms_tens        (i_rms_tens_wire),
    .i_rms_units       (i_rms_units_wire),
    .i_rms_decile      (i_rms_decile_wire),
    .i_rms_percentiles (i_rms_percentiles_wire),
    .i_rms_digits_valid(i_rms_digits_valid_wire)
);

p2p_measure #(
    .WIDTH             (SAMPLE_WIDTH),
    .MAX_FRAME_SAMPLES (RMS_MAX_FRAME_SAMPLES),
    .N_WIDTH           (RMS_N_WIDTH),
    .FULL_SCALE_X100   (U_FULL_SCALE_X100)
) u_u_p2p_measure (
    .clk             (clk),
    .rst_n           (rst_n),
    .start           (u_p2p_start),
    .sample_count_n  (RMS_FRAME_SAMPLES_VALUE),
    .sample_valid    (ui_sample_valid),
    .sample_code     (u_sample_code),
    .busy            (u_p2p_busy),
    .done            (u_p2p_done),
    .p2p_tens        (u_pp_tens_wire),
    .p2p_units       (u_pp_units_wire),
    .p2p_decile      (u_pp_decile_wire),
    .p2p_percentiles (u_pp_percentiles_wire),
    .p2p_digits_valid(u_pp_digits_valid_wire)
);

p2p_measure #(
    .WIDTH             (SAMPLE_WIDTH),
    .MAX_FRAME_SAMPLES (RMS_MAX_FRAME_SAMPLES),
    .N_WIDTH           (RMS_N_WIDTH),
    .FULL_SCALE_X100   (I_FULL_SCALE_X100)
) u_i_p2p_measure (
    .clk             (clk),
    .rst_n           (rst_n),
    .start           (i_p2p_start),
    .sample_count_n  (RMS_FRAME_SAMPLES_VALUE),
    .sample_valid    (ui_sample_valid),
    .sample_code     (i_sample_code),
    .busy            (i_p2p_busy),
    .done            (i_p2p_done),
    .p2p_tens        (i_pp_tens_wire),
    .p2p_units       (i_pp_units_wire),
    .p2p_decile      (i_pp_decile_wire),
    .p2p_percentiles (i_pp_percentiles_wire),
    .p2p_digits_valid(i_pp_digits_valid_wire)
);

phase_diff_calc #(
    .WIDTH             (SAMPLE_WIDTH),
    .MAX_FRAME_SAMPLES (RMS_MAX_FRAME_SAMPLES),
    .N_WIDTH           (RMS_N_WIDTH)
) u_phase_diff_calc (
    .clk             (clk),
    .rst_n           (rst_n),
    .start           (phase_start),
    .sample_count_n  (RMS_FRAME_SAMPLES_VALUE),
    .sample_valid    (ui_sample_valid),
    .u_sample_code   (u_sample_code),
    .u_zero_code     (u_zero_code),
    .u_zero_valid    (u_zero_valid),
    .i_sample_code   (i_sample_code),
    .i_zero_code     (i_zero_code),
    .i_zero_valid    (i_zero_valid),
    .busy            (phase_busy),
    .done            (phase_done),
    .phase_neg       (phase_neg_wire),
    .phase_hundreds  (phase_hundreds_wire),
    .phase_tens      (phase_tens_wire),
    .phase_units     (phase_units_wire),
    .phase_decile    (phase_decile_wire),
    .phase_percentiles(phase_percentiles_wire),
    .phase_x100_signed(phase_x100_signed_wire),
    .phase_valid     (phase_valid_wire)
);

frequency_measure #(
    .WIDTH             (SAMPLE_WIDTH),
    .MAX_FRAME_SAMPLES (RMS_MAX_FRAME_SAMPLES),
    .N_WIDTH           (RMS_N_WIDTH)
) u_frequency_measure (
    .clk             (clk),
    .rst_n           (rst_n),
    .start           (freq_start),
    .sample_count_n  (RMS_FRAME_SAMPLES_VALUE),
    .sample_valid    (ui_sample_valid),
    .sample_code     (u_sample_code),
    .zero_code       (u_zero_code),
    .zero_valid      (u_zero_valid),
    .busy            (freq_busy),
    .done            (freq_done),
    .freq_hundreds   (freq_hundreds_wire),
    .freq_tens       (freq_tens_wire),
    .freq_units      (freq_units_wire),
    .freq_decile     (freq_decile_wire),
    .freq_percentiles(freq_percentiles_wire),
    .freq_valid      (freq_valid_wire)
);

power_metrics_calc #(
    .WIDTH             (SAMPLE_WIDTH),
    .WINDOW_SAMPLES    (POWER_WINDOW_SAMPLES),
    .U_FULL_SCALE_X100 (U_FULL_SCALE_X100),
    .I_FULL_SCALE_X100 (I_FULL_SCALE_X100)
) u_power_metrics_calc (
    .clk                     (clk),
    .rst_n                   (rst_n),
    .start                   (power_start),
    .rms_valid               (rms_valid_latched),
    .u_rms_code              (u_rms_code),
    .i_rms_code              (i_rms_code),
    .phase_x100_signed       (phase_x100_signed_wire),
    .phase_valid             (phase_valid_latched),
    .busy                    (power_busy),
    .done                    (power_done),
    .active_p_neg            (active_p_neg_wire),
    .active_p_tens           (active_p_tens_wire),
    .active_p_units          (active_p_units_wire),
    .active_p_decile         (active_p_decile_wire),
    .active_p_percentiles    (active_p_percentiles_wire),
    .reactive_q_neg          (reactive_q_neg_wire),
    .reactive_q_tens         (reactive_q_tens_wire),
    .reactive_q_units        (reactive_q_units_wire),
    .reactive_q_decile       (reactive_q_decile_wire),
    .reactive_q_percentiles  (reactive_q_percentiles_wire),
    .apparent_s_tens         (apparent_s_tens_wire),
    .apparent_s_units        (apparent_s_units_wire),
    .apparent_s_decile       (apparent_s_decile_wire),
    .apparent_s_percentiles  (apparent_s_percentiles_wire),
    .power_factor_neg        (power_factor_neg_wire),
    .power_factor_units      (power_factor_units_wire),
    .power_factor_decile     (power_factor_decile_wire),
    .power_factor_percentiles(power_factor_percentiles_wire),
    .power_metrics_valid     (power_metrics_valid_wire)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state                     <= ST_WAIT_FRAME;
        start_delay_cnt           <= 32'd0;
        frame_toggle_sync1        <= 1'b0;
        frame_toggle_sync2        <= 1'b0;
        frame_toggle_sync3        <= 1'b0;
        swap_ack_sync1            <= 1'b0;
        swap_ack_sync2            <= 1'b0;
        swap_ack_sync3            <= 1'b0;
        rms_start                 <= 1'b0;
        u_p2p_start               <= 1'b0;
        i_p2p_start               <= 1'b0;
        phase_start               <= 1'b0;
        freq_start                <= 1'b0;
        power_start               <= 1'b0;
        rms_done_seen             <= 1'b0;
        u_p2p_done_seen           <= 1'b0;
        i_p2p_done_seen           <= 1'b0;
        phase_done_seen           <= 1'b0;
        freq_done_seen            <= 1'b0;
        rms_valid_latched         <= 1'b0;
        u_rms_digits_seen         <= 1'b0;
        i_rms_digits_seen         <= 1'b0;
        u_pp_digits_seen          <= 1'b0;
        i_pp_digits_seen          <= 1'b0;
        phase_valid_latched       <= 1'b0;
        freq_valid_latched        <= 1'b0;
        power_valid_latched       <= 1'b0;
        u_rms_tens_pending        <= 8'd0;
        u_rms_units_pending       <= 8'd0;
        u_rms_decile_pending      <= 8'd0;
        u_rms_percentiles_pending <= 8'd0;
        i_rms_tens_pending        <= 8'd0;
        i_rms_units_pending       <= 8'd0;
        i_rms_decile_pending      <= 8'd0;
        i_rms_percentiles_pending <= 8'd0;
        u_pp_tens_pending         <= 8'd0;
        u_pp_units_pending        <= 8'd0;
        u_pp_decile_pending       <= 8'd0;
        u_pp_percentiles_pending  <= 8'd0;
        i_pp_tens_pending         <= 8'd0;
        i_pp_units_pending        <= 8'd0;
        i_pp_decile_pending       <= 8'd0;
        i_pp_percentiles_pending  <= 8'd0;
        phase_neg_pending         <= 1'b0;
        phase_hundreds_pending    <= 8'd0;
        phase_tens_pending        <= 8'd0;
        phase_units_pending       <= 8'd0;
        phase_decile_pending      <= 8'd0;
        phase_percentiles_pending <= 8'd0;
        phase_x100_signed_pending <= 17'sd0;
        freq_hundreds_pending     <= 8'd0;
        freq_tens_pending         <= 8'd0;
        freq_units_pending        <= 8'd0;
        freq_decile_pending       <= 8'd0;
        freq_percentiles_pending  <= 8'd0;
        text_result_commit_toggle <= 1'b0;
        u_rms_tens                <= 8'd0;
        u_rms_units               <= 8'd0;
        u_rms_decile              <= 8'd0;
        u_rms_percentiles         <= 8'd0;
        u_rms_digits_valid        <= 1'b0;
        i_rms_tens                <= 8'd0;
        i_rms_units               <= 8'd0;
        i_rms_decile              <= 8'd0;
        i_rms_percentiles         <= 8'd0;
        i_rms_digits_valid        <= 1'b0;
        phase_hundreds            <= 8'd0;
        phase_tens                <= 8'd0;
        phase_units               <= 8'd0;
        phase_decile              <= 8'd0;
        phase_percentiles         <= 8'd0;
        phase_x100_signed         <= 17'sd0;
        phase_neg                 <= 1'b0;
        phase_valid               <= 1'b0;
        freq_hundreds             <= 8'd0;
        freq_tens                 <= 8'd0;
        freq_units                <= 8'd0;
        freq_decile               <= 8'd0;
        freq_percentiles          <= 8'd0;
        freq_valid                <= 1'b0;
        u_pp_tens                 <= 8'd0;
        u_pp_units                <= 8'd0;
        u_pp_decile               <= 8'd0;
        u_pp_percentiles          <= 8'd0;
        u_pp_digits_valid         <= 1'b0;
        i_pp_tens                 <= 8'd0;
        i_pp_units                <= 8'd0;
        i_pp_decile               <= 8'd0;
        i_pp_percentiles          <= 8'd0;
        i_pp_digits_valid         <= 1'b0;
        active_p_neg              <= 1'b0;
        active_p_tens             <= 8'd0;
        active_p_units            <= 8'd0;
        active_p_decile           <= 8'd0;
        active_p_percentiles      <= 8'd0;
        reactive_q_neg            <= 1'b0;
        reactive_q_tens           <= 8'd0;
        reactive_q_units          <= 8'd0;
        reactive_q_decile         <= 8'd0;
        reactive_q_percentiles    <= 8'd0;
        apparent_s_tens           <= 8'd0;
        apparent_s_units          <= 8'd0;
        apparent_s_decile         <= 8'd0;
        apparent_s_percentiles    <= 8'd0;
        power_factor_neg          <= 1'b0;
        power_factor_units        <= 8'd0;
        power_factor_decile       <= 8'd0;
        power_factor_percentiles  <= 8'd0;
        power_metrics_valid       <= 1'b0;
    end else begin
        frame_toggle_sync1 <= lcd_frame_done_toggle;
        frame_toggle_sync2 <= frame_toggle_sync1;
        frame_toggle_sync3 <= frame_toggle_sync2;
        swap_ack_sync1     <= lcd_swap_ack_toggle;
        swap_ack_sync2     <= swap_ack_sync1;
        swap_ack_sync3     <= swap_ack_sync2;

        rms_start   <= 1'b0;
        u_p2p_start <= 1'b0;
        i_p2p_start <= 1'b0;
        phase_start <= 1'b0;
        freq_start  <= 1'b0;
        power_start <= 1'b0;

        if (rms_done)
            rms_done_seen <= 1'b1;
        if (u_p2p_done)
            u_p2p_done_seen <= 1'b1;
        if (i_p2p_done)
            i_p2p_done_seen <= 1'b1;
        if (phase_done)
            phase_done_seen <= 1'b1;
        if (freq_done)
            freq_done_seen <= 1'b1;
        if (rms_valid_wire)
            rms_valid_latched <= 1'b1;
        if (u_rms_digits_valid_wire) begin
            u_rms_tens_pending        <= u_rms_tens_wire;
            u_rms_units_pending       <= u_rms_units_wire;
            u_rms_decile_pending      <= u_rms_decile_wire;
            u_rms_percentiles_pending <= u_rms_percentiles_wire;
            u_rms_digits_seen         <= 1'b1;
        end
        if (i_rms_digits_valid_wire) begin
            i_rms_tens_pending        <= i_rms_tens_wire;
            i_rms_units_pending       <= i_rms_units_wire;
            i_rms_decile_pending      <= i_rms_decile_wire;
            i_rms_percentiles_pending <= i_rms_percentiles_wire;
            i_rms_digits_seen         <= 1'b1;
        end
        if (u_pp_digits_valid_wire) begin
            u_pp_tens_pending        <= u_pp_tens_wire;
            u_pp_units_pending       <= u_pp_units_wire;
            u_pp_decile_pending      <= u_pp_decile_wire;
            u_pp_percentiles_pending <= u_pp_percentiles_wire;
            u_pp_digits_seen         <= 1'b1;
        end
        if (i_pp_digits_valid_wire) begin
            i_pp_tens_pending        <= i_pp_tens_wire;
            i_pp_units_pending       <= i_pp_units_wire;
            i_pp_decile_pending      <= i_pp_decile_wire;
            i_pp_percentiles_pending <= i_pp_percentiles_wire;
            i_pp_digits_seen         <= 1'b1;
        end
        if (phase_valid_wire) begin
            phase_neg_pending         <= phase_neg_wire;
            phase_hundreds_pending    <= phase_hundreds_wire;
            phase_tens_pending        <= phase_tens_wire;
            phase_units_pending       <= phase_units_wire;
            phase_decile_pending      <= phase_decile_wire;
            phase_percentiles_pending <= phase_percentiles_wire;
            phase_x100_signed_pending <= phase_x100_signed_wire;
            phase_valid_latched <= 1'b1;
        end
        if (freq_valid_wire) begin
            freq_hundreds_pending    <= freq_hundreds_wire;
            freq_tens_pending        <= freq_tens_wire;
            freq_units_pending       <= freq_units_wire;
            freq_decile_pending      <= freq_decile_wire;
            freq_percentiles_pending <= freq_percentiles_wire;
            freq_valid_latched       <= 1'b1;
        end
        if (power_metrics_valid_wire)
            power_valid_latched <= 1'b1;

        case (state)
            ST_WAIT_FRAME: begin
                start_delay_cnt <= 32'd0;
                if (frame_edge_wave)
                    state <= ST_WAIT_DELAY;
            end

            ST_WAIT_DELAY: begin
                if (start_delay_cnt == (START_DELAY_CYCLES - 1)) begin
                    start_delay_cnt <= 32'd0;
                    state           <= ST_START_BASIC;
                end else begin
                    start_delay_cnt <= start_delay_cnt + 32'd1;
                end
            end

            ST_START_BASIC: begin
                rms_start         <= 1'b1;
                u_p2p_start       <= 1'b1;
                i_p2p_start       <= 1'b1;
                phase_start       <= 1'b1;
                freq_start        <= 1'b1;
                rms_done_seen     <= 1'b0;
                u_p2p_done_seen   <= 1'b0;
                i_p2p_done_seen   <= 1'b0;
                phase_done_seen   <= 1'b0;
                freq_done_seen    <= 1'b0;
                rms_valid_latched <= 1'b0;
                u_rms_digits_seen <= 1'b0;
                i_rms_digits_seen <= 1'b0;
                u_pp_digits_seen  <= 1'b0;
                i_pp_digits_seen  <= 1'b0;
                phase_valid_latched <= 1'b0;
                freq_valid_latched  <= 1'b0;
                power_valid_latched <= 1'b0;
                state             <= ST_WAIT_BASIC;
            end

            ST_WAIT_BASIC: begin
                if ((rms_done_seen   || rms_done)   &&
                    (u_p2p_done_seen || u_p2p_done) &&
                    (i_p2p_done_seen || i_p2p_done) &&
                    (phase_done_seen || phase_done) &&
                    (freq_done_seen  || freq_done)) begin
                    state <= ST_START_POWER;
                end
            end

            ST_START_POWER: begin
                power_start <= 1'b1;
                state       <= ST_WAIT_POWER;
            end

            ST_WAIT_POWER: begin
                if (power_done)
                    state <= ST_COMMIT;
            end

            ST_COMMIT: begin
                if (base_commit_valid) begin
                    u_rms_tens         <= u_rms_tens_pending;
                    u_rms_units        <= u_rms_units_pending;
                    u_rms_decile       <= u_rms_decile_pending;
                    u_rms_percentiles  <= u_rms_percentiles_pending;
                    u_rms_digits_valid <= 1'b1;
                    i_rms_tens         <= i_rms_tens_pending;
                    i_rms_units        <= i_rms_units_pending;
                    i_rms_decile       <= i_rms_decile_pending;
                    i_rms_percentiles  <= i_rms_percentiles_pending;
                    i_rms_digits_valid <= 1'b1;

                    u_pp_tens          <= u_pp_tens_pending;
                    u_pp_units         <= u_pp_units_pending;
                    u_pp_decile        <= u_pp_decile_pending;
                    u_pp_percentiles   <= u_pp_percentiles_pending;
                    u_pp_digits_valid  <= 1'b1;
                    i_pp_tens          <= i_pp_tens_pending;
                    i_pp_units         <= i_pp_units_pending;
                    i_pp_decile        <= i_pp_decile_pending;
                    i_pp_percentiles   <= i_pp_percentiles_pending;
                    i_pp_digits_valid  <= 1'b1;

                    if (phase_packet_valid) begin
                        phase_hundreds     <= phase_hundreds_pending;
                        phase_tens         <= phase_tens_pending;
                        phase_units        <= phase_units_pending;
                        phase_decile       <= phase_decile_pending;
                        phase_percentiles  <= phase_percentiles_pending;
                        phase_x100_signed  <= phase_x100_signed_pending;
                        phase_neg          <= phase_neg_pending;
                        phase_valid        <= 1'b1;
                    end

                    if (freq_packet_valid) begin
                        freq_hundreds      <= freq_hundreds_pending;
                        freq_tens          <= freq_tens_pending;
                        freq_units         <= freq_units_pending;
                        freq_decile        <= freq_decile_pending;
                        freq_percentiles   <= freq_percentiles_pending;
                        freq_valid         <= 1'b1;
                    end

                    if (power_packet_valid) begin
                        active_p_neg       <= active_p_neg_wire;
                        active_p_tens      <= active_p_tens_wire;
                        active_p_units     <= active_p_units_wire;
                        active_p_decile    <= active_p_decile_wire;
                        active_p_percentiles <= active_p_percentiles_wire;
                        reactive_q_neg     <= reactive_q_neg_wire;
                        reactive_q_tens    <= reactive_q_tens_wire;
                        reactive_q_units   <= reactive_q_units_wire;
                        reactive_q_decile  <= reactive_q_decile_wire;
                        reactive_q_percentiles <= reactive_q_percentiles_wire;
                        apparent_s_tens    <= apparent_s_tens_wire;
                        apparent_s_units   <= apparent_s_units_wire;
                        apparent_s_decile  <= apparent_s_decile_wire;
                        apparent_s_percentiles <= apparent_s_percentiles_wire;
                        power_factor_neg   <= power_factor_neg_wire;
                        power_factor_units <= power_factor_units_wire;
                        power_factor_decile <= power_factor_decile_wire;
                        power_factor_percentiles <= power_factor_percentiles_wire;
                        power_metrics_valid <= 1'b1;
                    end

                    text_result_commit_toggle <= ~text_result_commit_toggle;
                    state                     <= ST_WAIT_FRAME;
                end else begin
                    state <= ST_WAIT_FRAME;
                end
            end

            ST_WAIT_SWAP: begin
                state <= ST_WAIT_FRAME;
            end

            default: begin
                state <= ST_WAIT_FRAME;
            end
        endcase
end
end

endmodule
