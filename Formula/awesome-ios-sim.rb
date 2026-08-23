class AwesomeIosSim < Formula
  desc "Simulator State as Code for iOS developers and AI agents"
  homepage "https://github.com/qubyyang/awesome-ios-sim"
  version "0.1.0"
  license "MIT"
  depends_on macos: :ventura

  on_macos do
    on_arm do
      url "https://github.com/qubyyang/awesome-ios-sim/releases/download/v0.1.0/awesome-ios-sim-0.1.0-macos-arm64.tar.gz"
      sha256 "88df6aed98ebf8f88ff23e80fc2873534de7278aab4cc5e6116cec74bf097d65"
    end

    on_intel do
      url "https://github.com/qubyyang/awesome-ios-sim/releases/download/v0.1.0/awesome-ios-sim-0.1.0-macos-x86_64.tar.gz"
      sha256 "88be5aea6a803f20f4b02e9d370ba80cb13d914942b290814c0c02f9cce6d793"
    end
  end

  def install
    architecture = Hardware::CPU.arm? ? "arm64" : "x86_64"
    package = "awesome-ios-sim-#{version}-macos-#{architecture}"
    bin.install "#{package}/bin/ios-sim-state"
    bin.install "#{package}/bin/ios-sim-state-mcp"
    doc.install "#{package}/README.md"
    doc.install "#{package}/README.zh-CN.md"
    prefix.install "#{package}/RELEASE-METADATA.json"
  end

  test do
    assert_equal version.to_s, shell_output("#{bin}/ios-sim-state --version").strip
    assert_equal version.to_s, shell_output("#{bin}/ios-sim-state-mcp --version").strip
  end
end
