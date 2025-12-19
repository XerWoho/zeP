class Zep < Formula
  desc "Fast package manager for Zig"
  homepage "https://github.com/XerWoho/zeP"
  license "GPLv3"

  on_macos do
    url "https://zep.run/releases/0.8/zep_x86_64-macos_0.8.tar.xz"
    sha256 "12dd94a0effb0226b8436a912ddd44788805277878382207bc0bb1b52323417a"
  end

  on_linux do
    url "https://zep.run/releases/0.8/zep_x86_64-linux_0.8.tar.xz"
    sha256 "61da5e4164913072404c273aae6966cc86f76d830e8f59462973986a6b558945"
  end

  def install
    bin.install "zep" => "zep"
  end

    def post_install
		ohai "--- ZEP CONFIG REQUIRED ---"
		puts " ==> Run 'zep setup' to configure zep"
		puts " ==> Then run: zep zep install 0.8"
	end

  test do
    system "#{bin}/zep", "version"
  end
end
