# ChaCha20 Verilog Implementation

A hardware implementation of the ChaCha20 stream cipher in Verilog, based on [RFC 8439](https://tools.ietf.org/html/rfc8439). This implementation is tested and simulated using Verilator.

## Requirements

- Verilator
- C++ compiler
- Make

## Usage

```bash
# build the testbench and run the simulation
make

# Build the testbench
make build_tb

# Run the simulation
make run

# Clean build artifacts
make clean

# Lint Verilog code
make lint

# View waveform (requires gtkwave)
make wave
```
