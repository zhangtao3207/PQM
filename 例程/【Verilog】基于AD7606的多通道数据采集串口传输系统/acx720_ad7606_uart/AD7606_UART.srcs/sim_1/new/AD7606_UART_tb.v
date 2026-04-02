`timescale 1ns / 1ps

module AD7606_UART_tb();

    reg 		 Clk;
	reg 		 Reset_n;
	reg 		 key_in;
    wire        Rs232_Tx;
	
    wire        ad7606_cs_n_o;         
	wire         ad7606_rd_n_o;         
	reg        ad7606_busy_i;         
	reg [15:0] ad7606_db_i;           
	wire [2:0]  ad7606_os_o;           
	wire         ad7606_reset_o;        
	wire         ad7606_convst_o; 
	  
    initial Clk = 1;
    always #10 Clk = ~Clk;

    AD7606_UART AD7606_UART(
        Clk,
        Reset_n,
        key_in,
        Rs232_Tx,
        
        ad7606_cs_n_o,   
        ad7606_rd_n_o,   
        ad7606_busy_i,   
        ad7606_db_i,     
        ad7606_os_o,     
        ad7606_reset_o,  
        ad7606_convst_o
    );
    
    always@(posedge ad7606_convst_o)begin
        #40;
        ad7606_busy_i = 1;
        #3960;
        ad7606_busy_i = 0;    
    end
        
    always@(negedge ad7606_rd_n_o)begin
        ad7606_db_i = ad7606_db_i + 1;
    end
    
    initial begin
        ad7606_db_i = 16'h1234;
        ad7606_busy_i = 0;  
        Reset_n = 0;
        key_in = 1;
        #201;
        Reset_n = 1;
        #200;
        key_in = 0;
        #20000;
        key_in = 1;
        #200000;        
    
    end
    
        
//    integer i;
    
//    initial begin
//        ad7606_db_i = 16'h1234;
//        ad7606_busy_i = 0;  
//        Reset_n = 0;
//        i=0;
//        RestartReq = 0;
//        adc_data_flag = 8'b0000_0000;;
//        adc_data_mult_ch = 0;
//        #201;
//        Reset_n = 1;
//        #200;
//        RestartReq = 1;
//        #20;
//        RestartReq = 0;
//        #200;
//        repeat(120)begin
//            for(i=0;i<8;i=i+1)begin
//                adc_data_mult_ch = adc_data_mult_ch + 1;
//                adc_data_flag = 1 << i;
//                #20;
//                adc_data_flag = 0;
//                #100;
//            end
//        end   
//        #2000;
//        $stop; 
//    end
endmodule
