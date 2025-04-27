#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vchacha20_top.h"
#include <iostream>
#include <vector>
#include <random>
#include <iomanip>
#include <memory>

// Maximum simulation time
#define MAX_SIM_TIME 20000


const std::string TEST_MESSAGE = "Very very secret message";

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
    std::vector<uint8_t> plaintext;
    std::vector<uint8_t> ciphertext;
    std::vector<uint8_t> decrypted;
    
    for (char c : TEST_MESSAGE) {
        plaintext.push_back(static_cast<uint8_t>(c));
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
    std::cout << "Hex: ";
    for (uint8_t byte : plaintext) {
        std::cout << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(byte);
    }
    std::cout << std::dec << std::endl;
    
    unsigned long sim_time = 20;  // Start after reset cycles
    bool done = false;
    size_t byte_index = 0;
    bool byte_sent = false;
    bool was_busy = false;
    
    std::cout << "\n--- ENCRYPTION ---" << std::endl;
    
    // Encrypt bytes (one at a time)
    while (sim_time < MAX_SIM_TIME/2 && !done) {
        if (dut->clk) { // Process on positive clock edge
            // Check if the module is busy
            if (byte_sent && dut->busy) {
                dut->data_valid = 0;
                byte_sent = false;
            }
            // If the module is not busy and we haven't sent all bytes, send next byte
            else if (!dut->busy && byte_index < plaintext.size()) {
                dut->data_in = plaintext[byte_index];
                dut->data_valid = 1;
                byte_sent = true;
                std::cout << "Sending byte " << byte_index << " for encryption: 0x" 
                          << std::hex << std::setw(2) << std::setfill('0') 
                          << static_cast<int>(plaintext[byte_index]) 
                          << " ('" << plaintext[byte_index] << "')" << std::dec << std::endl;
                byte_index++;
            }
            
            // Capture output when the module transitions from busy to not busy
            if (was_busy && !dut->busy && ciphertext.size() < plaintext.size()) {
                ciphertext.push_back(dut->data_out);
                std::cout << "Received encrypted byte: 0x" 
                          << std::hex << std::setw(2) << std::setfill('0') 
                          << static_cast<int>(dut->data_out) << std::dec << std::endl;
            }
            was_busy = dut->busy;
            
            // Check if encryption is done
            if (byte_index >= plaintext.size() && !dut->busy && ciphertext.size() == plaintext.size()) {
                done = true;
            }
        }
        
        dut->clk = !dut->clk; // Toggle clock
        
        // Evaluate model and dump trace
        dut->eval();
        tfp->dump(sim_time);
        sim_time++;
    }
    
    std::cout << "\n=== Encryption Results ===" << std::endl;
    std::cout << "Plaintext (" << plaintext.size() << " bytes): ";
    for (uint8_t byte : plaintext) {
        std::cout << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(byte);
    }
    std::cout << std::dec << std::endl;
    
    std::cout << "Ciphertext (" << ciphertext.size() << " bytes): ";
    for (uint8_t byte : ciphertext) {
        std::cout << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(byte);
    }
    std::cout << std::dec << std::endl;
    
    if (ciphertext.size() != plaintext.size()) {
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
    byte_index = 0;
    byte_sent = false;
    was_busy = false;
    
    std::cout << "\n--- DECRYPTION PHASE ---" << std::endl;
    
    // Decrypt bytes (one at a time)
    while (sim_time < MAX_SIM_TIME && !done) {
        if (dut->clk) { // Process on positive clock edge
            // Check if the module is busy
            if (byte_sent && dut->busy) {
                dut->data_valid = 0;
                byte_sent = false;
            }
            // If the module is not busy and we haven't sent all bytes, send the next byte
            else if (!dut->busy && byte_index < ciphertext.size()) {
                dut->data_in = ciphertext[byte_index];
                dut->data_valid = 1;
                byte_sent = true;
                std::cout << "Sending byte " << byte_index << " for decryption: 0x" 
                          << std::hex << std::setw(2) << std::setfill('0') 
                          << static_cast<int>(ciphertext[byte_index]) << std::dec << std::endl;
                byte_index++;
            }
            
            // Capture output when the module transitions from busy to not busy
            if (was_busy && !dut->busy && decrypted.size() < ciphertext.size()) {
                decrypted.push_back(dut->data_out);
                std::cout << "Received decrypted byte: 0x" 
                          << std::hex << std::setw(2) << std::setfill('0') 
                          << static_cast<int>(dut->data_out) 
                          << " ('" << (char)dut->data_out << "')" << std::dec << std::endl;
            }
            was_busy = dut->busy;
            
            // Check if decryption is done
            if (byte_index >= ciphertext.size() && !dut->busy && decrypted.size() == ciphertext.size()) {
                done = true;
            }
        }
        
        dut->clk = !dut->clk; // Toggle clock
        
        // Evaluate model and dump trace
        dut->eval();
        tfp->dump(sim_time);
        sim_time++;
    }
    
    std::cout << "\n=== Decryption Results ===" << std::endl;
    std::cout << "Ciphertext (" << ciphertext.size() << " bytes): ";
    for (uint8_t byte : ciphertext) {
        std::cout << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(byte) << " ";
    }
    std::cout << std::dec << std::endl;
    
    std::cout << "Decrypted (" << decrypted.size() << " bytes): ";
    for (uint8_t byte : decrypted) {
        std::cout << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(byte) << " ";
    }
    std::cout << std::dec << std::endl;
    
    std::string decryptedText(decrypted.begin(), decrypted.end());
    std::cout << "Decrypted text: \"" << decryptedText << "\"" << std::endl;
    
    // Verify decryption
    bool decryption_correct = true;
    for (size_t i = 0; i < plaintext.size(); i++) {
        if (i < decrypted.size() && plaintext[i] != decrypted[i]) {
            std::cout << "ERROR at byte " << i << ": Expected 0x" 
                      << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(plaintext[i])
                      << " ('" << (char)plaintext[i] << "'), Got 0x" 
                      << std::setw(2) << std::setfill('0') << static_cast<int>(decrypted[i])
                      << " ('" << (char)decrypted[i] << "')" << std::dec << std::endl;
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
