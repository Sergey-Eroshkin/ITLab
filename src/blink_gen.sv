module blink_gen(
	input  logic clk,
	input  logic rst_n,
	output logic blink
);
	logic tick;
	clk_divider #(.DIV_LIMIT(12_500_000)) d1 (.clk(clk), .rst_n(rst_n), .tick(tick));
	always_ff @(posedge clk or negedge rst_n) begin
		if(!rst_n) blink <= 1'b0;
		else if(tick) blink <= ~blink;
	end
endmodule
