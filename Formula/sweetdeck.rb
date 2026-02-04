class Sweetdeck < Formula
  desc "FlowDeck-like CLI for Xcode builds and simulator workflows"
  homepage "https://github.com/leon-wolf/SweetDeck"
  url "https://github.com/leon-wolf/SweetDeck/releases/download/v__VERSION__/sweetdeck-v__VERSION__-macos.zip"
  sha256 "REPLACE_SHA256"
  version "__VERSION_NO_V__"

  def install
    bin.install "sweetdeck"
  end

  test do
    system "#{bin}/sweetdeck", "--version"
  end
end
