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
#include "Vwb_hc164.h"
#include "testb.h"
#include "hc164.h"

using namespace std;

void update_simulation(TESTB<Vwb_hc164> *tb, Hc164 *device_sim) {
	device_sim->update(tb->m_core->o_shifter_cp, tb->m_core->o_shifter_ds, tb->m_core->o_shifter_ds, tb->m_core->o_shifter_mr_n);

	tb->tick();
}

void wait_clocks(TESTB<Vwb_hc164> *tb, Hc164 *device_sim, unsigned clocks) {
	for (unsigned i = 0; i < clocks; i++) {
		update_simulation(tb, device_sim);
	}
}

unsigned send_byte(TESTB<Vwb_hc164> *tb, Hc164 *device_sim) {
	unsigned data = (rand() % 0xFF) + 1;

	printf("[TEST] Sending byte [%02X] to HC164...\n", data);

	tb->m_core->i_wb_cyc = 1;
	tb->m_core->i_wb_stb = 1;
	tb->m_core->i_wb_data = data;
	update_simulation(tb, device_sim);
	tb->m_core->i_wb_cyc = 0;
	tb->m_core->i_wb_stb = 0;
	update_simulation(tb, device_sim);

	return data;
}

void send_data(TESTB<Vwb_hc164> *tb, Hc164 *device_sim, unsigned times) {
	for (int i = 0; i < times; i ++) {
		unsigned sent_data = send_byte(tb, device_sim);
		wait_clocks(tb, device_sim, 100);
		
		unsigned output = device_sim->output_signals; 
		if (sent_data != device_sim->output_signals) {
			printf("[TEST] Received invalid byte [%02X] from HC164, expected [%02X].\n", sent_data, output);
			exit(-1);
		} else {
        	printf("[HC164] Parallel port set to: %02X\n", output);
		}
	}
}

int	main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);

	TESTB<Vwb_hc164> *tb = new TESTB<Vwb_hc164>;
	Hc164 *device_sim = new Hc164();
	tb->opentrace("wb_hc164_tb.vcd");

	// Initial reset 
	tb->m_core->i_reset_n = 0;

	// Wait until starting
	wait_clocks(tb, device_sim, 10);

	tb->m_core->i_reset_n = 1;

	// Wait a bit after reset
	printf("[TEST] Starting sim after reset...\n");
	wait_clocks(tb, device_sim, 10);

	// Submit some data:
	send_data(tb, device_sim, 15);

	// Reset and do it again:
	tb->m_core->i_reset_n = 0;
	update_simulation(tb, device_sim);
	tb->m_core->i_reset_n = 1;
	update_simulation(tb, device_sim);
	send_data(tb, device_sim, 15);

	wait_clocks(tb, device_sim, 200);

    printf("\n\nSimulation successful\n");
}
