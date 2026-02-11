
`default_nettype none

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

localparam [6:0] MAX_ADDRESS = 7'd4; //max register address


//Fixed 2-FF Synchronizers 

reg nCS_meta,  nCS_sync;
reg SCLK_meta, SCLK_sync;
reg COPI_meta, COPI_sync;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        nCS_meta  <= 1'b1;  // idle high
        nCS_sync  <= 1'b1;

        SCLK_meta <= 1'b0;  // idle low (mode 0)
        SCLK_sync <= 1'b0;

        COPI_meta <= 1'b0;
        COPI_sync <= 1'b0;
    end else begin
        nCS_meta  <= nCS;
        nCS_sync  <= nCS_meta;

        SCLK_meta <= SCLK;
        SCLK_sync <= SCLK_meta;

        COPI_meta <= COPI;
        COPI_sync <= COPI_meta;
    end
end

// Use only stage 2 outputs
wire nCS_stable  = nCS_sync;
wire SCLK_stable = SCLK_sync;
wire COPI_data   = COPI_sync;


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
                bit_count <= bit_count + 5'b1;
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
        if(nCS_rising && bit_count == 5'd16) begin
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
            














