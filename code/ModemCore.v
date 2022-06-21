
module OSC( input CLK,
            output signed [17:0] S,
            output signed [17:0] C);

parameter n_bits = 12;
parameter k = 8;
parameter Ac = 16;

reg signed [17:0] X = 17'h1D000;
reg signed [17:0] Y = 17'h00000;

wire signed [17:0] X1;
assign X1 = X - ((k * X) >>> n_bits) + Y;

always @(negedge CLK) begin
  Y <= X1 - ((k * X1 ) >>> n_bits ) - X;
  X <= X1;
end

assign C = Y * Ac;
assign S = X;

endmodule //OSC




module MULT(  output signed [17:0] P,
              input  signed [17:0] A,
              input  signed [17:0] B);

wire signed [35:0] P36;
assign P = (P36>>>17);
MULT18X18 mult (	.P(P36),
									.A(A),
									.B(B));

endmodule //MULT




module LPF( input CLK,
            input      signed [17:0] IN,
            output reg signed [17:0] OUT);

parameter k = 6;
always @(posedge CLK) OUT <= OUT - (OUT>>>k) + (IN>>>(k-1));

endmodule //LPF




module DEMODULATOR  ( input             CLK,
                      input      [17:0] SIG,
                      output reg        DATA,
                      output reg        DET,
                      input      [3:0]  EXTRA_SEL,
                      output reg [17:0] EXTRA);

wire signed [17:0] S1k2;
wire signed [17:0] C1k2;
wire signed [17:0] S2k2;
wire signed [17:0] C2k2;

wire signed [17:0] mixS1k2;
wire signed [17:0] mixC1k2;
wire signed [17:0] mixS2k2;
wire signed [17:0] mixC2k2;

wire signed [17:0] IFS1k2;
wire signed [17:0] IFC1k2;
wire signed [17:0] IFS2k2;
wire signed [17:0] IFC2k2;

//these are not signed numbers, always positive!
wire signed [17:0] BBS1k2;
wire signed [17:0] BBC1k2;
wire signed [17:0] BBS2k2;
wire signed [17:0] BBC2k2;

//these are not signed numbers, always positive!
wire signed [17:0] Simb1k2;
wire signed [17:0] Simb2k2;


//---- EXTRA STUFF-------------------------------
reg signed [17:0] DACout;
always @(posedge CLK) begin
	case (EXTRA_SEL)
		4'h0: EXTRA <= S1k2;
		4'h1: EXTRA <= C1k2;
		4'h2: EXTRA <= S2k2;
		4'h3: EXTRA <= C2k2;
		4'h4: EXTRA <= mixS1k2;
		4'h5: EXTRA <= mixC1k2;
		4'h6: EXTRA <= mixS2k2;
		4'h7: EXTRA <= mixC2k2;
		4'h8: EXTRA <= IFS1k2;
		4'h9: EXTRA <= IFC1k2;
		4'hA: EXTRA <= IFS2k2;
		4'hB: EXTRA <= IFC2k2;
		4'hC: EXTRA <= BBS1k2;
		4'hD: EXTRA <= BBC1k2;
		4'hE: EXTRA <= BBS2k2;
		4'hF: EXTRA <= BBC2k2;
	endcase
end
//----------------------------------

//Oscillator 1.2kHz
OSC #(.k(8), .Ac(16)) Osc1 (.CLK(CLK),
				 										.S(S1k2),
				 									 	.C(C1k2));

//Oscillator 2.2kHz
OSC #(.k(26), .Ac(9)) Osc2 (.CLK(CLK),
				 									  .S(S2k2),
				 										.C(C2k2));

//Signal mixed with tone
MULT MULT1 (	.P(mixS1k2),
							.A(S1k2),
							.B(SIG));

MULT MULT2 (	.P(mixC1k2),
							.A(C1k2),
							.B(SIG));

MULT MULT3 (	.P(mixS2k2),
							.A(S2k2),
							.B(SIG));

MULT MULT4 (	.P(mixC2k2),
							.A(C2k2),
							.B(SIG));

//Intermediate frequency
LPF LPF1 ( 	.CLK(CLK),
          	.IN(mixS1k2),
	          .OUT(IFS1k2));

LPF LPF2 ( 	.CLK(CLK),
          	.IN(mixC1k2),
	          .OUT(IFC1k2));

LPF LPF3 ( 	.CLK(CLK),
          	.IN(mixS2k2),
	          .OUT(IFS2k2));

LPF LPF4 ( 	.CLK(CLK),
          	.IN(mixC2k2),
		        .OUT(IFC2k2));

//Baseband frequency
MULT MULT5 (	.P(BBS1k2),
							.A(IFS1k2),
							.B(IFS1k2));

MULT MULT6 (	.P(BBC1k2),
							.A(IFC1k2),
							.B(IFC1k2));

MULT MULT7 (	.P(BBS2k2),
							.A(IFS2k2),
							.B(IFS2k2));

MULT MULT8 (	.P(BBC2k2),
							.A(IFC2k2),
							.B(IFC2k2));

//Symbol 1k2
assign Simb1k2 = BBS1k2 + BBC1k2;

//Symbol 2k2
assign Simb2k2 = BBS2k2 + BBC2k2;

