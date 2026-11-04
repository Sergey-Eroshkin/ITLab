#include <verilated.h>
#include "Vtraffic_light_fsm.h"
#include <cstdio>
#include <cstdint>

// Параметры быстрой симуляции
static constexpr int DIV_LIMIT_1S = 20;
static constexpr int CLK_PERIOD   = 10;   // нс
static constexpr int SEC_CYCLES   = DIV_LIMIT_1S;

int errors = 0;
int checks = 0;

void tick(Vtraffic_light_fsm* dut) {
    dut->clk = 0; dut->eval();
    dut->clk = 1; dut->eval();
    dut->clk = 0; dut->eval();
}

void wait_seconds(Vtraffic_light_fsm* dut, int n) {
    for (int i = 0; i < n * SEC_CYCLES; ++i) tick(dut);
}

void press_ped(Vtraffic_light_fsm* dut) {
    dut->btn_ped = 1;
    for (int i = 0; i < 8; ++i) tick(dut);
    dut->btn_ped = 0;
    for (int i = 0; i < 4; ++i) tick(dut);
}

void check(const char* label, uint8_t got, uint8_t exp) {
    checks++;
    if (got != exp) {
        printf("[FAIL] %s: got %u, expected %u\n", label, got, exp);
        errors++;
    }
}

void check_state(Vtraffic_light_fsm* dut, uint8_t exp, const char* label) {
    checks++;
    if (dut->fsm_state != exp) {
        printf("[FAIL] %s: state=%u, expected %u\n", label, dut->fsm_state, exp);
        errors++;
    }
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vtraffic_light_fsm* dut = new Vtraffic_light_fsm;

    // Сброс
    dut->clk = 0;
    dut->rst_n = 0;
    dut->btn_ped = 0;
    for (int i = 0; i < 10; ++i) tick(dut);
    dut->rst_n = 1;
    for (int i = 0; i < 3; ++i) tick(dut);

    // ============================================================
    // Тест 1: базовый режим
    // ============================================================
    printf("\n=== Test 1: Base mode ===\n");
    check_state(dut, 0, "start state=S_GREEN");
    check("start cars_lights", dut->cars_lights, 0b001);
    check("start ped_lights",  dut->ped_lights,  0b10);
    check("start time_left",  dut->time_left,    15);

    // Ждём 6s (green_left=6, display=9)
    wait_seconds(dut, 6);
    check("t=6s time_left", dut->time_left, 9);

    // Ждём до конца зелёного + 1s жёлтого (7s)
    wait_seconds(dut, 7);
    check_state(dut, 1, "state=S_YELLOW at t=13s");
    check("yellow cars_lights[2]=0", (dut->cars_lights >> 2) & 1, 0);
    check("yellow ped_lights",        dut->ped_lights, 0b10);

    // ============================================================
    // Тест 2: мигание жёлтого
    // ============================================================
    printf("\n=== Test 2: Blink modulation ===\n");
    {
        int toggles = 0;
        uint8_t prev = dut->cars_lights & 0b010;
        for (int i = 0; i < 20; ++i) {
            tick(dut);
            uint8_t cur = dut->cars_lights & 0b010;
            if (cur != prev) toggles++;
            prev = cur;
        }
        if (toggles < 1) {
            printf("[FAIL] yellow did not toggle (toggles=0)\n");
            errors++;
        } else {
            printf("[OK] yellow toggles = %d\n", toggles);
        }
        checks++;
    }

    // Ждём S_PED (всего 15s от старта зелёного, 1s уже прошёл жёлтого)
    wait_seconds(dut, 3);
    check_state(dut, 2, "state=S_PED at t=16s");
    check("S_PED cars", dut->cars_lights, 0b100);
    check("S_PED ped",  dut->ped_lights,  0b01);

    // ============================================================
    // Тест 3: возврат в S_GREEN
    // ============================================================
    printf("\n=== Test 3: Return to S_GREEN ===\n");
    wait_seconds(dut, 10);
    check_state(dut, 0, "state=S_GREEN at t=26s");

    // ============================================================
    // Тест 4: кнопка на ~1s — сокращение до 3
    // ============================================================
    printf("\n=== Test 4: Button at ~1s (green_left=11) ===\n");
    wait_seconds(dut, 1);
    check("before button time_left", dut->time_left, 14);  // green_left=11+3
    press_ped(dut);
    for (int i = 0; i < 4; ++i) tick(dut);
    if (dut->time_left > 3) {
        printf("[FAIL] after shorten time_left=%u (expected <=3)\n", dut->time_left);
        errors++;
    } else {
        printf("[OK] shortened to %u\n", dut->time_left);
    }
    checks++;

    // Ждём завершения короткой фазы + жёлтого (6s)
    wait_seconds(dut, 7);
    check_state(dut, 2, "state=S_PED after shortened+yellow");
    wait_seconds(dut, 10);   // конец пешеходного

    // ============================================================
    // Тест 5: кнопка на ~10s (green_left=2) — игнорируется
    // ============================================================
    printf("\n=== Test 5: Button at ~10s (green_left=2) ===\n");
    wait_seconds(dut, 10);
    check("before late button time_left", dut->time_left, 5);   // green_left=2+3
    press_ped(dut);
    for (int i = 0; i < 4; ++i) tick(dut);
    if (dut->time_left < 4) {
        printf("[FAIL] late button should be ignored, time_left=%u\n", dut->time_left);
        errors++;
    } else {
        printf("[OK] late button ignored (time_left=%u)\n", dut->time_left);
    }
    checks++;

    // Ждём конца зелёного + жёлтый
    wait_seconds(dut, 5);
    check_state(dut, 2, "state=S_PED after normal yellow");
    wait_seconds(dut, 10);

    // ============================================================
    // Тест 6: safety — одновременный зелёный для авто и пешеходов
    // ============================================================
    printf("\n=== Test 6: Safety check (no simultaneous green) ===\n");
    {
        int bad = 0;
        for (int cycle = 0; cycle < 1000; ++cycle) {
            tick(dut);
            uint8_t car_green = dut->cars_lights & 0x1;
            uint8_t ped_green = dut->ped_lights & 0x1;
            if (car_green && ped_green) bad++;
        }
        if (bad > 0) {
            printf("[FAIL] simultaneous green for %d cycles!\n", bad);
            errors++;
        } else {
            printf("[OK] no simultaneous green in 1000 cycles\n");
        }
        checks++;
    }

    // ============================================================
    // Итог
    // ============================================================
    printf("\n========== SUMMARY ==========\n");
    printf("Total checks: %d\n", checks);
    printf("Errors:       %d\n", errors);
    printf("Result:       %s\n", errors == 0 ? "PASSED" : "FAILED");

    delete dut;
    return errors ? 1 : 0;
}
