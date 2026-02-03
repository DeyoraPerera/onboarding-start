`timescale 1ns/1ps
module spi_peripheral (
    input wire clk, //system clk
    input wire rst_n, //active-low reset
    input wire nCS, //SPI chip select
    input wire SCLK, //spi clock
    input wire COPI, //master Out, Slave in
    output reg  [7:0] en_reg_out_7_0,
    output reg  [7:0] en_reg_out_15_8,
    output reg  [7:0] en_reg_pwm_7_0,
    output reg  [7:0] en_reg_pwm_15_8,
    output reg  [7:0] pwm_duty_cycle
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

wire nCS_stable = nCS_sync[1]; //taking the stable value
wire SCLK_stable = SCLK_sync[1]; //taking the stable value
wire COPI_data = COPI_sync[0];


//edge detection

reg nCS_prev, SCLK_prev;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        nCS_prev  <= 1'b1; // idle high
        SCLK_prev <= 1'b0; // idle low
    end else begin
        nCS_prev  <= nCS_stable;
        SCLK_prev <= SCLK_stable;
    end
end

wire SCLK_rising = ~SCLK_prev & SCLK_stable;
wire nCS_rising  = ~nCS_prev & nCS_stable;


//bit counter and shift register

reg [4:0] bit_count; //up to 16 bits
reg [15:0] shift_reg; //holds r/w address, data

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bit_count <= 5'd0;
        shift_reg <= 16'b0;
    end else begin
        if (!nCS_stable) begin //spi transaction
            if (SCLK_rising) begin
                shift_reg <= {shift_reg[14:0], COPI_data};
                bit_count <= bit_count + 1'b1;
            end
        end else begin
            bit_count <= 5'd0; // reset for next transaction
        end
    end
end

//transaction handshake

reg transaction_ready;
reg transaction_processed;       

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        transaction_ready <= 1'b0;
    end else begin
        if(nCS_rising && bit_count == 16) begin
            transaction_ready <= 1'b1;
        end else if (transaction_processed) begin
            transaction_ready <= 1'b0;
        end
    end
end


//decoding transaction and updating registers

wire [6:0] reg_addr = shift_reg[14:8];
wire [7:0] data = shift_reg[7:0];
wire write_bit = shift_reg[15];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        en_reg_out_7_0   <= 8'h00;
        en_reg_out_15_8  <= 8'h00;
        en_reg_pwm_7_0   <= 8'h00;
        en_reg_pwm_15_8  <= 8'h00;
        pwm_duty_cycle   <= 8'h00;
        transaction_processed <= 1'b0;
    end else if (transaction_ready && !transaction_processed) begin 
        //updating reg only after entire transaction complete
        if (write_bit && reg_addr <= MAX_ADDRESS) begin
            case (reg_addr)
                7'h00: en_reg_out_7_0   <= data;
                7'h01: en_reg_out_15_8  <= data;
                7'h02: en_reg_pwm_7_0   <= data;
                7'h03: en_reg_pwm_15_8  <= data;
                7'h04: pwm_duty_cycle   <= data;
                default: ;   
            endcase
        end
        transaction_processed <= 1'b1;
    end else if (!transaction_ready && transaction_processed) begin
        transaction_processed <= 1'b0;
    end
end

endmodule
            














