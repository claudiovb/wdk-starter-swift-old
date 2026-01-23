import SwiftUI
import WdkSwiftCore

struct ContentView: View {
    @State private var status: String = "Ready to test WDK"
    @State private var result: String = ""
    @State private var isLoading: Bool = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Logo/Icon
                Image(systemName: "key.fill")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.blue)
                    .padding(.top, 40)
                
                // Title
                Text("WDK Starter Swift")
                    .font(.title)
                    .fontWeight(.bold)
                
                // Status section
                VStack(spacing: 15) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(1.5)
                    } else {
                        Image(systemName: result.isEmpty ? "questionmark.circle" : (result.contains("Error") ? "xmark.circle.fill" : "checkmark.circle.fill"))
                            .resizable()
                            .frame(width: 50, height: 50)
                            .foregroundColor(result.isEmpty ? .gray : (result.contains("Error") ? .red : .green))
                    }
                    
                    Text(status)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    if !result.isEmpty {
                        ScrollView {
                            Text(result)
                                .font(.caption)
                                .multilineTextAlignment(.leading)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                        .frame(maxHeight: 200)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                )
                .padding(.horizontal)
                
                // Test button
                Button(action: {
                    Task {
                        await testWdk()
                    }
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Test WDK")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                .disabled(isLoading)
                
                Spacer()
                
                // Footer
                Text("WDK Swift Core Demo")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 20)
            }
            .navigationBarHidden(true)
        }
    }
    
    func testWdk() async {
        isLoading = true
        status = "Testing WDK..."
        result = ""
        
        do {
            // Initialize client
            let client = WdkSwiftCore()
            
            // Test 1: Start worklet
            status = "Starting worklet..."
            try await client.workletStart()
            result += "✅ Worklet started\n"
            
            // Test 2: Generate entropy
            status = "Generating entropy..."
            let entropy = try await client.generateEntropyAndEncrypt(wordCount: 12)
            result += "✅ Entropy generated\n"
            result += "Key: \(entropy.encryptionKey.prefix(20))...\n"
            result += "Seed: \(entropy.encryptedSeedBuffer.prefix(20))...\n"
            
            // Test 3: Get mnemonic
            status = "Getting mnemonic..."
            let mnemonic = try await client.getMnemonicFromEntropy(
                encryptedEntropy: entropy.encryptedEntropyBuffer,
                encryptionKey: entropy.encryptionKey
            )
            result += "✅ Mnemonic retrieved\n"
            result += "Words: \(mnemonic.split(separator: " ").prefix(3).joined(separator: " "))...\n"
            
            status = "✅ All tests passed!"
            isLoading = false
            
        } catch {
            result = "❌ Error: \(error.localizedDescription)"
            status = "Test failed"
            isLoading = false
        }
    }
}

#Preview {
    ContentView()
}
