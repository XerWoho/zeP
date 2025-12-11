class Zep < Formula
  desc "Fast package manager for Zig"
  homepage "https://github.com/XerWoho/zeP"
  license "GPLv3"

  on_macos do
    url "https://zep.run/releases/0.7/zep_x86_64-macos_0.7.tar.xz"
    sha256 "ad14f58986b6f81349674ae5ee280060b62a5a6363a644b90177b8e3483b63ac"
  end

  on_linux do
    url "https://zep.run/releases/0.7/zep_x86_64-linux_0.7.tar.xz"
    sha256 "eb349a36c9705f157d1722dc0ea082e11a28569e9c32b6835b642e0cf1b5f598"
  end

  def install
    bin.install "zeP" => "zep"
  end

    def post_install
		ohai "--- ZEP CONFIG REQUIRED ---"
		puts " ==> Run 'zeP setup' to configure zeP"
		puts " ==> Then run: zeP zep install 0.7"
	end

  test do
    system "#{bin}/zep", "--version"
  end
end
