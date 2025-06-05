`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/03/23 08:03:15
// Design Name: 
// Module Name: i2c_slave
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module i2c_slave(
    input clk,
    input rst_n,
    input i2c_scl,
    inout i2c_sda,
    input [7:0] rd_data,
    output wr_en,
    output rd_en,
    output [7:0] wr_data,
    output [7:0] addr
    );
	
reg scl_s1, scl_s2;
reg sda_s1, sda_s2;
//reg i2c_scl, i2c_sda;

reg [3:0] cnt, cnt_next;

reg [3:0] write_cnt;


//fsm
reg [3:0] cstate, nstate;
reg [7:0] shift_reg;

//sram 128*8
reg [7:0] mem [255:0];
reg [7:0] rdata;


localparam IDLE 	    = 4'd0;
localparam ADDR	   	    = 4'd1;
localparam ADDR_ACK 	= 4'd2;
localparam RECEIVE      = 4'd3;
localparam SEND         = 4'd4;
localparam ACK          = 4'd5;
localparam WAIT_ACK     = 4'd6;
localparam STOP         = 4'd7;

parameter SLAVE_ADDR    = 7'b0101_000;




always@(posedge clk or negedge rst_n)
begin
	if(~rst_n)begin
		scl_s1 <= 1'd0;
		scl_s2 <= 1'd0;
		sda_s1 <= 1'd0;
		sda_s2 <= 1'd0;
	end else begin
		scl_s1 <= i2c_scl;
		sda_s1 <= i2c_sda;
		scl_s2 <= scl_s1;
		sda_s2 <= sda_s1;
	end

end

wire scl_posedge = scl_s1 & ~scl_s2;
wire sda_posedge = sda_s1 & ~sda_s2;

wire scl_negedge = ~scl_s1 & scl_s2;
wire sda_negedge = ~sda_s1 & sda_s2;

wire start_bit = sda_negedge & scl_s2;
wire stop_bit = sda_posedge & scl_s2;
reg start_bit_en;
reg stop_bit_en;
reg sda_o_tmp;
reg sda_o;
reg sda_oe;


//fsm

always@(posedge clk or negedge rst_n)
begin
	if(~rst_n)begin
		cstate <= IDLE;
	end else begin
		cstate <= nstate;
	end
end

//counter
always@(posedge clk or negedge rst_n)
begin
	if(~rst_n)begin
		cnt <= 4'd0;
	end else if(start_bit)begin
		cnt <= 4'd0;
	end else if(scl_negedge)begin
		cnt <= cnt_next;
	end
end
//shift reg
always@(posedge clk or negedge rst_n)
begin
	if(~rst_n)begin
		shift_reg <= 8'd0;
	end else if(scl_negedge)begin
		shift_reg <= {shift_reg[6:0],sda_s2};
	end 
end
reg write_en;
reg read_en;
reg addr_chk_en;
always@(posedge clk or negedge rst_n)
begin
	if(~rst_n)begin
		write_en <= 1'd0;
		read_en <= 1'd0;
	end else if(stop_bit)begin
		write_en <= 1'd0;
		read_en <= 1'd0;
	end else if(addr_chk_en && cstate == ADDR_ACK && ~shift_reg[0])begin
		write_en <= 1'd1;
		read_en <= 1'd0;
	end else if(addr_chk_en && cstate == ADDR_ACK && shift_reg[0])begin
		write_en <= 1'd0;
		read_en <= 1'd1;
	end 
end
		
	 


//fsm
wire addr_chk = (shift_reg[7:1] == SLAVE_ADDR);

always@(posedge clk or negedge rst_n)
begin
	if(~rst_n)begin
		addr_chk_en <= 1'd0;
	end else if(stop_bit)begin
		addr_chk_en <= 1'd0;
	end else if(addr_chk)begin
		addr_chk_en <= 1'd1;
	end 
end

always@(*)
begin
	case(cstate)
	//0
	IDLE:
	begin
		sda_o_tmp = 1'd1;
		sda_oe = 1'd0;
		if(start_bit)begin
			nstate = ADDR;
		end else begin
			nstate = IDLE;
		end
	
	end
	//1
	ADDR:begin
		cnt_next = cnt + 4'd1;
		sda_o_tmp = 1'd0;
		sda_oe = 1'd0;
		if(cnt == 4'd8 && scl_negedge)begin
		//if(addr_chk_en && scl_negedge)begin
			nstate = ADDR_ACK;
			cnt_next = 4'd0;
		end else begin
			nstate = ADDR;
		end

	end
	//2
	ADDR_ACK:begin
		sda_o_tmp = 1'd1;
		sda_oe = 1'd1;
		if(shift_reg[0] == 1'd1 && scl_negedge && addr_chk_en)begin
			nstate = RECEIVE;
		end else if(shift_reg[0] == 1'd0 && scl_negedge && addr_chk_en)begin
			nstate = SEND;
		end else begin
			nstate = ADDR_ACK;
		end
	
	end
	//3
	RECEIVE:begin
		cnt_next = cnt + 4'd1;
		sda_oe = 1'd1;
		//rdata = 8'haa;
		case(cnt)
			0:begin sda_o_tmp = rdata[7];end
			1:begin sda_o_tmp = rdata[6];end
			2:begin sda_o_tmp = rdata[5];end
			3:begin sda_o_tmp = rdata[4];end
			4:begin sda_o_tmp = rdata[3];end
			5:begin sda_o_tmp = rdata[2];end
			6:begin sda_o_tmp = rdata[1];end
			7:begin sda_o_tmp = rdata[0];end
			default: begin sda_o_tmp = 1'd0;end
		endcase
		if(cnt == 4'd7 && scl_negedge)begin
			nstate = WAIT_ACK;
		end else begin
			nstate = RECEIVE;
		end
			
	end
	//4
	SEND:begin
		sda_o_tmp = 1'd0;
		cnt_next = cnt + 4'd1;
		sda_oe = 1'd0;
		if(stop_bit)begin
			nstate = IDLE;
		end else if(start_bit)begin
			nstate = ADDR;
		end else if(cnt == 4'd7 && scl_negedge)begin
			nstate = ACK;
		end else begin
			nstate = SEND;
		end 
		
	
	end
	//5
	ACK:begin
	sda_o_tmp = 1'd1;
	sda_oe = 1'd1;
		if(stop_bit)begin
			nstate = IDLE;
			cnt_next = 4'd0;
		end if(scl_negedge && write_en)begin
			nstate = SEND;
			cnt_next = 4'd0;
		end else if(scl_negedge && read_en)begin
			nstate = RECEIVE;
			cnt_next = 4'd0;
		end else begin
			nstate = ACK;
		end
		
	end
	//6
	WAIT_ACK:begin
		sda_o_tmp = 1'd0;
		sda_oe = 1'd0;
	//if NACK detect nstate = STOP
		if(sda_s2 == 1'd0 && scl_posedge)begin
			nstate = RECEIVE;
		end else if(sda_s2 == 1'd1 && scl_posedge)begin
			nstate = STOP;
		end else begin
			nstate = WAIT_ACK;
		end 
	
	end
	//7
	STOP:begin
		nstate = IDLE;
		sda_oe = 1'd0;
	
	
	end
	
	default:begin
		nstate = IDLE;
		sda_oe = 1'd0;
	
	end
		
	endcase


end


	// data and address
wire data_en = (write_en && cstate == 4'd5 && scl_negedge);
reg [7:0] data_cnt;
reg [7:0] data;
always@(posedge clk or negedge rst_n)
begin
	if(~rst_n)begin
		data_cnt <= 8'd0;
	end else if(stop_bit)begin
		data_cnt <= 8'd0;
	end else if(data_en)begin
		data_cnt <= data_cnt + 8'd1;
	end
end
always@(posedge clk or negedge rst_n)
begin
	if(~rst_n)begin
		data <= 8'd0;
	end else if(stop_bit)begin
		data <= 8'd0;
	end else if(scl_posedge && cstate == ACK)begin
		data <= shift_reg;
	end
end

reg [7:0] wdata;
always@(posedge clk or negedge rst_n)
begin
	if(~rst_n)begin
		wdata <= 8'd0;
	end else if(stop_bit)begin
		wdata <= 8'd0;
	end else if(cstate == 4'd5 && scl_posedge && data_cnt > 8'd0)begin
		wdata <= data;
	end
end
reg [7:0] waddr;
always@(posedge clk or negedge rst_n)
begin
	if(~rst_n)begin
		waddr <= 8'd0;
	end else if(stop_bit)begin
		waddr <= 8'd0;
	end else if(cstate == 4'd5 && scl_negedge && data_cnt == 8'd0)begin
		waddr <= data;
	end
end
//for read sram
reg read_en_s1;
wire rd_stp;
always@(posedge clk or negedge rst_n)
begin
	if(~rst_n)begin
		read_en_s1 <= 1'd0;
	end else begin
		read_en_s1 <= read_en;
	end 
end 
assign rd_stp = read_en && ~read_en_s1;


//for sram
integer i;
always@(posedge clk)
begin
	if(~rst_n)begin
		for (i=0; i<256; i=i+1)begin
			mem[i] <= 8'd0;
		end 
	end else if(data_en)begin
		mem[waddr] <= wdata;
	end else if(rd_stp)begin
		rdata <= mem[waddr];
	end 
end 

//for sda 

assign i2c_sda = (sda_oe)? ~sda_o_tmp : 1'bz;



endmodule