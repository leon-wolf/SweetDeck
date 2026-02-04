class Sweetdeck < Formula
  desc "FlowDeck-like CLI for Xcode builds and simulator workflows"
  homepage "https://github.com/leon-wolf/SweetDeck"
  url "https://github.com/leon-wolf/SweetDeck/releases/download/v0.1.0/sweetdeck-v0.1.0-macos.zip"
  sha256 "REPLACE_SHA256"
  version "0.1.0"

  def install
    bin.install "sweetdeck"
  end

  test do
    system "#{bin}/sweetdeck", "--version"
  end
end

