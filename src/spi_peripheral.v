`timescale 1ns/1ps
module spi_peripheral (
    input wire clk, //system clk
    input wire rst_n, //active-low reset
    input wire nCS, //SPI chip select
    input wire SCLK, //spi clock
    input wire COPI, //master Out, Slave in
    output reg [7:0] uo_out, //ex output reg
    output reg [7:0] uio_out //output reg 2
);

localparam MAX_ADDRESS = 4; //max register address

//signal synchronization

reg [1:0] nCS_sync, SCLK_sync, COPI_sync;// 2 stage flip flops

always @ (posedge clk or negedge rst_n) begin //executes on every posedge and if rst_n goes low

    if(!rst_n) begin
        nCS_sync <= 2'b11; //both ff initialized to high bc active low
        SCLK_sync <= 2'b00; 
        COPI_sync <= 2'b00;
    end else begin
        //concatenating 2 values prev value from first flip-flop and current raw async input
        nCS_sync <= {nCS_sync[0], nCS}; 
        SCLK_sync <= {SCLK_sync[0], SCLK};
        COPI_sync <= {COPI_sync[0], COPI};
    end

end

wire nCS_sync2 = nCS_sync[1]; //taking the stable value
wire SCLK_sync2 = SCLK_sync[1];
wire COPI_sync2 = COPI_sync[1];


//edge detection

//when rising edge happens: prev is 0 and sync2 is 1
reg SCLK_prev, nCS_prev; //stores prev state of signals to help detect edges
wire SCLK_rising = ~SCLK_prev & SCLK_sync2;
wire nCS_rising = ~nCS_prev & nCS_sync2;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        SCLK_prev <= 1'b0; //idle
        nCS_prev <= 1'b1; //not selected
    end else begin
        SCLK_prev <= SCLK_sync2;
        nCS_prev <= nCS_sync2;
    end
end

//bit counter and shift register

reg [4:0] bit_count; //up to 16 bits
reg [15:0] shift_reg; //holds r/w address, data
reg transaction_ready;
reg transaction_processed;//for handshaking

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bit_count <= 0;
        shift_reg <= 16'b0;
        transaction_ready <= 1'b0;
    end else begin
        transaction_ready <= 1'b0; //clearing by default

        if (!nCS_sync2) begin //spi transaction
            if (SCLK_rising && bit_count < 16) begin
                shift_reg <= {shift_reg[14:0], COPI_sync2};
                bit_count <= bit_count + 1;
            end
        end else begin
            //when nCS goes high, checking if we got exactly 16 bits
            if (nCS_rising && (bit_count == 16)) begin 
                transaction_ready <= 1'b1;
            end else if (transaction_processed) begin
                transaction_ready <= 1'b0;
            end
            bit_count <= 0; // reset for next transaction
        end
    end
end


//decoding transaction and updating registers

wire [6:0] reg_addr = shift_reg[14:8];
wire [7:0] data = shift_reg[7:0];
wire write_bit = shift_reg[15];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        uo_out  <= 8'h00;
        uio_out <= 8'h00;
        transaction_processed <= 1'b0;
    end else if (transaction_ready && !transaction_processed) begin 
        //updating reg only after entire transaction complete
        if (write_bit && reg_addr <= MAX_ADDRESS) begin
            case (reg_addr)
                7'h00: uo_out  <= data;
                7'h01: uio_out <= data;
                7'h02: uo_out  <= data;   
                7'h03: uio_out <= data;  
                7'h04: uo_out  <= data;   
                default: ;   
            endcase
        end
        transaction_processed <= 1'b1;
    end else if (!transaction_ready) begin
        transaction_processed <= 1'b0;
    end
end

endmodule
            














