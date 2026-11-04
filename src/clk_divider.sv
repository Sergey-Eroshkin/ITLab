module clk_divider #(parameter DIV_LIMIT = 50_000_000) (
	input  logic clk,
	input  logic rst_n,
	output logic tick
);
	int counter;
	
	always_ff @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			counter <= 0;
			tick <= 1'b0;
		end else begin
			if(counter == DIV_LIMIT - 1) begin
				counter <= 0;
				tick <= 1'b1;		
			end else begin
				counter <= counter + 1;
				tick <= 1'b0;
			end
		end
	end
endmodule
