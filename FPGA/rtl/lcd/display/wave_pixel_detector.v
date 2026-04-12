`timescale 1ns / 1ps

/*
 * Module: wave_pixel_detector
 * Function:
 *   Parameterized waveform pixel detection logic for LCD display.
 *   Eliminates code duplication between voltage (U) and current (I) channels.
 *
 * This module computes:
 *   - Current and previous Y coordinates (in LCD pixels)
 *   - Segment validity (whether current and previous points are adjacent)
 *   - Y-range for the waveform line segment (to fill vertical gaps)
 *   - Final pixel-on signal indicating when to draw this waveform at (pixel_x, pixel_y)
 *
 * Parameters:
 *   GRAPH_Y:   Upper edge of the waveform plot area (in LCD pixel coordinates)
 */

module wave_pixel_detector #(
    parameter [10:0] GRAPH_Y = 11'd144
)(
    // Timing and control
    input  wire             graph_en_d1,           // Graph area enable (delayed by one pixel clock)
    input  wire             wave_frame_valid_sync, // Waveform frame has been captured
    
    // Current waveform point data (from RAM)
    input  wire [7:0]       wave_ram_dout,         // 8-bit Y coordinate
    
    // Previous point data (from pipeline)
    input  wire             wave_prev_valid_d1,    // Previous point is valid
    input  wire [7:0]       wave_prev_y_d1,        // Previous point's Y coordinate
    input  wire [8:0]       wave_prev_col_d1,      // Previous point's column
    input  wire [10:0]      wave_prev_row_d1,      // Previous point's row
    
    // Current pixel coordinate (from LCD timing)
    input  wire [8:0]       graph_col_d1,          // Current column in graph
    input  wire [10:0]      graph_row_d1,          // Current row in graph
    
    // Outputs
    output wire [10:0]      wave_y_curr_abs,       // Current Y in absolute LCD coordinates
    output wire [10:0]      wave_y_prev_abs,       // Previous Y in absolute LCD coordinates
    output wire             wave_seg_valid,        // Current and previous are adjacent columns
    output wire [10:0]      wave_seg_lo_abs,       // Lower end of segment (min Y)
    output wire [10:0]      wave_seg_hi_abs,       // Upper end of segment (max Y)
    output wire             wave_pixel_on           // Pixel should be drawn
);

localparam [10:0] Y_MARGIN = 11'd1;    // Anti-alias: draw within ±1 pixel of the line

// Compute absolute Y coordinates
assign wave_y_curr_abs = GRAPH_Y + {3'd0, wave_ram_dout};
assign wave_y_prev_abs = GRAPH_Y + {3'd0, wave_prev_y_d1};

// Check if current and previous points are adjacent columns
// (This indicates a continuous line segment, not a jump)
assign wave_seg_valid = wave_prev_valid_d1 &&
                        graph_en_d1 &&
                        (wave_prev_row_d1 == graph_row_d1) &&
                        ((wave_prev_col_d1 + 9'd1) == graph_col_d1);

// Compute Y range of the line segment (to handle diagonal lines)
assign wave_seg_lo_abs = (wave_y_curr_abs < wave_y_prev_abs) ? wave_y_curr_abs : wave_y_prev_abs;
assign wave_seg_hi_abs = (wave_y_curr_abs < wave_y_prev_abs) ? wave_y_prev_abs : wave_y_curr_abs;

// Final pixel-on logic:
// For the first point of a segment (no valid previous), use current Y only.
// For subsequent points, use the Y-range to fill diagonal lines.
assign wave_pixel_on = graph_en_d1 && wave_frame_valid_sync &&
                       (((graph_col_d1 == 9'd0) || !wave_seg_valid) ?
                           // First point: draw at current Y ±1
                           ((graph_row_d1 >= (wave_y_curr_abs - Y_MARGIN)) &&
                            (graph_row_d1 <= (wave_y_curr_abs + Y_MARGIN))) :
                           // Subsequent points: fill the segment
                           ((graph_row_d1 >= (wave_seg_lo_abs - Y_MARGIN)) &&
                            (graph_row_d1 <= (wave_seg_hi_abs + Y_MARGIN))));

endmodule
