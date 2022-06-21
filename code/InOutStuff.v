
//--------SPI controll----------------------------------------------------------
module SPI( input       CLK,
            output reg  AorB,
            input       MOSI_A,
            input       MOSI_B,
            output      MOSI,
            output      SCK);

reg [7:0]  BootCnt;
always @(posedge SCK) begin
  if(BootCnt == 8'hFF)
    AorB <= 1;
  else begin
    BootCnt <= BootCnt + 1;
    AorB <= 0;
  end
end

reg [2:0]  cnt;
always @(posedge CLK)
	cnt <= cnt + 1;

assign SCK = cnt[2];
assign MOSI = AorB ? MOSI_A : MOSI_B;

endmodule //SPI

//--------DAC ------------------------------------------------------------------
module DAC( input               SCK,
            output reg          MOSI,
            output reg          CS,
            output              CLR,
            input               EN,
            input signed [11:0] A,
            input signed [11:0] B,
            output reg          AorB);

reg [19:0]  dataReg;
reg [5:0]   stateReg;
reg [4:0]   cnt;

initial begin
  CS = 1;
  AorB = 0;
  stateReg = 6'h19;
end

always @(negedge SCK) begin
  if(stateReg == 6'h19)
    if(!EN && !AorB)
      CS <= 1;
    else begin
      CS <= 0;
      AorB <= !AorB;
      stateReg <= 6'h00;
      //don't care, command + DAC A or B, data, don't care
      dataReg <= {8'h30 + AorB, (AorB ? {!A[11],A[10:0]} : {!B[11],B[10:0]} )};
  end else begin
    stateReg <= stateReg + 1;
    if(stateReg == 6'h18)
      CS <= 1;
    else if(stateReg < 6'h14) begin
      MOSI <= dataReg[19];
      dataReg <= dataReg << 1;
    end else if(stateReg < 6'h18)
      MOSI <= 0;
  end
end

assign CLR = 1;

endmodule //DAC

//--------GAIN setup------------------------------------------------------------
module GAIN(input       SCK,
            output reg  MOSI,
            output reg  CS,
            output      CLR,
            input       EN);

//default gain set to 0dB
parameter gain = 4'h1;

reg [3:0] stateReg;
reg [7:0] data = gain;

initial begin
  CS = 1;
  stateReg = 4'hF;
end

always @(negedge SCK) begin
  if(!EN)
    CS <= 1;
  else if(stateReg == 4'hF) begin
    stateReg <= 4'h0;
    data <= {gain[3:0], gain[3:0]};
  end else begin
    if(stateReg < 4'h8) begin
      CS <= 0;
      MOSI <= data[7];
      data <= {data[6:0], 1'bX};
    end else
      CS <= 1;
    stateReg <= stateReg + 1;
  end
end

assign CLR = 0;

endmodule //GAIN

//----ADC-----------------------------------------------------------------------
module ADC( input       SCK,
            input       MISO,
            output reg  RUN,
            output reg [13:0] A,
            output reg [13:0] B);

reg [13:0] ShiftReg;
reg [5:0] stateReg;

initial begin
  RUN = 0;
  stateReg = 6'h20;
end

always @(negedge SCK) begin
  if(stateReg == 6'h2F) begin
    stateReg <= 6'h3D;
    A <= ShiftReg;
  end else begin
    if(stateReg == 6'h3D)
      RUN <= 1;
    else if(stateReg == 6'h3E) begin
      RUN <= 0;
    end else if(stateReg < 6'h0E)
      ShiftReg <= {ShiftReg[12:0] , MISO};
    else if(stateReg == 6'h0F)
      B <= ShiftReg;
    else if((stateReg >= 6'h10) && (stateReg < 6'h1E))
      ShiftReg <= {ShiftReg[12:0] , MISO};

    stateReg <= stateReg + 1;
  end
end

endmodule //ADC

//----Serial Port Controller----------------------------------------------------
module SERIAL_TX (input [7:0]  DATA,
                  input        CLK,
                  input        EN,
                  output reg   TX);

//baud rate 9600 bit/s
parameter baudRate = 13'd5208;

reg [12:0] cnt;
reg EN_old;
reg [7:0] dataReg;
reg [3:0] stateReg;

initial begin
  cnt = 0;
  TX = 1;
  stateReg = 0;
end

always @(posedge CLK) begin
  if(stateReg == 0) begin
    if(EN & !EN_old) begin
      stateReg <= 4'hC;
      cnt <= baudRate;
      dataReg <= DATA;
      TX <= 0;
    end else begin
      TX <= 1;
    end
  end else begin
    if(cnt > 0) cnt <= cnt - 1;
    else begin
      cnt <= baudRate;
      stateReg <= stateReg - 1;
      TX <= dataReg[0];
      dataReg <= {1'bX, dataReg[7:1]};
    end
  end

  EN_old <= EN;
end

endmodule // SERIAL_TX

module SERIAL_RX (input         CLK,
                  input         RX,
                  output reg [7:0]  DATA,
                  output reg    CLK_out);

//baud rate 9600 bit/s
parameter baudRate = 13'd5208;

reg RX_d;
reg RX_sync;
reg RX_old;

reg [3:0]  stateReg;
reg [12:0] cnt;

initial begin
  stateReg = 0;
  CLK_out = 0;
  cnt <= 0;
end

always @(posedge CLK) begin
  RX_d <= RX;
  RX_sync <= RX_d;
  RX_old <= RX_sync;

  if(stateReg == 4'h0) begin

    //start condition
    if(RX_old & !RX_sync) begin
      stateReg <= 4'h9;
      cnt <= (baudRate*2'h3)>>1;
    end
  end else begin

    //wait required time
    if(cnt > 0) cnt <= cnt - 1;

    //write data
    else begin
      cnt <= baudRate;
      stateReg <= stateReg - 1;
      if(stateReg < 4'h9) DATA <= {RX_sync, DATA[7:1]};
    end
  end

  CLK_out <= (stateReg == 4'h0);
end

endmodule // SERIAL_RX
