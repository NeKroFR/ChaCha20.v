VERILATOR = verilator
VERILATOR_FLAGS = --cc --assert --trace --top-module chacha20_top --Wno-fatal
VERILATOR_MAKE = make
CC = g++
CFLAGS = -std=c++11 -Wall -g

# Directories
VERILOG_SRC_DIR = src/verilog_sources
VERILOG_INC_DIR = src/verilog_headers
TESTS_DIR = src/tests
OBJ_DIR = obj_dir

# Source files
VERILOG_SRCS = $(wildcard $(VERILOG_SRC_DIR)/*.v)
VERILOG_INCS = $(wildcard $(VERILOG_INC_DIR)/*.vh)
TEST_SRCS = $(TESTS_DIR)/chacha20_top.v
CPP_DRIVER = $(TESTS_DIR)/chacha20_driver.cpp

# Output executable
OUTPUT_EXE = $(OBJ_DIR)/Vchacha20_top

# Default target (build and run)
default: build_tb run

# Build Verilog testbench
build_tb:
	$(VERILATOR) $(VERILATOR_FLAGS) \
		-I$(VERILOG_SRC_DIR) -I$(VERILOG_INC_DIR) \
		$(VERILOG_SRCS) $(TEST_SRCS) \
		--exe $(CPP_DRIVER)
	$(VERILATOR_MAKE) -C $(OBJ_DIR) -f Vchacha20_top.mk

# Run simulation
run: $(OUTPUT_EXE)
	if [ -f $(OUTPUT_EXE) ]; then \
		./$(OUTPUT_EXE); \
	else \
		echo "File not found. Please run 'make' to build the project."; \
	fi
# if statement does not work :(

# Clean build files
clean:
	rm -rf $(OBJ_DIR)
	rm -f src/*.vcd
	rm -f *.vcd

# Lint Verilog code
lint:
	$(VERILATOR) --lint-only \
		-I$(VERILOG_SRC_DIR) -I$(VERILOG_INC_DIR) \
		$(VERILOG_SRCS)

wave:
	gtkwave dump.vcd &

.PHONY: all default build_tb run clean lint wave
