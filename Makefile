PROJECT := market_pbl
BUILD_DIR := build
SRC := src/main.c
SDCC ?= sdcc
PACKIHX ?= packihx

CFLAGS := -mmcs51 --model-small --std-sdcc99 --opt-code-size -Iinclude

.PHONY: all clean flash detect

all: $(BUILD_DIR)/$(PROJECT).hex

$(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/$(PROJECT).ihx: $(SRC) include/board.h include/c8051f310.h | $(BUILD_DIR)
	$(SDCC) $(CFLAGS) -o $@ $(SRC)

$(BUILD_DIR)/$(PROJECT).hex: $(BUILD_DIR)/$(PROJECT).ihx
	$(PACKIHX) $< > $@

flash: $(BUILD_DIR)/$(PROJECT).hex
	./scripts/flash.sh $<

detect:
	LD_LIBRARY_PATH=./siliconlabs-c8051-efm8-utils/inspect_c8051 ./siliconlabs-c8051-efm8-utils/inspect_c8051/device8051 -slist

clean:
	rm -rf $(BUILD_DIR)
