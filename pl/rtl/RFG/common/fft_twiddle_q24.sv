`timescale 1ns/1ps

// Q2.24 twiddle lookup for radix-2 FFT sizes up to 512 points.
module e01_fft_twiddle_q24 (
    input  wire [8:0]               i_phase_index, // Phase index on a 512-step full-circle grid
    output reg  signed [25:0]       o_cosine,      // cos(2*pi*index/512) in signed Q2.24
    output reg  signed [25:0]       o_sine         // -sin(2*pi*index/512) in signed Q2.24
);
    function automatic signed [25:0] cosine_quarter_q24(input [7:0] index);
        begin
            case (index)
                8'd0: cosine_quarter_q24 = 26'sd16777216;
                8'd1: cosine_quarter_q24 = 26'sd16775953;
                8'd2: cosine_quarter_q24 = 26'sd16772163;
                8'd3: cosine_quarter_q24 = 26'sd16765847;
                8'd4: cosine_quarter_q24 = 26'sd16757007;
                8'd5: cosine_quarter_q24 = 26'sd16745643;
                8'd6: cosine_quarter_q24 = 26'sd16731757;
                8'd7: cosine_quarter_q24 = 26'sd16715352;
                8'd8: cosine_quarter_q24 = 26'sd16696429;
                8'd9: cosine_quarter_q24 = 26'sd16674992;
                8'd10: cosine_quarter_q24 = 26'sd16651044;
                8'd11: cosine_quarter_q24 = 26'sd16624588;
                8'd12: cosine_quarter_q24 = 26'sd16595628;
                8'd13: cosine_quarter_q24 = 26'sd16564169;
                8'd14: cosine_quarter_q24 = 26'sd16530216;
                8'd15: cosine_quarter_q24 = 26'sd16493773;
                8'd16: cosine_quarter_q24 = 26'sd16454846;
                8'd17: cosine_quarter_q24 = 26'sd16413442;
                8'd18: cosine_quarter_q24 = 26'sd16369565;
                8'd19: cosine_quarter_q24 = 26'sd16323224;
                8'd20: cosine_quarter_q24 = 26'sd16274424;
                8'd21: cosine_quarter_q24 = 26'sd16223173;
                8'd22: cosine_quarter_q24 = 26'sd16169479;
                8'd23: cosine_quarter_q24 = 26'sd16113350;
                8'd24: cosine_quarter_q24 = 26'sd16054795;
                8'd25: cosine_quarter_q24 = 26'sd15993821;
                8'd26: cosine_quarter_q24 = 26'sd15930439;
                8'd27: cosine_quarter_q24 = 26'sd15864658;
                8'd28: cosine_quarter_q24 = 26'sd15796488;
                8'd29: cosine_quarter_q24 = 26'sd15725939;
                8'd30: cosine_quarter_q24 = 26'sd15653022;
                8'd31: cosine_quarter_q24 = 26'sd15577747;
                8'd32: cosine_quarter_q24 = 26'sd15500126;
                8'd33: cosine_quarter_q24 = 26'sd15420172;
                8'd34: cosine_quarter_q24 = 26'sd15337895;
                8'd35: cosine_quarter_q24 = 26'sd15253308;
                8'd36: cosine_quarter_q24 = 26'sd15166424;
                8'd37: cosine_quarter_q24 = 26'sd15077256;
                8'd38: cosine_quarter_q24 = 26'sd14985817;
                8'd39: cosine_quarter_q24 = 26'sd14892122;
                8'd40: cosine_quarter_q24 = 26'sd14796184;
                8'd41: cosine_quarter_q24 = 26'sd14698017;
                8'd42: cosine_quarter_q24 = 26'sd14597637;
                8'd43: cosine_quarter_q24 = 26'sd14495059;
                8'd44: cosine_quarter_q24 = 26'sd14390298;
                8'd45: cosine_quarter_q24 = 26'sd14283370;
                8'd46: cosine_quarter_q24 = 26'sd14174291;
                8'd47: cosine_quarter_q24 = 26'sd14063077;
                8'd48: cosine_quarter_q24 = 26'sd13949745;
                8'd49: cosine_quarter_q24 = 26'sd13834313;
                8'd50: cosine_quarter_q24 = 26'sd13716797;
                8'd51: cosine_quarter_q24 = 26'sd13597215;
                8'd52: cosine_quarter_q24 = 26'sd13475586;
                8'd53: cosine_quarter_q24 = 26'sd13351928;
                8'd54: cosine_quarter_q24 = 26'sd13226258;
                8'd55: cosine_quarter_q24 = 26'sd13098597;
                8'd56: cosine_quarter_q24 = 26'sd12968963;
                8'd57: cosine_quarter_q24 = 26'sd12837376;
                8'd58: cosine_quarter_q24 = 26'sd12703856;
                8'd59: cosine_quarter_q24 = 26'sd12568423;
                8'd60: cosine_quarter_q24 = 26'sd12431097;
                8'd61: cosine_quarter_q24 = 26'sd12291899;
                8'd62: cosine_quarter_q24 = 26'sd12150850;
                8'd63: cosine_quarter_q24 = 26'sd12007971;
                8'd64: cosine_quarter_q24 = 26'sd11863283;
                8'd65: cosine_quarter_q24 = 26'sd11716809;
                8'd66: cosine_quarter_q24 = 26'sd11568571;
                8'd67: cosine_quarter_q24 = 26'sd11418590;
                8'd68: cosine_quarter_q24 = 26'sd11266890;
                8'd69: cosine_quarter_q24 = 26'sd11113493;
                8'd70: cosine_quarter_q24 = 26'sd10958422;
                8'd71: cosine_quarter_q24 = 26'sd10801701;
                8'd72: cosine_quarter_q24 = 26'sd10643353;
                8'd73: cosine_quarter_q24 = 26'sd10483403;
                8'd74: cosine_quarter_q24 = 26'sd10321873;
                8'd75: cosine_quarter_q24 = 26'sd10158790;
                8'd76: cosine_quarter_q24 = 26'sd9994176;
                8'd77: cosine_quarter_q24 = 26'sd9828057;
                8'd78: cosine_quarter_q24 = 26'sd9660458;
                8'd79: cosine_quarter_q24 = 26'sd9491405;
                8'd80: cosine_quarter_q24 = 26'sd9320922;
                8'd81: cosine_quarter_q24 = 26'sd9149035;
                8'd82: cosine_quarter_q24 = 26'sd8975771;
                8'd83: cosine_quarter_q24 = 26'sd8801154;
                8'd84: cosine_quarter_q24 = 26'sd8625213;
                8'd85: cosine_quarter_q24 = 26'sd8447972;
                8'd86: cosine_quarter_q24 = 26'sd8269459;
                8'd87: cosine_quarter_q24 = 26'sd8089701;
                8'd88: cosine_quarter_q24 = 26'sd7908725;
                8'd89: cosine_quarter_q24 = 26'sd7726557;
                8'd90: cosine_quarter_q24 = 26'sd7543226;
                8'd91: cosine_quarter_q24 = 26'sd7358759;
                8'd92: cosine_quarter_q24 = 26'sd7173184;
                8'd93: cosine_quarter_q24 = 26'sd6986529;
                8'd94: cosine_quarter_q24 = 26'sd6798821;
                8'd95: cosine_quarter_q24 = 26'sd6610090;
                8'd96: cosine_quarter_q24 = 26'sd6420363;
                8'd97: cosine_quarter_q24 = 26'sd6229669;
                8'd98: cosine_quarter_q24 = 26'sd6038037;
                8'd99: cosine_quarter_q24 = 26'sd5845495;
                8'd100: cosine_quarter_q24 = 26'sd5652074;
                8'd101: cosine_quarter_q24 = 26'sd5457801;
                8'd102: cosine_quarter_q24 = 26'sd5262706;
                8'd103: cosine_quarter_q24 = 26'sd5066819;
                8'd104: cosine_quarter_q24 = 26'sd4870169;
                8'd105: cosine_quarter_q24 = 26'sd4672785;
                8'd106: cosine_quarter_q24 = 26'sd4474698;
                8'd107: cosine_quarter_q24 = 26'sd4275936;
                8'd108: cosine_quarter_q24 = 26'sd4076531;
                8'd109: cosine_quarter_q24 = 26'sd3876512;
                8'd110: cosine_quarter_q24 = 26'sd3675909;
                8'd111: cosine_quarter_q24 = 26'sd3474752;
                8'd112: cosine_quarter_q24 = 26'sd3273072;
                8'd113: cosine_quarter_q24 = 26'sd3070900;
                8'd114: cosine_quarter_q24 = 26'sd2868265;
                8'd115: cosine_quarter_q24 = 26'sd2665197;
                8'd116: cosine_quarter_q24 = 26'sd2461729;
                8'd117: cosine_quarter_q24 = 26'sd2257890;
                8'd118: cosine_quarter_q24 = 26'sd2053710;
                8'd119: cosine_quarter_q24 = 26'sd1849222;
                8'd120: cosine_quarter_q24 = 26'sd1644455;
                8'd121: cosine_quarter_q24 = 26'sd1439440;
                8'd122: cosine_quarter_q24 = 26'sd1234209;
                8'd123: cosine_quarter_q24 = 26'sd1028791;
                8'd124: cosine_quarter_q24 = 26'sd823219;
                8'd125: cosine_quarter_q24 = 26'sd617523;
                8'd126: cosine_quarter_q24 = 26'sd411733;
                8'd127: cosine_quarter_q24 = 26'sd205882;
                8'd128: cosine_quarter_q24 = 26'sd0;
                default: cosine_quarter_q24 = 26'sd0;
            endcase
        end
    endfunction

    always @(*) begin
        if (i_phase_index <= 9'd128) begin
            o_cosine = cosine_quarter_q24(i_phase_index[7:0]);
            o_sine = -cosine_quarter_q24(8'd128-i_phase_index[7:0]);
        end else if (i_phase_index <= 9'd255) begin
            o_cosine = -cosine_quarter_q24(9'd256-i_phase_index);
            o_sine = -cosine_quarter_q24(i_phase_index-9'd128);
        end else begin
            o_cosine = 26'sd0;
            o_sine = 26'sd0;
        end
    end
endmodule

