# Compiler settings
ASM = nasm

# Directory settings
SRC_DIR = src
BUILD_DIR = build
INSTALL_DIR = .install

# Disk settings
SECTOR_SIZE := 512
DISK_SECTORS := 2880

# Space computation
KERNEL_SIZE := $(shell stat -c%s $(BUILD_DIR)/kernel.bin)
KERNEL_SECTORS := $$(( ($(KERNEL_SIZE) + 511) / 512 ))
MODEL_SECTOR := $$(( 2 + $(KERNEL_SECTORS) ))

.PHONY: all disk_image kernel bootloader clean always install-deps

# ----------- Disk Image -----------
disk_image: $(BUILD_DIR)/main_disk.img

# Create main disk image (1.44 MB) containing the bootloader
# This simulates a physical main disk for emulation
$(BUILD_DIR)/main_disk.img: bootloader kernel model image_header
	dd if=/dev/zero of=$@ bs=$(SECTOR_SIZE) count=$(DISK_SECTORS)
	dd if=$(BUILD_DIR)/bootloader.bin of=$@ bs=$(SECTOR_SIZE) seek=0 conv=notrunc
	dd if=$(BUILD_DIR)/image_header.bin of=$@ bs=$(SECTOR_SIZE) seek=1 conv=notrunc
	dd if=$(BUILD_DIR)/kernel.bin of=$@ bs=$(SECTOR_SIZE) seek=2 conv=notrunc
	dd if=$(BUILD_DIR)/model.bin of=$@ bs=$(SECTOR_SIZE) seek=$(MODEL_SECTOR) conv=notrunc
	
# ----------- Image Header -----------
image_header: $(BUILD_DIR)/image_header.bin

$(BUILD_DIR)/image_header.bin: kernel
	@$(ASM) $(SRC_DIR)/image_header/image_header.asm -f bin -o $(BUILD_DIR)/image_header.bin \
	-d KERNEL_SIZE=$(KERNEL_SIZE) -d MODEL_SECTOR=$(MODEL_SECTOR)

# ----------- Bootloader -----------
bootloader: $(BUILD_DIR)/bootloader.bin

# Compile bootloader assembly to raw binary (no ELF header)
# -f bin means raw binary format (not object file)
$(BUILD_DIR)/bootloader.bin: always
	@$(ASM) $(SRC_DIR)/bootloader/boot.asm -f bin -o $(BUILD_DIR)/bootloader.bin

# ----------- Kernel -----------
kernel: $(BUILD_DIR)/kernel.bin

$(BUILD_DIR)/kernel.bin: always
	@$(ASM) $(SRC_DIR)/kernel/main.asm -f bin -o $(BUILD_DIR)/kernel.bin

# ----------- Model -----------
model: $(BUILD_DIR)/model.bin

$(BUILD_DIR)/model.bin: always
	@$(ASM) $(SRC_DIR)/model/model.asm -f bin -o $(BUILD_DIR)/model.bin

# ----------- Always -----------
always:
	mkdir -p $(BUILD_DIR)

# ----------- Clean -----------
clean:
	rm -rf $(BUILD_DIR)/*

# Install dependencies
install-deps:
	@chmod +x $(INSTALL_DIR)/install-deps.sh
	@./$(INSTALL_DIR)/install-deps.sh