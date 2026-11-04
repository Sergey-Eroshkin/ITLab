module phase_timer #(
	parameter SECONDS 		= 10,
	parameter DIV_LIMIT_1S  = 50_000_000
) (
	input  logic 		 clk,
	input  logic 		 rst_n,
	output logic 		 timer_done,
	output logic [3:0] time_left
);
	logic tick;
	clk_divider #( .DIV_LIMIT(DIV_LIMIT_1S) ) d1(
		.clk(clk),
		.rst_n(rst_n),
		.tick(tick));
	always_ff @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			time_left <= 4'(SECONDS);
			timer_done <= 1'b0;
		end else begin
			if(tick) begin
				if(time_left > 0) begin
					time_left <= time_left - 4'b0001;
					if(time_left == 4'b0001) timer_done <= 1'b1;
				end
			end
		end
	end
endmodule
