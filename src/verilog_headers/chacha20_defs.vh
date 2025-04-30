`ifndef CHACHA20_DEFS_VH
`define CHACHA20_DEFS_VH

//==============================================================================
// ChaCha20 Constants
//==============================================================================
`define CHACHA20_CONST_0 32'h61707865
`define CHACHA20_CONST_1 32'h3320646e
`define CHACHA20_CONST_2 32'h79622d32
`define CHACHA20_CONST_3 32'h6b206574

//==============================================================================
// Block Size Definitions
//==============================================================================
// ChaCha20 operates on 64-bytes blocks (512 bits, or 16 32-bits words)
`define CHACHA20_BLOCK_SIZE_BITS 512
`define CHACHA20_BLOCK_SIZE_BYTES 64
`define CHACHA20_BLOCK_SIZE_WORDS 16

//==============================================================================
// Word Size Definitions
//==============================================================================
// ChaCha20 uses 32-bitss words for all operations
`define CHACHA20_WORD_SIZE_BITS 32
`define CHACHA20_WORD_SIZE_BYTES 4

//==============================================================================
// Key Size Definitions
//==============================================================================
// ChaCha20 uses a 256-bits (32-bytes) key
`define CHACHA20_KEY_SIZE_BITS 256
`define CHACHA20_KEY_SIZE_BYTES 32
`define CHACHA20_KEY_SIZE_WORDS 8

//==============================================================================
// Nonce Size Definitions
//==============================================================================
// ChaCha20 uses a 96-bits (12-bytes) nonce (IV)
// THE NONCE SHOULD BE UNIQUE FOR EACH ENCRYPTION WITH THE SAME KEY
`define CHACHA20_NONCE_SIZE_BITS 96
`define CHACHA20_NONCE_SIZE_BYTES 12
`define CHACHA20_NONCE_SIZE_WORDS 3

//==============================================================================
// Counter Size Definitions
//==============================================================================
// ChaCha20 uses a 32-bits block counter
// This allows processing of up to 2^32 blocks (256 GB) with a single key-nonce pair
`define CHACHA20_COUNTER_SIZE_BITS 32
`define CHACHA20_COUNTER_SIZE_BYTES 4
`define CHACHA20_COUNTER_SIZE_WORDS 1

//==============================================================================
// Round Definitions
//==============================================================================
// ChaCha20 performs 20 rounds (10 double-rounds) of mixing operations
`define CHACHA20_ROUNDS 20
`define CHACHA20_DOUBLE_ROUNDS 10




//==============================================================================
// Implementation Configuration Options
//==============================================================================
// Resource optimization setting - controls hardware implementation strategy
// 0 = high performance (parallel operation - faster but uses more ressources)
//     This mode instantiates multiple quarter-round modules to process data in parallel
// 1 = resource optimized (sequential operation - smaller footprint but slower)
//     This mode reuses a single quarter-round module, requiring more cycles but less ressources
`define CHACHA20_RESOURCE_OPTIMIZE 0

// Parallel blocks - controls how many ChaCha20 blocks can be processed simultaneously
// Increasing this value improves throughput at the cost of hardware resources
// Valid values: 1, 2, or 4 blocks
`define CHACHA20_PARALLEL_BLOCKS 2

// Pipeline stages - controls the depth of pipelining in the quarter-round module
// 0 = No pipelining (pure combinational logic - lowest latency, potential timing issues)
// 1 = Single stage pipeline (balanced latency/throughput)
// 2 = Two-stage pipeline (highest throughput, best for high clock frequencies)
`define CHACHA20_PIPELINE_STAGES 2

// Endianness control
// 0 = little endian (RFC 8439 standard)
// 1 = big endian
`define CHACHA20_ENDIANNESS 0

`endif // CHACHA20_DEFS_VH
