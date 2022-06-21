`timescale 1ns/1ns

module Bell202Modem	(	input					CLK_50M,

											output [7:0]	LED,

											output SPI_MOSI,
											output SPI_SCK,
											output DAC_CS,
											output DAC_CLR,
											output AMP_CS,
											output AMP_SHDN,
											output AD_CONV,
											input  AD_DOUT,

											input [3:0] BTN,
											input [3:0] SW,
											output 			FX2_IO1,
											output 			FX2_IO5,
											output 			FX2_IO9,

											output TX,
											input  RX);

wire signed [13:0] SigA;
wire signed [13:0] SigB;
wire signed [17:0] SigC;
wire signed [17:0] SigExtra;

wire DATA_RX;
wire DET_RX;

wire DATA_TX;
wire DET_TX;

wire VALID;
wire CLK_DATA_TX;
wire CLK_DATA_RX;

wire [7:0] SERIAL_DATA_TX;
wire [7:0] SERIAL_DATA_RX;

wire CLK_ADC;

wire ADCinit;
wire MOSI_A;
wire MOSI_B;
SPI Spi1 (	.CLK(CLK_50M),
          	.AorB(ADCinit),
            .MOSI_A(MOSI_A),
            .MOSI_B(MOSI_B),
            .MOSI(SPI_MOSI),
            .SCK(SPI_SCK));

GAIN #(.gain(1)) Gain1 (	.SCK(SPI_SCK),
            							.MOSI(MOSI_B),
						            	.CS(AMP_CS),
						          		.CLR(AMP_SHDN),
						            	.EN(!ADCinit));

ADC Adc1 (	.SCK(SPI_SCK),
						.MISO(AD_DOUT),
						.RUN(CLK_ADC),
						.A(SigA),
						.B(SigB));
assign AD_CONV = CLK_ADC;


DAC Dac1 (	.MOSI(MOSI_A),
          	.SCK(SPI_SCK),
        		.CS(DAC_CS),
        		.CLR(DAC_CLR),
						.EN(ADCinit && CLK_ADC),
						.A(SigExtra[17:6]),
						.B(SigC[17:6]));

DEMODULATOR DEM1  ( .CLK(CLK_ADC),
                    .SIG({SigA, 4'h0}),
                    .DATA(DATA_RX),
                    .DET(DET_RX),
										.EXTRA_SEL(SW),
										.EXTRA(SigExtra));

NCO NCO1 (  .CLK(CLK_ADC),
            .DET(DET_TX),
            .DATA(DATA_TX),
            .S(SigC));

DESERIALIZER DEC1  (.CLK(CLK_ADC),
		                .DATA(DATA_RX),
		                .DET(DET_RX),
										.VALID(VALID),
		                .CLK_out(CLK_DATA_RX),
		                .DATA_out(SERIAL_DATA_RX));

SERIALIZER DEC2		 (.CLK(CLK_ADC),
                    .DATA(SERIAL_DATA_TX),
                    .DET(DET_TX),
                    .EN(CLK_DATA_TX),
	                  .DATA_out(DATA_TX));

SERIAL_RX SER_RX ( 	.CLK(CLK_50M),
										.RX(RX),
									 	.DATA(SERIAL_DATA_TX),
									 	.CLK_out(CLK_DATA_TX));

SERIAL_TX SER_TX ( 	.DATA(SERIAL_DATA_RX),
             				.CLK(CLK_50M),
             				.EN(CLK_DATA_RX && VALID),
             				.TX(TX));

//assign DET_TX = DET_RX;
//assign DATA_TX = DATA_RX;

//------------testing-----stuff------------------------------------------------//

assign LED[3:0] = DET_RX ? 4'hF : 4'h0;
assign LED[7:4] = DET_TX ? 4'hF : 4'h0;

assign FX2_IO1 = DET_RX;
assign FX2_IO5 = CLK_DATA_RX;
assign FX2_IO9 = DATA_RX;


endmodule
