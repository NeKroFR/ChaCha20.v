#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vchacha20_top.h"
#include <iostream>
#include <vector>
#include <random>
#include <iomanip>
#include <memory>
#include <string>
#include <cstring>

// Maximum simulation time
#define MAX_SIM_TIME 20000
const std::string TEST_MESSAGE = "Very very secret message";

// Bytes to word (little-endian)
uint32_t bytesToWord(const std::vector<uint8_t>& bytes, size_t offset) {
    if (offset + 3 >= bytes.size()) {
        uint32_t result = 0;
        for (size_t i = 0; i < 4 && offset + i < bytes.size(); i++) {
            result |= (static_cast<uint32_t>(bytes[offset + i]) << (8 * i));
        }
        return result;
    }
    
    return (static_cast<uint32_t>(bytes[offset]) |
            (static_cast<uint32_t>(bytes[offset + 1]) << 8) |
            (static_cast<uint32_t>(bytes[offset + 2]) << 16) |
            (static_cast<uint32_t>(bytes[offset + 3]) << 24));
}

// Word to bytes (little-endian)
void wordToBytes(uint32_t word, std::vector<uint8_t>& bytes) {
    bytes.push_back(word & 0xFF);
    bytes.push_back((word >> 8) & 0xFF);
    bytes.push_back((word >> 16) & 0xFF);
    bytes.push_back((word >> 24) & 0xFF);
}

