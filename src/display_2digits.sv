module display_2digits (
	input  logic [15:0] number,
	output logic [6:0]  seg0,
	output logic [6:0]  seg1
);
	always_comb begin
		digits_a = number % 10;           
		digits_b = (number / 10) % 10;
	end
	hex7seg_decoder d1 (.dec(digits_a), .seg(seg0));
	hex7seg_decoder d2 (.dec(digits_b), .seg(seg1));
endmodule
