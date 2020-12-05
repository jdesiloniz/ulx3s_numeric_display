#include <verilatedos.h>
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <time.h>
#include <sys/types.h>
#include <signal.h>
#include <iostream>
#include <fstream>
#include <time.h>
#include "verilated.h"
#include "Vled_display_controller.h"
#include "testb.h"
#include "hc164.h"

#define COMMON_ANODE true

using namespace std;

bool extract_bit(unsigned source, unsigned bit_number) {
	return (bool)((source >> bit_number) & 1);
}

char segment_name(unsigned bit) {
	switch (bit) {
		case 0: return 'p'; break;
		case 1: return 'g'; break;
		case 2: return 'f'; break;
		case 3: return 'e'; break;
		case 4: return 'd'; break;
		case 5: return 'c'; break;
		case 6: return 'b'; break;
		case 7: return 'a'; break;
		default: return 'a'; break;
	}
}

void print_led_display(Hc164 *shifter_a, Hc164 *shifter_b) {
	unsigned shifter_a_output = COMMON_ANODE ? ~(shifter_a->output_signals) & 0xFF : shifter_a->output_signals;
	unsigned shifter_b_output = COMMON_ANODE ? ~(shifter_b->output_signals) & 0xFF : shifter_b->output_signals;

	unsigned segment_digit;

	switch (shifter_a_output) {
		case 0x80: segment_digit = 3; break;
		case 0x40: segment_digit = 2; break;
		case 0x20: segment_digit = 1; break;
		case 0x10: segment_digit = 0; break;
	}

	printf("[LED_DISPLAY] Active digit [%d], ", segment_digit);

	for (int i = 7; i >= 0; i --) {
		bool segment = extract_bit(shifter_b_output, i);
		char name = segment_name(i);

		printf("%c:[%d]", name, (unsigned)segment);
	}

	printf("\n");
}

void update_simulation(TESTB<Vled_display_controller> *tb, Hc164 *shifter_a, Hc164 *shifter_b, unsigned digit0, unsigned digit1, unsigned digit2, unsigned digit3, bool print_leds) {
	tb->m_core->i_display_D0 = digit0;
	tb->m_core->i_display_D1 = digit1;
	tb->m_core->i_display_D2 = digit2;
	tb->m_core->i_display_D3 = digit3;
	tb->tick();
	shifter_a->update(tb->m_core->o_shifter_a_cp, tb->m_core->o_shifter_a_ds, tb->m_core->o_shifter_a_ds, tb->m_core->o_shifter_a_mr_n);
	shifter_b->update(tb->m_core->o_shifter_b_cp, tb->m_core->o_shifter_b_ds, tb->m_core->o_shifter_b_ds, tb->m_core->o_shifter_b_mr_n);

	if (tb->m_core->debug_update_leds == 1 && print_leds) {
		print_led_display(shifter_a, shifter_b);
	}
}

void wait_clocks(TESTB<Vled_display_controller> *tb, Hc164 *shifter_a, Hc164 *shifter_b, unsigned digit0, unsigned digit1, unsigned digit2, unsigned digit3, unsigned clocks) {
	for (unsigned i = 0; i < clocks; i++) {
		update_simulation(tb, shifter_a, shifter_b, digit0, digit1, digit2, digit3, true);
	}
}

void wait_hc164_reset(TESTB<Vled_display_controller> *tb, Hc164 *shifter_a, Hc164 *shifter_b, unsigned digit0, unsigned digit1, unsigned digit2, unsigned digit3) {
	// HC164 IC needs at least 25ns to reset itself at booting up, to be safe in our design we wait a whole "digit cycle",
	// so the first notification of leds being updated would give us "garbage" data. To avoid that, we ignore that first "dummy cycle":
	while (tb->m_core->debug_update_leds != 1) {
		update_simulation(tb, shifter_a, shifter_b, digit0, digit1, digit2, digit3, false);
	}
}

int	main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);

	unsigned digit0 = 0xFC; 	// 0
	unsigned digit1 = 0xB6;		// 5
	unsigned digit2 = 0xE0;		// 7
	unsigned digit3 = 0xFF;		// B

	TESTB<Vled_display_controller> *tb = new TESTB<Vled_display_controller>;
	Hc164 *shifter_a = new Hc164();
	Hc164 *shifter_b = new Hc164();

	tb->opentrace("led_display_controller_tb.vcd");

	// Initial reset 
	tb->m_core->i_reset_n = 0;

	// Wait until starting
	wait_clocks(tb, shifter_a, shifter_b, digit0, digit1, digit2, digit3, 10);
	tb->m_core->i_reset_n = 1;

	// Wait during the delay for HC164 reset cycle
	wait_hc164_reset(tb, shifter_a, shifter_b, digit0, digit1, digit2, digit3);

	// Wait a bit after reset
	printf("[TEST] Starting sim after reset...\n");
	wait_clocks(tb, shifter_a, shifter_b, digit0, digit1, digit2, digit3, 5000);

    printf("\n\nSimulation complete\n");
}
