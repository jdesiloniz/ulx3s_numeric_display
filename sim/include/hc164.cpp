#include <stdio.h>
#include "hc164.h"

Hc164::Hc164()
{
    init_hc164();
}

void Hc164::init_hc164() {
    output_signals = 0;
    previous_cp = 0;
}

void Hc164::update(unsigned cp, unsigned dsa, unsigned dsb, unsigned mr) {
    if (mr == 0) {
        init_hc164();
    } else if (previous_cp == 0 && cp == 1) {
        unsigned ds = ((dsa & 1) & (dsb & 1)) << 7;
        output_signals = ds + (output_signals >> 1);
    }

    previous_cp = cp;
}