//DATA demodulated
always @(posedge CLK) DATA <= ((Simb2k2 - Simb1k2) + (DATA ? +18'h0000F : -18'h0000F )) > 0;

//DET is signal present?
wire DET_raw;
assign DET_raw = (Simb1k2 + Simb2k2) > 18'h0004F;


//remove glitches from DET signal
reg [4:0] cnt;
always @(posedge CLK) begin
  if(cnt != 0) begin
    if(cnt == 4'h1)
      DET <= DET_raw;
    cnt <= cnt - 1;
  end else if(DET_raw != DET)
    cnt <= 5'h1F; //5 cycles of clock before switching DET
end

endmodule //DEMODULATOR




module NCO( input CLK,
            input DET,
            input DATA,
            output signed [17:0] S);

reg DATA_old;

initial begin
  DATA_old  = DATA;
end

parameter n_bits = 12;

//2.2k sine
parameter k1 = 8;
parameter Ac1 = 8;

//1.2k sine
parameter k2 = 26;
parameter Ac2 = 4;

reg signed [17:0] X;
reg signed [17:0] Y;

wire signed [17:0] X1;
assign X1 = X - (( (DATA ? k2 : k1) * X) >>> n_bits) + Y;

always @(negedge CLK) begin
  if( (DATA != DATA_old)) begin
    DATA_old <= DATA;
    Y <= (DATA ? (Y*29)>>>4 : (Y*9)>>>4); //joint condition
  end else begin
    if(DET) begin
      Y <= X1 - (( (DATA ? k2 : k1) * X1 ) >>> n_bits ) - X;
      X <= X1;
    end else begin
      X <= 17'h0E800;
      Y <= 17'h00000;
    end
  end
end

assign S = Y * (DATA ? Ac2 : Ac1);

endmodule //NCO




module DESERIALIZER(  input CLK,
                      input DATA,
                      input DET,
                      output reg CLK_out,
                      output reg VALID,
                      output reg [7:0] DATA_out);

reg [7:0] cnt;
reg DATA_old;
reg [2:0] bitCnt;
reg [2:0] stuffedBit;

initial begin
  DATA_out = 8'hFF;
  cnt = 0;
  bitCnt = 0;
  stuffedBit = 0;
  VALID = 0;
end

always @(posedge CLK) begin

  //signal detected
  if(DET) begin

    //transition of DATA --> bit LOW
    if(DATA != DATA_old) begin
      cnt <= 8'd0; //reset counter
      stuffedBit <= 0;

        //stuffedBit < 5 --> bit LOW
        if(stuffedBit < 5) begin
          DATA_out <= {1'b0, DATA_out[7:1]};
          bitCnt <= bitCnt + 1;
          if(bitCnt == 3'h0)
            VALID <= 1;

        //stuffedBit == 5 --> bit stuffing --> do nothing
        //stuffedBit > 5 --> FLAG
        end else if(stuffedBit > 5) begin
          VALID <= 0; //data not valid
          DATA_out <= {1'b0, DATA_out[7:1]};
          bitCnt <= 3'h7;
        end

    //no transition of DATA --> bit HIGH
    end else begin
      //wait the required time (1.2 kbit/s)
      if(cnt < 8'd153) begin
        cnt <= cnt + 1;
      //no transition in that time --> low bit
      end else begin
        cnt <= 8'd51;
        DATA_out <= {1'b1, DATA_out[7:1]};
        bitCnt <= bitCnt + 1;
        if(bitCnt == 3'h0)
          VALID <= 1;
        stuffedBit <= stuffedBit + 1;
      end
    end

    //at 8th bit data is ready
    CLK_out <= (bitCnt == 3'h7) && (cnt < 16);


  //signal not detected
  end else begin
    bitCnt <= 0;
    cnt <= 0;
    stuffedBit <= 0;
  end

  DATA_old <= DATA;
end

endmodule //DESERIALIZER




module SERIALIZER(  input       CLK,
                    input [7:0] DATA,
                    output reg  DET,
                    input       EN,
                    output reg  DATA_out);

reg [4:0]  stateReg;
reg [7:0]  cnt;
reg [15:0] dataReg;
reg [3:0]  stuffedBit;
reg EN_old;

initial begin
  stateReg = 0;
  DET = 0;
  stuffedBit = 0;
end

always @(posedge CLK) begin
  if(stateReg == 0) begin
    if(EN & !EN_old) begin
      stateReg <= 5'h11;
      cnt <= 8'd102;
      stuffedBit <= 0;
      DET <= 1;
      //DATA_out <= 0;
      dataReg <= {DATA[7:0], 8'h7E};
    end else begin
      DET <= 0;
    end
  end else begin
    if(cnt > 0) cnt <= cnt - 1;
    else begin
      cnt <= 8'd102;
      if((stuffedBit < 5) || (stateReg > 5'h8)) begin
        if(!dataReg[0]) begin
          DATA_out <= !DATA_out;
          stuffedBit <= 0;
        end else begin
          stuffedBit <= stuffedBit + 1;
        end

        dataReg <= {1'bX, dataReg[15:1]};
        stateReg <= stateReg - 1;
      end else begin
        DATA_out <= !DATA_out;
        stuffedBit <= 0;
      end
    end
  end

  EN_old <= EN;
end

endmodule //DESERIALIZER