int main(int argc, char** argv) {
    // Initialize Verilator
    Verilated::commandArgs(argc, argv);
    
    // Create VCD file for waveform dumping
    Verilated::traceEverOn(true);
    std::unique_ptr<VerilatedVcdC> tfp(new VerilatedVcdC);
    
    // Create an instance of the DUT
    std::unique_ptr<Vchacha20_top> dut(new Vchacha20_top);
    dut->trace(tfp.get(), 99);  // Trace 99 levels of hierarchy
    tfp->open("dump.vcd");
    
    // Initialize test vectors
    std::vector<uint8_t> plaintext_bytes;
    std::vector<uint32_t> plaintext_words;
    std::vector<uint32_t> ciphertext_words;
    std::vector<uint8_t> ciphertext_bytes;
    std::vector<uint32_t> decrypted_words;
    std::vector<uint8_t> decrypted_bytes;
     
    // String to bytes
    for (char c : TEST_MESSAGE) {
        plaintext_bytes.push_back(static_cast<uint8_t>(c));
    }
    
    // Bytes to 3words
    for (size_t i = 0; i < plaintext_bytes.size(); i += 4) {
        plaintext_words.push_back(bytesToWord(plaintext_bytes, i));
    }
    
    // Reset the DUT
    dut->rst_n = 0;
    dut->clk = 0;
    dut->data_valid = 0;
    dut->data_in = 0;
    
    // Run for a few cycles
    for (int i = 0; i < 10; i++) {
        dut->clk = !dut->clk;
        dut->eval();
        tfp->dump(i);
    }
    
    dut->rst_n = 1; // Release reset
    
    std::cout << "=== ChaCha20 Encryption Test ===" << std::endl;
    std::cout << "Plaintext: \"" << TEST_MESSAGE << "\"" << std::endl;
    std::cout << "Hex words: ";
    for (uint32_t word : plaintext_words) {
        std::cout << std::hex << std::setw(8) << std::setfill('0') << word << " ";
    }
    std::cout << std::dec << std::endl;
    
    unsigned long sim_time = 20;  // Start after reset cycles
    bool done = false;
    size_t word_index = 0;
    bool word_sent = false;
    bool was_busy = false;
    
    std::cout << "\n--- ENCRYPTION ---" << std::endl;
    
    // Encrypt words (one at a time)
    while (sim_time < MAX_SIM_TIME/2 && !done) {
        if (dut->clk) { // Process on positive clock edge
            // Check if the module is busy
            if (word_sent && dut->busy) {
                dut->data_valid = 0;
                word_sent = false;
            }
            // If the module is not busy and we haven't sent all words, send next word
            else if (!dut->busy && word_index < plaintext_words.size()) {
                dut->data_in = plaintext_words[word_index];
                dut->data_valid = 1;
                word_sent = true;
                
                std::cout << "Sending word " << word_index << " for encryption: 0x" 
                          << std::hex << std::setw(8) << std::setfill('0') 
                          << plaintext_words[word_index] << std::dec << std::endl;
                          
                word_index++;
            }
            
            // Capture output when the module transitions from busy to not busy
            if (was_busy && !dut->busy && ciphertext_words.size() < plaintext_words.size()) {
                ciphertext_words.push_back(dut->data_out);
                std::cout << "Received encrypted word: 0x" 
                          << std::hex << std::setw(8) << std::setfill('0') 
                          << dut->data_out << std::dec << std::endl;
            }
            was_busy = dut->busy;
            
            // Check if encryption is done
            if (word_index >= plaintext_words.size() && !dut->busy && 
                ciphertext_words.size() == plaintext_words.size()) {
                done = true;
            }
        }
        
        dut->clk = !dut->clk; // Toggle clock
        
        // Evaluate model and dump trace
        dut->eval();
        tfp->dump(sim_time);
        sim_time++;
    }
    
    // Convert ciphertext words back to bytes
    for (uint32_t word : ciphertext_words) {
        wordToBytes(word, ciphertext_bytes);
    }
    
    std::cout << "\n=== Encryption Results ===" << std::endl;
    std::cout << "Plaintext (" << plaintext_words.size() << " words, " 
              << plaintext_bytes.size() << " bytes): ";
    for (uint8_t byte : plaintext_bytes) {
        std::cout << std::hex << std::setw(2) << std::setfill('0') 
                  << static_cast<int>(byte) << " ";
    }
    std::cout << std::dec << std::endl;
    
    std::cout << "Ciphertext (" << ciphertext_words.size() << " words, " 
              << ciphertext_bytes.size() << " bytes): ";
    for (uint8_t byte : ciphertext_bytes) {
        std::cout << std::hex << std::setw(2) << std::setfill('0') 
                  << static_cast<int>(byte) << " ";
    }
    std::cout << std::dec << std::endl;
    
    if (ciphertext_words.size() != plaintext_words.size()) {
        std::cout << "ERROR: Ciphertext size doesn't match plaintext size!" << std::endl;
        return 1;
    }
        
    // Reset the DUT for decryption
    dut->rst_n = 0;
    for (int i = 0; i < 10; i++) {
        dut->clk = !dut->clk;
        dut->eval();
        tfp->dump(sim_time++);
    }
    dut->rst_n = 1;
    
    // Reset variables for decryption
    done = false;
    word_index = 0;
    word_sent = false;
    was_busy = false;
    
    std::cout << "\n--- DECRYPTION PHASE ---" << std::endl;
    
    // Decrypt words (one at a time)
    while (sim_time < MAX_SIM_TIME && !done) {
        if (dut->clk) { // Process on positive clock edge
            // Check if the module is busy
            if (word_sent && dut->busy) {
                dut->data_valid = 0;
                word_sent = false;
            }
            // If the module is not busy and we haven't sent all words, send the next word
            else if (!dut->busy && word_index < ciphertext_words.size()) {
                dut->data_in = ciphertext_words[word_index];
                dut->data_valid = 1;
                word_sent = true;
                
                std::cout << "Sending word " << word_index << " for decryption: 0x" 
                          << std::hex << std::setw(8) << std::setfill('0') 
                          << ciphertext_words[word_index] << std::dec << std::endl;
                          
                word_index++;
            }
            
            // Capture output when the module transitions from busy to not busy
            if (was_busy && !dut->busy && decrypted_words.size() < ciphertext_words.size()) {
                decrypted_words.push_back(dut->data_out);
                std::cout << "Received decrypted word: 0x" 
                          << std::hex << std::setw(8) << std::setfill('0') 
                          << dut->data_out << std::dec << std::endl;
            }
            was_busy = dut->busy;
            
            // Check if decryption is done
            if (word_index >= ciphertext_words.size() && !dut->busy && 
                decrypted_words.size() == ciphertext_words.size()) {
                done = true;
            }
        }
        
        dut->clk = !dut->clk; // Toggle clock
        
        // Evaluate model and dump trace
        dut->eval();
        tfp->dump(sim_time);
        sim_time++;
    }
    
    // Words to bytes
    for (uint32_t word : decrypted_words) {
        wordToBytes(word, decrypted_bytes);
    }
    
    // Trim padding
    while (decrypted_bytes.size() > plaintext_bytes.size()) {
        decrypted_bytes.pop_back();
    }
    
    std::cout << "\n=== Decryption Results ===" << std::endl;
    std::cout << "Ciphertext (" << ciphertext_words.size() << " words): ";
    for (uint32_t word : ciphertext_words) {
        std::cout << std::hex << std::setw(8) << std::setfill('0') << word << " ";
    }
    std::cout << std::dec << std::endl;
    
    std::cout << "Decrypted (" << decrypted_words.size() << " words): ";
    for (uint32_t word : decrypted_words) {
        std::cout << std::hex << std::setw(8) << std::setfill('0') << word << " ";
    }
    std::cout << std::dec << std::endl;
    
    std::string decryptedText(decrypted_bytes.begin(), decrypted_bytes.end());
    std::cout << "Decrypted text: \"" << decryptedText << "\"" << std::endl;
    
    // Verify decryption
    bool decryption_correct = true;
    for (size_t i = 0; i < plaintext_bytes.size(); i++) {
        if (i < decrypted_bytes.size() && plaintext_bytes[i] != decrypted_bytes[i]) {
            std::cout << "ERROR at byte " << i << ": Expected 0x" 
                      << std::hex << std::setw(2) << std::setfill('0') 
                      << static_cast<int>(plaintext_bytes[i])
                      << " ('" << plaintext_bytes[i] << "'), Got 0x" 
                      << std::setw(2) << std::setfill('0') 
                      << static_cast<int>(decrypted_bytes[i])
                      << " ('" << decrypted_bytes[i] << "')" << std::dec << std::endl;
            decryption_correct = false;
        }
    }
    
    if (decryption_correct) {
        std::cout << "\nSUCCESS: All bytes correctly decrypted!" << std::endl;
    }
    else {
        std::cout << "\nERROR: Decryption failed!" << std::endl;
    }
    
    // Cleanup
    tfp->close();
    return 0;
}
