class Sweetdeck < Formula
  desc "FlowDeck-like CLI for Xcode builds and simulator workflows"
  homepage "https://github.com/leon-wolf/SweetDeck"
  url "https://github.com/leon-wolf/SweetDeck/releases/download/v2026.02.2/sweetdeck-v2026.02.2-macos.zip"
  sha256 "07bacb88717c5019fa749a36d36c24e16a92953e6d49b135abc3ed4b8077033d"
  version "2026.02.2"

  def install
    bin.install "sweetdeck"
  end

  test do
    system "#{bin}/sweetdeck", "--version"
  end
end
