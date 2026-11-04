`timescale 1ns/1ps

module tb_traffic_light();
    // ---- Параметры быстрой симуляции ----
    localparam int DIV_LIMIT_1S = 20;   // 1 "секунда" = 20 тактов
    localparam int BLINK_DIV    = 5;    // 0.5 с период = 10 тактов
    localparam int CLK_PERIOD   = 10;   // 100 МГц
    localparam int SEC_NS       = DIV_LIMIT_1S * CLK_PERIOD; // 200 нс = 1 с

    logic        clk;
    logic        rst_n;
    logic        btn_ped;
    logic [2:0]  cars_lights;
    logic [1:0]  ped_lights;
    logic [3:0]  time_left;
    logic [1:0]  fsm_state;

    int errors = 0;

    // ---- DUT ----
    traffic_light_fsm #(
        .DIV_LIMIT_1S(DIV_LIMIT_1S),
        .BLINK_DIV(BLINK_DIV)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .btn_ped(btn_ped),
        .cars_lights(cars_lights),
        .ped_lights(ped_lights),
        .time_left(time_left),
        .fsm_state(fsm_state)
    );

    // ---- Тактовый сигнал ----
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ---- Автоматическое протоколирование ----
    initial begin
        $monitor("t=%0t | state=%0d cars=%b ped=%b time=%0d",
                 $time, fsm_state, cars_lights, ped_lights, time_left);
    end

    // ---- Нажатие кнопки пешехода (активный высокий) ----
    task press_ped();
        begin
            btn_ped = 1'b1;
            #(CLK_PERIOD * 8);     // удержание > 3 циклов (sync + edge)
            btn_ped = 1'b0;
            #(CLK_PERIOD * 4);
        end
    endtask

    // ---- Проверка ----
    task check(string label,
               logic [2:0] exp_cars,
               logic [1:0] exp_ped,
               logic [3:0] exp_time);
        if (cars_lights !== exp_cars || ped_lights !== exp_ped || time_left !== exp_time) begin
            $error("%s: got cars=%b ped=%b time=%0d, expected cars=%b ped=%b time=%0d",
                   label, cars_lights, ped_lights, time_left,
                   exp_cars, exp_ped, exp_time);
            errors++;
        end else begin
            $display("%s: OK", label);
        end
    endtask

    // ---- Безопасность: никогда не должно быть зелёного для авто И пешеходов ----
    always @(posedge clk) begin
        if (rst_n && cars_lights[0] && ped_lights[0]) begin
            $error("SAFETY: green for cars AND pedestrians simultaneously!");
            errors++;
        end
    end

    // ---- Основной сценарий ----
    initial begin
        // Сброс
        rst_n   = 0;
        btn_ped = 0;
        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 3);

        // ============================================================
        // Тест 1: базовый режим — старт в S_GREEN
        // ============================================================
        $display("\n--- Test 1: Base mode, initial state ---");
        check("t=0: S_GREEN start", 3'b001, 2'b10, 4'd15);

        // Ждём ~6 секунд зелёного (green_left = 12-6 = 6, display = 9)
        #(SEC_NS * 6);
        check("t=6s: S_GREEN mid", 3'b001, 2'b10, 4'd9);

        // Ждём до конца зелёного (12s) + 2s жёлтого
        #(SEC_NS * 8);   // всего 14s
        $display("  state=%0d (S_YELLOW expected)", fsm_state);
        if (fsm_state !== 2'd1) begin
            $error("Expected S_YELLOW at t=14s, got %0d", fsm_state);
            errors++;
        end

        // Проверка мигания: yellow должен мигать в течение 0.5s (10 тактов)
        $display("\n--- Test 2: Blink modulation during yellow ---");
        begin
            logic prev_blink;
            int toggles = 0;
            prev_blink = cars_lights[1];
            repeat (SEC_NS / CLK_PERIOD) begin  // 1 "секунда" = 20 тактов
                @(posedge clk);
                if (cars_lights[1] !== prev_blink) toggles++;
                prev_blink = cars_lights[1];
            end
            if (toggles < 2) begin
                $error("Yellow LED did not toggle enough (toggles=%0d)", toggles);
                errors++;
            end else begin
                $display("  Yellow toggles = %0d: OK", toggles);
            end
        end

        // Ждём перехода в S_PED (15s от старта)
        #(SEC_NS * 2);   // t = 16s
        $display("\n--- Test 3: S_PED phase ---");
        if (fsm_state !== 2'd2) begin
            $error("Expected S_PED at t=16s, got %0d", fsm_state);
            errors++;
        end
        // Проверка: авто красный, пешеходам зелёный, отсчёт ~10..09
        if (cars_lights !== 3'b100) begin
            $error("S_PED: cars_lights should be 100, got %b", cars_lights);
            errors++;
        end
        if (ped_lights !== 2'b01) begin
            $error("S_PED: ped_lights should be 01, got %b", ped_lights);
            errors++;
        end

        // Ждём возврата в S_GREEN (25s от старта)
        #(SEC_NS * 10);
        $display("\n--- Test 4: Return to S_GREEN ---");
        if (fsm_state !== 2'd0) begin
            $error("Expected S_GREEN at t=26s, got %0d", fsm_state);
            errors++;
        end
        check("Return to S_GREEN", 3'b001, 2'b10, 4'd14);

        // ============================================================
        // Тест 5: нажатие кнопки на 2-й секунде (зелёный сокращается до 3 с)
        // ============================================================
        $display("\n--- Test 5: Button at ~1s (green_left=11) ---");
        // Ждём 1s (зелёный = 11)
        #(SEC_NS * 1);
        check("Before button", 3'b001, 2'b10, 4'd14);
        press_ped();
        // Проверяем: display должно стать 3 (short_left=3)
        #(CLK_PERIOD * 4);
        if (time_left > 4'd3) begin
            $error("After shorten, time_left should be <= 3, got %0d", time_left);
            errors++;
        end else begin
            $display("  Shortened to %0d: OK", time_left);
        end
        // Ждём завершения короткой фазы + жёлтого (3+3=6s)
        #(SEC_NS * 7);
        $display("  state after short+yellow = %0d", fsm_state);
        if (fsm_state !== 2'd2) begin
            $error("Expected S_PED after shortened yellow, got %0d", fsm_state);
            errors++;
        end
        // Возврат в зелёный
        #(SEC_NS * 10);

        // ============================================================
        // Тест 6: нажатие кнопки на 11-й секунде (2 с осталось — игнорируется)
        // ============================================================
        $display("\n--- Test 6: Button at ~10s (green_left=2) ---");
        // Ждём 10s (зелёный = 2)
        #(SEC_NS * 10);
        check("Before late button", 3'b001, 2'b10, 4'd5);
        press_ped();
        #(CLK_PERIOD * 4);
        // display не должен измениться на 3 — должно остаться 5
        if (time_left < 4'd4) begin
            $error("Late button should be ignored, but time_left = %0d", time_left);
            errors++;
        end else begin
            $display("  Late button ignored (time_left=%0d): OK", time_left);
        end
        // Ждём окончания нормального зелёного + жёлтый
        #(SEC_NS * 5);
        if (fsm_state !== 2'd2) begin
            $error("Expected S_PED, got %0d", fsm_state);
            errors++;
        end
        #(SEC_NS * 10);

        // ============================================================
        // Тест 7: кнопка во время жёлтого и пешеходного — игнорируется
        // ============================================================
        $display("\n--- Test 7: Button during yellow/ped phases ---");
        // Ждём перехода в жёлтый
        #(SEC_NS * 12);   // конец зелёного
        #(SEC_NS * 1);    // первый тик жёлтого
        press_ped();      // должно игнорироваться
        #(SEC_NS * 4);
        if (fsm_state !== 2'd2) begin
            $error("Button during yellow should be ignored, state=%0d", fsm_state);
            errors++;
        end else $display("  Button during yellow: ignored OK");

        press_ped();      // во время пешеходного
        #(SEC_NS * 4);
        if (fsm_state !== 2'd2) begin
            $error("Button during ped should be ignored, state=%0d", fsm_state);
            errors++;
        end else $display("  Button during ped: ignored OK");

        // ============================================================
        // Итог
        // ============================================================
        $display("\n========== ИТОГ ==========");
        if (errors == 0)
            $display("ВСЕ ТЕСТЫ ПРОЙДЕНЫ");
        else
            $display("ОШИБОК: %0d", errors);

        $stop;
    end
endmodule