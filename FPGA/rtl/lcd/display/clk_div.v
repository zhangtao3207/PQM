/*
 * Module: clk_div
 * 功能:
 *   并行产生多种像素时钟并按 LCD ID 选择输出。
 */

/*
 * 详细说明：
 *   通过对系统时钟做二分频、四分频，再结合 LCD 面板 ID 查表，
 *   给显示链输出合适的像素时钟 `lcd_pclk`。
 */
module clk_div(
    input               clk,          
    input               rst_n,
    input       [15:0]  lcd_id,
    output  reg         lcd_pclk
    );

reg          clk_25m;
reg          clk_12_5m;
reg          div_4_cnt;

// 二分频时钟。
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        clk_25m <= 1'b0;
    else
        clk_25m <= ~clk_25m;
end

// 四分频时钟。
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        div_4_cnt <= 1'b0;
        clk_12_5m <= 1'b0;
    end    
    else begin
        div_4_cnt <= div_4_cnt + 1'b1;
        if(div_4_cnt == 1'b1)
            clk_12_5m <= ~clk_12_5m;
        else
            clk_12_5m <= clk_12_5m;
    end        
end

// 根据 LCD ID 选择匹配的像素时钟。
always @(*) begin
    case(lcd_id)
        16'h4342 : lcd_pclk = clk_12_5m;
        16'h7084 : lcd_pclk = clk_25m;
        16'h7016 : lcd_pclk = clk;
        16'h4384 : lcd_pclk = clk_25m;
        16'h1018 : lcd_pclk = clk;
        default :  lcd_pclk = 1'b0;
    endcase
end

endmodule
