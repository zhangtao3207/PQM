module AD7606_UART(
	Clk,
	Reset_n,
	Rs232_Tx,
	Rs232_Rx,
	
	ad7606_cs_n_o,   
	ad7606_rd_n_o,   
	ad7606_busy_i,   
	ad7606_db_i,     
	ad7606_os_o,     
	ad7606_reset_o,  
	ad7606_convst_o
);
    
	input  wire 		 Clk;
	input  wire 		 Reset_n;

	output wire        Rs232_Tx;
	input  wire 		 Rs232_Rx;
    
	output wire        ad7606_cs_n_o;         
	output wire        ad7606_rd_n_o;         
	input  wire        ad7606_busy_i;         
	input  wire [15:0] ad7606_db_i;           
	output wire [2:0]  ad7606_os_o;           
	output wire        ad7606_reset_o;        
	output wire        ad7606_convst_o;   

    wire fifowrreq;
    wire [15:0]fifowrdata;
    wire [7:0]uart_tx_data;
    wire uart_send_en;
    wire uart_tx_done;       
    wire key_flag;
    wire key_state; 
    wire fifordempty;
    wire fifordreq;
    wire [15:0]fiforddata;
    
    wire [7:0]rx_data;
    wire rx_done;
    
    wire [7:0]ChannelSel;
    wire [15:0]DataNum;
    wire [31:0] ADC_Speed_Set;
    
    wire [7:0]cmd_addr;
    wire [31:0]cmd_data;
    wire cmdvalid;    
    
    wire RestartReq;
    wire [7:0]adc_data_flag;
    wire [15:0]adc_data_mult_ch; 

    ad7606_driver ad7606_driver(
        .Clk(Clk),
        .Reset_n(Reset_n),
        .Go(1),
        .Speed_Set(ADC_Speed_Set),
        .Conv_Done(),
        .ad7606_cs_n_o(ad7606_cs_n_o), 
        .ad7606_rd_n_o(ad7606_rd_n_o), 
        .ad7606_busy_i(ad7606_busy_i), 
        .ad7606_db_i(ad7606_db_i), 
        .ad7606_os_o(ad7606_os_o), 
        .ad7606_reset_o(ad7606_reset_o), 
        .ad7606_convst_o(ad7606_convst_o), 
        .data_flag(adc_data_flag),
        .data_mult_ch(adc_data_mult_ch),
        .data1(),
        .data2(), 
        .data3(), 
        .data4(), 
        .data5(), 
        .data6(), 
        .data7(), 
        .data8()
    );
    
    fifo_generator_0 fifo (
        .clock(Clk),      // input wire clk
        .sclr(!Reset_n),    // input wire srst
        .data(fifowrdata),      // input wire [15 : 0] din
        .wrreq(fifowrreq),  // input wire wr_en
        .rdreq(fifordreq),  // input wire rd_en
        .q(fiforddata),    // output wire [15 : 0] dout
        .full(),    // output wire full
        .empty(fifordempty)  // output wire empty
    );
    
    adc_write_ctrl adc_write_ctrl(
        .Clk(Clk),
        .Reset_n(Reset_n),
        .DataNum(DataNum),
        .RestartReq(RestartReq),
        .ChannelSel(ChannelSel),
        .fifowrreq(fifowrreq),
        .fifowrdata(fifowrdata),
        .fifowrfull(),
        .adc_data_flag(adc_data_flag),
        .adc_data_mult_ch(adc_data_mult_ch)
    );

    uart_byte_tx uart_byte_tx(
        .Clk(Clk),       //50M时钟输入
        .Rst_n(Reset_n),     //模块复位
        .data_byte(uart_tx_data), //待传输8bit数据
        .send_en(uart_send_en),   //发送使能
        .baud_set(4),  //波特率设置
        .Rs232_Tx(Rs232_Tx),  //Rs232输出信号
        .Tx_Done(uart_tx_done),   //一次发送数据完成标志
        .uart_state() //发送数据状态
    );
    
    uart_send_ctrl uart_send_ctrl(
        .Clk(Clk),
        .Reset_n(Reset_n),
        .uart_tx_data(uart_tx_data),
        .uart_send_en(uart_send_en),
        .uart_tx_done(uart_tx_done),
        .fifordempty(fifordempty),
        .fifordreq(fifordreq),
        .fiforddata(fiforddata)
    );
    
    uart_cmd uart_cmd(
        .Clk(Clk),
        .Reset_n(Reset_n),
        .rx_data(rx_data),
        .rx_done(rx_done),
        .address(cmd_addr),
        .data(cmd_data),
        .cmdvalid(cmdvalid)
    );
    
    uart_byte_rx uart_byte_rx(
        .Clk(Clk),
        .Reset_n(Reset_n),
        .Baud_Set(4),
        .uart_rx(Rs232_Rx),
        .Data(rx_data),
        .Rx_Done(rx_done)  
    ); 


    cmd_ctrl cmd_ctrl(
       .Clk(Clk),
       .Reset_n(Reset_n),
       .cmd_data(cmd_data),
       .cmd_addr(cmd_addr),
       .cmdvalid(cmdvalid),
       .RestartReq(RestartReq),
       .ChannelSel(ChannelSel),
       .DataNum(DataNum),
       .ADC_Speed_Set(ADC_Speed_Set)
	);

endmodule
