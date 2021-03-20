`default_nettype none

module top_module 
  (
    input wire i_clk,
    input wire i_rst_n,
    input wire i_rx,
    output wire o_tx
  );
  
  logic [7:0] rx_byte;
  logic rx_byte_valid, rx_err;
  
  // UART RX
  uart_rx #(
    .CLK_FREQ_MHZ	(100_000_000),
    .BAUD_RATE		(3_000_000),
    .OVERSAMPLE_RATE(16),
    .NUM_DATA_BITS	(8),
    .PARITY_ON		(1),
    .PARITY_EO		(1)
  ) uart_rx_module (
    .i_clk,
    .i_rst_n,
    .i_rx,
    .o_rx_byte		(rx_byte),
    .o_rx_byte_valid(rx_byte_valid),
    .o_rx_err		(rx_err)
  );
  
  logic [7:0] cmd_reg;
  logic cmd_reg_valid;
  logic [7:0] burst_cnt;
  logic burst_cnt_valid;
  logic rx_msg_err;
  logic cordic_start;
  logic [47:0] cordic_theta;
  logic cordic_pipeline_en, cordic_rst_n;
  
  // RX MSG
  uart_rx_msg uart_rx_msg_module (
    .i_clk,
    .i_rst_n,
    
    // in from uart_rx
    .i_rx_byte			(rx_byte),
    .i_rx_byte_valid	(rx_byte_valid),
    .i_rx_err			(rx_err),
    
    // out to uart_tx_msg
    .o_cmd_reg			(cmd_reg),
    .o_cmd_reg_valid	(cmd_reg_valid),
    .o_burst_cnt		(burst_cnt),
    .o_burst_cnt_valid  (burst_cnt_valid),
    .o_rx_msg_err		(rx_msg_err),
    
    // out to cordic
    .o_cordic_start			(cordic_start),
    .o_cordic_theta			(cordic_theta),
    .o_cordic_pipeline_en	(cordic_pipeline_en),
    .o_cordic_rst_n 		(cordic_rst_n)
  );
  
  logic cordic_reset;
  assign cordic_reset = i_rst_n && cordic_rst_n;
  
  logic cordic_done;
  logic [47:0] cordic_sin_theta, cordic_cos_theta;
  
  // CORDIC
  cordic_sincos #(
    .STAGES		(48),
    .BITS		(48)
  ) cordic_sincos_module (
  	.i_clk,
    .i_rst_n		(cordic_reset),
    .i_pipeline_en	(cordic_pipeline_en),
    .i_start		(cordic_start),
    .i_theta		(cordic_theta),            
    .o_done			(cordic_done),
    .o_sin_theta	(cordic_sin_theta),  
    .o_cos_theta  	(cordic_cos_theta)   
  );
 
  logic [7:0] tx_byte;
  logic tx_byte_valid;
  
  // TX MSG
  uart_tx_msg uart_tx_msg_module (
    .i_clk,
    .i_rst_n,
    
    // from uart rx msg
    .i_cmd_reg		    (cmd_reg),
    .i_cmd_valid	    (cmd_reg_valid),
    .i_burst_cnt	    (burst_cnt),
    .i_burst_cnt_valid  (burst_cnt_valid),
    .i_rx_msg_err	    (rx_msg_err),
    
    // from cordic
    .i_cordic_sin_theta	(cordic_sin_theta),
    .i_cordic_cos_theta	(cordic_cos_theta),
    .i_cordic_done		(cordic_done),
    
    // to uart tx
    .o_tx_byte			(tx_byte),
    .o_tx_byte_valid	(tx_byte_valid)
  );
  
  logic fifo_wr_en, fifo_rd_en, fifo_full, fifo_empty;
  logic [7:0] fifo_wr_data, fifo_rd_data;
  
  assign fifo_wr_en = ((tx_byte_valid)&&(!fifo_full));
  assign fifo_wr_data = tx_byte;
  
  // FIFO between TX MSG and TX
  sync_fifo #(
    .WIDTH  (8),
    .DEPTH  (64)
  ) sync_fifo_inst (
    .i_clk,
    .i_rst_n,
    .i_wr_en    (fifo_wr_en),
    .i_rd_en    (fifo_rd_en),
    .i_wr_data  (fifo_wr_data),
    .o_rd_data  (fifo_rd_data),
    .o_full     (fifo_full),
    .o_empty    (fifo_empty)
  );
  
  // UART TX
    uart_tx #(
      .CLK_FREQ_MHZ 	(100_000_000),
      .BAUD_RATE		(3_000_000),
      .NUM_DATA_BITS	(8),
      .PARITY_ON		(1),
      .PARITY_EO		(1),
      .NUM_STOP_BITS	(1)
    ) uart_tx_module (
      .i_clk,
      .i_rst_n,
      .i_fifo_empty	    (fifo_empty),
      .i_fifo_rd_data   (fifo_rd_data),
      .o_fifo_rd_en     (fifo_rd_en),
      .o_tx
    );
    
endmodule