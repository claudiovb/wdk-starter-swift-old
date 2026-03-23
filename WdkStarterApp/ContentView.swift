import SwiftUI
import WdkSwiftCore

// MARK: - Navigation

enum Screen {
    case welcome, create, importWallet, home, send, receive, sign
}

enum Network: String {
    case btc, eth
}

// MARK: - View Model

@MainActor
class WalletViewModel: ObservableObject {
    @Published var currentScreen: Screen = .welcome
    @Published var seedPhrase: [String] = []
    @Published var importWords: [String] = Array(repeating: "", count: 12)
    @Published var importError: Bool = false
    @Published var toastMessage: String?
    @Published var toastIsSuccess: Bool = false
    @Published var isLoading: Bool = false
    @Published var statusText: String = ""

    // Wallet state
    @Published var ethAddress: String = ""
    @Published var ethBalance: String = "0"
    @Published var btcAddress: String = ""
    @Published var btcBalance: String = "0"
    @Published var isWdkInitialized: Bool = false

    // Send
    @Published var sendNetwork: Network = .eth
    @Published var sendAddress: String = ""
    @Published var sendAmount: String = ""

    // Receive
    @Published var receiveNetwork: Network = .eth

    // Sign
    @Published var signNetwork: Network = .eth
    @Published var signMessage: String = "Login to MyDApp\nTimestamp: 1711036800\nNonce: a3f8c2"

    // WDK internals
    private var client: WdkSwiftCore?
    private var encryptionKey: String = ""
    private var encryptedSeed: String = ""

    private let wdkConfig = """
    {
      "networks": {
        "sepolia": {
            "provider": "https://ethereum-sepolia-rpc.publicnode.com"
        },
        "bitcoin": {
          "client": {
            "type": "blockbook-http",
            "clientConfig": {
              "url": "https://blockbook.tbtc-1.zelcore.io/api"
            }
          },
          "network": "testnet"
        }
      }
    }
    """

    // MARK: - Navigation

    func navigate(to screen: Screen) {
        withAnimation(.easeInOut(duration: 0.25)) {
            currentScreen = screen
        }
    }

    // MARK: - Create Wallet

    func createWallet() {
        Task {
            isLoading = true
            statusText = "Generating seed phrase..."
            do {
                let wdk = getOrCreateClient()
                let entropy = try await wdk.generateEntropyAndEncrypt(wordCount: 12)
                encryptionKey = entropy.encryptionKey
                encryptedSeed = entropy.encryptedSeedBuffer

                let mnemonic = try await wdk.getMnemonicFromEntropy(
                    encryptedEntropy: entropy.encryptedEntropyBuffer,
                    encryptionKey: entropy.encryptionKey
                )
                seedPhrase = mnemonic.split(separator: " ").map(String.init)
                navigate(to: .create)
                isLoading = false
                statusText = ""
            } catch {
                isLoading = false
                statusText = ""
                showToast("Error: \(error.localizedDescription)")
            }
        }
    }

    func confirmSeedAndInitialize() {
        Task {
            isLoading = true
            statusText = "Initializing wallet..."

            let wdk = getOrCreateClient()
            do {
                try await wdk.initializeWDK(
                    encryptionKey: encryptionKey,
                    encryptedSeed: encryptedSeed,
                    config: wdkConfig
                )
                isWdkInitialized = true
            } catch {
                showToast("WDK init failed: \(error.localizedDescription)")
            }

            if let eth = try? await wdk.getAddress(network: "sepolia") {
                ethAddress = eth
            }
            if let btc = try? await wdk.getAddress(network: "bitcoin") {
                btcAddress = btc
            }

            navigate(to: .home)
            isLoading = false
            statusText = ""
            try? await fetchBalance()
        }
    }

    // MARK: - Import Wallet

    func doImport() {
        let words = importWords.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let filled = words.filter { !$0.isEmpty }
        if filled.count < 12 {
            importError = true
            return
        }
        importError = false

        let mnemonic = words.joined(separator: " ")
        Task {
            isLoading = true
            statusText = "Importing wallet..."

            let wdk = getOrCreateClient()
            do {
                let result = try await wdk.getSeedAndEntropyFromMnemonic(mnemonic: mnemonic)
                encryptionKey = result.encryptionKey
                encryptedSeed = result.encryptedSeedBuffer

                try await wdk.initializeWDK(
                    encryptionKey: encryptionKey,
                    encryptedSeed: encryptedSeed,
                    config: wdkConfig
                )
                isWdkInitialized = true
            } catch {
                showToast("Import failed: \(error.localizedDescription)")
            }

            if let eth = try? await wdk.getAddress(network: "sepolia") {
                ethAddress = eth
            }
            if let btc = try? await wdk.getAddress(network: "bitcoin") {
                btcAddress = btc
            }

            navigate(to: .home)
            isLoading = false
            statusText = ""
            try? await fetchBalance()
        }
    }

    // MARK: - Balance

