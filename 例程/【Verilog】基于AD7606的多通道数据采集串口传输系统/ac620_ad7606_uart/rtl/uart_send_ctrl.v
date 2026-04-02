module uart_send_ctrl(
    Clk,
    Reset_n,
    uart_tx_data,
    uart_send_en,
    uart_tx_done,
    fifordempty,
    fifordreq,
    fiforddata
);

    input Clk;
    input Reset_n;
    output reg [7:0]uart_tx_data;
    output reg uart_send_en;
    input uart_tx_done;
    input fifordempty;
    output reg fifordreq;
    input [15:0]fiforddata;
    
    reg [2:0]state;

    always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)begin
        state <= 0;
        fifordreq <= 1'b0;
    end
    else begin
        case(state)
            0:
                if(!fifordempty)begin
                    state <= 1;
                    fifordreq <= 1'b1;
                end
                else begin
                    state <= 0;
                    fifordreq <= 1'b0;
                end
                
            1: 
                begin
                    fifordreq <= 1'b0;
                    state <= 2;
                end
            
            2:
               begin
                    state <= 3;
                end
            
            3:
               begin
                    state <= 4;
                    uart_send_en <= 1'b1;
                    uart_tx_data <= fiforddata[7:0];
               end
               
            4:
                begin
                    if(uart_tx_done)
                        state <= 5;
                    else
                        state <= 4;
                    uart_send_en <= 1'b0;         
                end
                
            5:
                begin
                    state <= 6;
                    uart_send_en <= 1'b1;
                    uart_tx_data <= fiforddata[15:8];
                end   
                                         
            6:
                begin
                    if(uart_tx_done)
                        state <= 0;
                    else
                        state <= 6;
                    uart_send_en <= 1'b0;         
                end
             default:
                begin
                    state <= 0;
                    uart_send_en <= 1'b0; 
                    fifordreq <= 1'b0;    
                end
         endcase    
    end

endmodule
