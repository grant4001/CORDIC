`default_nettype none

module uart_rx_msg (
    input wire 		  				i_clk,
    input wire 		  				i_rst_n,
    
    // in from uart_rx
  	input wire  [7:0] 				i_rx_byte,
    input wire 		  				i_rx_byte_valid,
    input wire						i_rx_err,
    
    // out to uart_tx_msg
    output reg	[7:0]				o_cmd_reg,
    output reg						o_cmd_reg_valid,
  output reg	[7:0]				o_burst_cnt,
    output reg						o_rx_msg_err,
    
    // out to cordic
    output reg 	  					o_cordic_start,
  	output reg 	[47:0]				o_cordic_theta,
    output reg						o_cordic_pipeline_en,
    output reg						o_cordic_rst_n  	
  );
  
  // LFSR module used to calculate CRC-8
  logic lfsr_count_en, lfsr_load;
  logic [7:0] lfsr_seed, lfsr_reg;
  
  lfsr #(
    .N		(8),
    .poly	(8'h3c)
  ) lfsr_inst (
    .i_clk,
    .i_rst_n,
    .i_count_en (lfsr_count_en),
    .i_load		(lfsr_load),
    .i_seed		(lfsr_seed),
    .o_lfsr		(lfsr_reg)
  );
  
  // LFSR control FSM
  typedef enum {LFSR_STATE_LOAD, 
                LFSR_STATE_COUNT} lfsr_state_t;
  lfsr_state_t lfsr_state;
  logic [3:0] count2eight;
  logic crc_byte_done;

  always_ff @(posedge i_clk or negedge i_rst_n)
    if (!i_rst_n) begin
      	count2eight			<= '0;
      	crc_byte_done		<= 1'b0;
      	lfsr_load			<= 1'b0;
        lfsr_count_en		<= 1'b0;
        lfsr_seed			<= '0;
      	lfsr_state			<= LFSR_STATE_LOAD;
    end else begin
      
      crc_byte_done		<= 1'b0;
      lfsr_load			<= 1'b0;
      lfsr_count_en		<= 1'b0;
      
      case (lfsr_state) 
        LFSR_STATE_LOAD: begin
          if (i_rx_byte_valid) begin
            lfsr_load	<= 1'b1;
            lfsr_seed	<= lfsr_reg^i_rx_byte;
			lfsr_state	<= LFSR_STATE_COUNT;
          end
        end
        LFSR_STATE_COUNT: begin
          lfsr_count_en	<= 1'b1;
          count2eight	<= count2eight + 1;
          if (count2eight == 7) begin
            count2eight		<= '0;
            crc_byte_done	<= 1'b1;
            lfsr_state		<= LFSR_STATE_LOAD;
          end
        end
        default: begin
          crc_byte_done		<= 1'b0;
          count2eight		<= '0;
          lfsr_load			<= 1'b0;
          lfsr_count_en		<= 1'b0;
          lfsr_seed			<= '0;
          lfsr_state		<= LFSR_STATE_LOAD;
        end
          
      endcase
    end
  
  // Message codes
  localparam [7:0] BYTE_HEADER			= 8'h5a;
  localparam [7:0] CMD_SINGLE_TRANS 	= 8'hd1;
  localparam [7:0] CMD_BURST_TRANS 		= 8'hd2;
  localparam [7:0] CMD_DISABLE 			= 8'he1;
  localparam [7:0] CMD_ENABLE			= 8'he2;
  
  // CMD sequence FSM
  typedef enum {STATE_HEADER,
                STATE_CMD,
                STATE_SINGLE_TRANS,
                STATE_BURST_TRANS,
                STATE_BURST_TRANS_II,
                STATE_DISABLE,
                STATE_ENABLE,
                STATE_CRC_CHECK
                } cmd_seq_state_t;
  
  cmd_seq_state_t cmd_seq_state;
  
  // RX msg registers
  logic [2:0] count2six;
  logic [7:0] count2burst;
  
  always_ff @(posedge i_clk or negedge i_rst_n)
    
    if (!i_rst_n)
      begin
        cmd_seq_state		<= STATE_HEADER;
        count2six			<= '0;
        count2burst			<= '0;
        o_burst_cnt			<= '0;
        o_cmd_reg			<= '0;
        o_cmd_reg_valid		<= 1'b0;
        o_rx_msg_err		<= 1'b0;
        o_cordic_start		<= 1'b0;
        o_cordic_theta		<= '0;
        o_cordic_pipeline_en<= 1'b1;
        o_cordic_rst_n		<= 1'b1;
      end
    else begin
      
      o_cmd_reg				<= '0;
      o_cmd_reg_valid		<= 1'b0;
      o_rx_msg_err			<= 1'b0;
      o_cordic_start		<= 1'b0;
      o_cordic_theta		<= '0;
      o_cordic_pipeline_en	<= o_cordic_pipeline_en;
      o_cordic_rst_n		<= 1'b1;
      
      case (cmd_seq_state)
        
        STATE_HEADER: begin
          cmd_seq_state	<= STATE_HEADER;
          count2six		<= '0;
          o_burst_cnt	<= '0;
          count2burst	<= '0;
          if (i_rx_byte_valid && i_rx_byte == BYTE_HEADER)
            cmd_seq_state	<= STATE_CMD;
        end
        
        STATE_CMD: begin
          if (i_rx_byte_valid) begin
            case (i_rx_byte)
              CMD_SINGLE_TRANS: cmd_seq_state	<= STATE_SINGLE_TRANS;
              CMD_BURST_TRANS:  cmd_seq_state	<= STATE_BURST_TRANS;
              CMD_DISABLE: 		cmd_seq_state	<= STATE_DISABLE;
              CMD_ENABLE: 		cmd_seq_state	<= STATE_ENABLE;
              default:			cmd_seq_state	<= STATE_HEADER;
            endcase
            o_cmd_reg		<= i_rx_byte;
            o_cmd_reg_valid	<= 1'b1;
          end
        end
        
        STATE_SINGLE_TRANS: begin
          if (i_rx_byte_valid) begin
            o_cordic_theta	<= {i_rx_byte, o_cordic_theta[47:8]};
            count2six		<= count2six + 1;
            if (count2six == 5) begin
              count2six			<= '0;
              o_cordic_start	<= 1'b1;
              cmd_seq_state		<= STATE_CRC_CHECK;
            end
          end
        end
        
        STATE_BURST_TRANS: begin
          if (i_rx_byte_valid) begin
            count2burst		<= i_rx_byte;
            o_burst_cnt		<= i_rx_byte;
            cmd_seq_state	<= STATE_BURST_TRANS_II;
          end
        end
        
        STATE_BURST_TRANS_II: begin
          if (i_rx_byte_valid) begin
            o_cordic_theta	<= {i_rx_byte, o_cordic_theta[47:8]};
            count2six		<= count2six + 1;
            if (count2six == 5) begin
              count2six			<= '0;
              o_cordic_start	<= 1'b1;
              count2burst		<= count2burst - 1;
              if (count2burst == 1) begin
                cmd_seq_state		<= STATE_CRC_CHECK;
              end
            end
          end
        end
        
        STATE_DISABLE: begin
          o_cordic_pipeline_en	<= 1'b0;
          o_cordic_rst_n		<= 1'b0;
          cmd_seq_state			<= STATE_CRC_CHECK;
        end
        
        STATE_ENABLE: begin
          o_cordic_pipeline_en	<= 1'b1;
          cmd_seq_state			<= STATE_CRC_CHECK;
        end
        
        STATE_CRC_CHECK: begin
          if (crc_byte_done) begin
            cmd_seq_state	<= STATE_HEADER;
            o_rx_msg_err	<= !lfsr_reg;
          end
        end
        
        default: begin
          cmd_seq_state		<= STATE_HEADER;
          count2six			<= '0;
          count2burst			<= '0;
          o_burst_cnt			<= '0;
          o_rx_msg_err			<= 1'b0;
          o_cordic_start		<= 1'b0;
          o_cordic_theta		<= '0;
          o_cordic_pipeline_en	<= 1'b1;
          o_cordic_rst_n		<= 1'b1;
        end
          
      endcase
      
      if (i_rx_err) begin
        cmd_seq_state	<= STATE_HEADER;
        o_cordic_rst_n	<= 1'b0;
      end
      
    end
  
endmodule