    func fetchBalance() async throws {
        guard isWdkInitialized, let wdk = client else { return }
        do {
            let balance = try await wdk.getBalance(network: "sepolia")
            ethBalance = balance
        } catch {
            print("ETH balance fetch failed: \(error)")
        }
        do {
            let balance = try await wdk.getBalance(network: "bitcoin")
            btcBalance = balance
        } catch {
            print("BTC balance fetch failed: \(error)")
        }
    }

    func refreshBalance() {
        Task {
            try? await fetchBalance()
        }
    }

    // MARK: - Send (placeholder — wired for UI flow)

    func doSend() {
        guard !sendAddress.isEmpty, !sendAmount.isEmpty else {
            showToast("Please fill in address and amount")
            return
        }
        // TODO: Wire to actual callMethod for sendTransaction
        navigate(to: .home)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.showToast("Send not yet implemented — coming soon")
        }
    }

    // MARK: - Sign (placeholder)

    func doSign() {
        guard !signMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // TODO: Wire to actual callMethod for signMessage
        navigate(to: .home)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.showToast("Sign not yet implemented — coming soon")
        }
    }

    // MARK: - Helpers

    func showToast(_ message: String, success: Bool = false) {
        toastMessage = message
        toastIsSuccess = success
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if self.toastMessage == message {
                self.toastMessage = nil
            }
        }
    }

    private func getOrCreateClient() -> WdkSwiftCore {
        if let existing = client { return existing }
        let wdk = WdkSwiftCore()
        client = wdk
        return wdk
    }

    var receiveAddress: String {
        receiveNetwork == .eth ? ethAddress : btcAddress
    }

    var receiveLabel: String {
        receiveNetwork == .eth ? "Your Ethereum Sepolia address" : "Your Bitcoin Testnet address"
    }

    var sendFee: String {
        sendNetwork == .eth ? "~0.002 ETH" : "~0.00001 BTC"
    }

    var sendNetworkLabel: String {
        sendNetwork == .eth ? "Ethereum Sepolia" : "Bitcoin Testnet"
    }

    var sendTokenLabel: String {
        sendNetwork == .eth ? "ETH" : "BTC"
    }

    var formattedEthBalance: String {
        if let wei = Double(ethBalance) {
            let eth = wei / 1_000_000_000_000_000_000
            if eth == 0 { return "0.0000 ETH" }
            return String(format: "%.4f ETH", eth)
        }
        return "\(ethBalance) ETH"
    }

    var formattedBtcBalance: String {
        if let satoshis = Double(btcBalance) {
            let btc = satoshis / 100_000_000
            if btc == 0 { return "0.0000 BTC" }
            return String(format: "%.4f BTC", btc)
        }
        return "\(btcBalance) BTC"
    }
}

// MARK: - Root View

struct ContentView: View {
    @StateObject private var vm = WalletViewModel()

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            Group {
                switch vm.currentScreen {
                case .welcome:      WelcomeScreen(vm: vm)
                case .create:       CreateWalletScreen(vm: vm)
                case .importWallet: ImportWalletScreen(vm: vm)
                case .home:         HomeScreen(vm: vm)
                case .send:         SendScreen(vm: vm)
                case .receive:      ReceiveScreen(vm: vm)
                case .sign:         SignMessageScreen(vm: vm)
                }
            }

            // Loading overlay
            if vm.isLoading {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    if !vm.statusText.isEmpty {
                        Text(vm.statusText)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
            }

            // Toast overlay
            if let msg = vm.toastMessage {
                VStack {
                    Text(msg)
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(vm.toastIsSuccess ? Color.green : Color.accentColor)
                        )
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .padding(.top, 8)
                .animation(.easeOut(duration: 0.3), value: vm.toastMessage != nil)
            }
        }
    }
}

// MARK: - Reusable Components

struct ScreenHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().stroke(Color(.separator), lineWidth: 1))
            }
            Text(title)
                .font(.system(size: 16, weight: .bold))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

struct NetworkPill: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(icon)
                Text(label)
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.accentColor : Color(.separator), lineWidth: 1)
            )
            .foregroundColor(isSelected ? .accentColor : .secondary)
        }
    }
}

struct TestnetBadge: View {
    var body: some View {
        Text("Testnet")
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.15))
            .foregroundColor(.orange)
            .cornerRadius(6)
    }
}

struct PrimaryButton: View {
    let title: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 12).fill(disabled ? Color.gray : Color.accentColor))
        }
        .disabled(disabled)
    }
}

struct OutlineButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor, lineWidth: 2)
                )
        }
    }
}

struct SeedWordCell: View {
    let index: Int
    let word: String

    var body: some View {
        HStack(spacing: 6) {
            Text("\(index)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(minWidth: 18, alignment: .leading)
            Text(word)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }
}

struct SeedInputCell: View {
    let index: Int
    @Binding var word: String

    var body: some View {
        HStack(spacing: 6) {
            Text("\(index)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(minWidth: 18, alignment: .leading)
            TextField("word", text: $word)
                .font(.system(size: 13))
                .autocapitalization(.none)
                .disableAutocorrection(true)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }
}

#Preview {
    ContentView()
}
