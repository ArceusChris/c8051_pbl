PROJECT := garbage_sorter
AS := sdas8051
LD := sdld
PACKIHX := packihx

.PHONY: all clean flash

all: $(PROJECT).hex

$(PROJECT).rel: $(PROJECT).asm
	$(AS) -los $(PROJECT).asm

$(PROJECT).ihx: $(PROJECT).rel
	$(LD) -i -m -u $(PROJECT) $(PROJECT).rel

$(PROJECT).hex: $(PROJECT).ihx
	$(PACKIHX) $(PROJECT).ihx > $(PROJECT).hex

flash: $(PROJECT).hex
	cd .. && SERIAL=$$SERIAL ./scripts/flash.sh exp/$(PROJECT).hex

clean:
	rm -f $(PROJECT).rel $(PROJECT).lst $(PROJECT).sym $(PROJECT).rst $(PROJECT).map $(PROJECT).mem $(PROJECT).ihx $(PROJECT).hex
