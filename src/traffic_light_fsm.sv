module traffic_light_fsm(
	input  logic       clk,
	input  logic       rst_n,
	input  logic       btn_ped,
	output logic [2:0] cars_lights,
	output logic [1:0] ped_lights,
	output logic [3:0] time_left,
	output logic [1:0] fsm_state
);

	typedef enum logic [1:0] {
		GREEN,
		YELLOW,
		RED
	} state_t;

	state_t 		state, next_state;
	logic 		green_done,  yellow_done,  short_done,  ped_done;
	logic [3:0] green_left,  yellow_left,  short_left,  ped_left;
	logic 		green_rst_n, yellow_rst_n, short_rst_n, ped_rst_n;
	logic			short;
	

	phase_timer #( .SECONDS(12) ) tgreen (
		.clk(clk),
		.rst_n(green_rst_n),
		.timer_done(green_done),
		.time_left(green_left)
	);
	
	phase_timer #( .SECONDS(3) ) tyellow (
		.clk(clk),
		.rst_n(yellow_rst_n),
		.timer_done(yellow_done),
		.time_left(yellow_left)
	);
	
	phase_timer #( .SECONDS(3) ) tshort (
		.clk(clk),
		.rst_n(short_rst_n),
		.timer_done(short_done),
		.time_left(short_left)
	);
	
	phase_timer #( .SECONDS(10) ) tped (
		.clk(clk),
		.rst_n(ped_rst_n),
		.timer_done(ped_done),
		.time_left(ped_left)
	);
	
	logic blink;
	blink_gen b(
		.clk(clk),
		.rst_n(rst_n),
		.blink(blink)
	);
	
	// флаги перезагрузок
	assign green_rst_n = rst_n & (state == GREEN) & ~short;
	assign short_rst_n = rst_n & (state == GREEN) & short;
	assign yellow_rst_n = rst_n & (state == YELLOW);
	assign ped_rst_n = rst_n & (state == RED);
	
	always_ff @(posedge clk or negedge rst_n) begin  // поведение по тыку кнопки
		if(!rst_n) short <= 1'b0;
		else begin
			if(state != GREEN) short <= 1'b0;
			else begin
				if(green_left > 4'd3 && btn_ped && !short) short <= 1'b1;
			end
		end
	end
	
	always_ff @(posedge clk or negedge rst_n) begin // поведение при перезагрузке
		if(!rst_n) state <= GREEN;
		else state <= next_state;
	end
	
	always_comb begin  // сам автомат
		next_state = state;
		case(state)
			GREEN: begin
				if(short) next_state = YELLOW;
				else if(green_done) next_state = YELLOW;
			end
			
			YELLOW: begin
				if(yellow_done) next_state = RED;
			end
			
			RED: begin
				if(ped_done) next_state = GREEN;
			end
			
			default: next_state = GREEN;
		endcase
	end
	
	always_comb begin    // выход автомата (на индикаторы и лампочки)
		cars_lights = 3'b000;
		ped_lights = 2'b0;
		time_left = 4'd0;
		fsm_state = state;
		
		case(state)
			GREEN: begin
				cars_lights[0] = 1'b1;
				ped_lights[1] = 1'b1;
				if(short) time_left = short_left;
				else time_left = green_left + 4'd3;
			end
			
			YELLOW: begin
				cars_lights[1] = blink;
				ped_lights[1] = 1'b1;
				time_left = yellow_left;
			end
			
			RED: begin
				cars_lights[2] = 1'b1;
				ped_lights[0] = 1'b1;
				time_left = ped_left;
			end
			
			default: begin
				cars_lights = 3'b000;
				ped_lights = 2'b0;
				time_left = 4'd0;
			end
		endcase
	end
	
endmodule
