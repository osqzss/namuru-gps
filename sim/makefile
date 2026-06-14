CC      := gcc
CFLAGS  := -O2 -Wall -Wextra -std=c11
LDFLAGS := -lm

all: gps_if_sim

gps_if_sim: gps_if_sim.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f gps_if_sim *.o

.PHONY: all clean
