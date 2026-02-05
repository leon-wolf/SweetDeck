class Sweetdeck < Formula
  desc "FlowDeck-like CLI for Xcode builds and simulator workflows"
  homepage "https://github.com/leon-wolf/SweetDeck"
  url "https://github.com/leon-wolf/SweetDeck/releases/download/v2026.02.2/sweetdeck-v2026.02.2-macos.zip"
  sha256 "b99b194e4c6fa32d042b667c4c32431f913e7c8321ef497df110bab8d13f9f40"
  version "2026.02.2"

  def install
    bin.install "sweetdeck"
  end

  test do
    system "#{bin}/sweetdeck", "--version"
  end
end
