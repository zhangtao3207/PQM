/*
 * Module: rd_id
 * 功能:
 *   读取 LCD 标识引脚并输出面板 ID。
 */

/*
 * 详细说明：
 *   本模块在系统上电后从 LCD 复用数据总线读取一次面板 ID，并将结果锁存。
 *   之后 `lcd_id` 会被像素时钟与扫描时序模块复用。
 */
module rd_id(
    input                   clk    ,    
    input                   rst_n  ,    
    input           [23:0]  lcd_rgb,    
    output   reg    [15:0]  lcd_id      
    );

reg            rd_flag;  

// 复位释放后只采样一次 ID，避免正常显示阶段被 RGB 数据覆盖。
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        rd_flag <= 1'b0;
        lcd_id <= 16'd0;
    end    
    else begin
        if(rd_flag == 1'b0) begin
            rd_flag <= 1'b1; 
            case({lcd_rgb[7],lcd_rgb[15],lcd_rgb[23]})
                3'b000 : lcd_id <= 16'h4342;    
                3'b001 : lcd_id <= 16'h7084;    
                3'b010 : lcd_id <= 16'h7016;    
                3'b100 : lcd_id <= 16'h4384;    
                3'b101 : lcd_id <= 16'h1018;    
                default : lcd_id <= 16'd0;
            endcase    
        end
    end    
end

endmodule
