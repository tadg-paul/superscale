class Superscale < Formula
  desc "AI image upscaling for Apple Silicon"
  homepage "https://github.com/tigger04/superscale"
  url "https://github.com/tigger04/superscale/archive/refs/tags/v0.2.2.tar.gz"
  sha256 "a425907943a6adde7a8bf9467ca506f34ecd34722cdda2c4c961cb621b0604a0"
  license "MIT"

  depends_on :macos
  depends_on arch: :arm64


  resource "RealESRGAN_x4plus" do
    url "https://github.com/tigger04/superscale/releases/download/models-v1/RealESRGAN_x4plus.mlpackage.zip"
    sha256 "66c6ce19ebf060378f0a9d6fc2a09b22f147a52893a576aa37b7991b551eaaf0"
  end

  resource "RealESRGAN_x2plus" do
    url "https://github.com/tigger04/superscale/releases/download/models-v1/RealESRGAN_x2plus.mlpackage.zip"
    sha256 "a09453aa035be72abb9e6a84d283a5bad5fd148417017f279550c77c304fc7c2"
  end

  resource "RealESRNet_x4plus" do
    url "https://github.com/tigger04/superscale/releases/download/models-v1/RealESRNet_x4plus.mlpackage.zip"
    sha256 "c826dbe99cc47a6e46216660ada98e41c1bd7df65fd9c6df504dc34a3916ffcc"
  end

  resource "RealESRGAN_x4plus_anime_6B" do
    url "https://github.com/tigger04/superscale/releases/download/models-v1/RealESRGAN_x4plus_anime_6B.mlpackage.zip"
    sha256 "2c6ed71bb38a2bc06c6ef93840d17c55a31ecbe8dfed8766959ac2a9be2ff020"
  end

  resource "realesr-animevideov3" do
    url "https://github.com/tigger04/superscale/releases/download/models-v1/realesr-animevideov3.mlpackage.zip"
    sha256 "98dfd469c3789a1ca1f33e01e307751205e987ed2d14b289b13bbfe9fb3dc1b1"
  end

  resource "realesr-general-x4v3" do
    url "https://github.com/tigger04/superscale/releases/download/models-v1/realesr-general-x4v3.mlpackage.zip"
    sha256 "4d5ee58b2251a61ef6649f99e89f099fc6ae6fafc72df2cb63baaf83c7e93c61"
  end

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/superscale"

    # Install all models alongside binary (Cellar prefix layout)
    %w[
      RealESRGAN_x4plus
      RealESRGAN_x2plus
      RealESRNet_x4plus
      RealESRGAN_x4plus_anime_6B
      realesr-animevideov3
      realesr-general-x4v3
    ].each do |model|
      resource(model).stage do
        (prefix/"models").install "#{model}.mlpackage"
      end
    end
  end

  def caveats
    <<~EOS
      All six upscaling models are bundled and ready to use.

      List available models:
        superscale --list-models

      Auto-detection selects the best model for your image.
      Override with -m <model-name> if needed.
    EOS
  end

  test do
    assert_match "0.2.2", shell_output("#{bin}/superscale --version")
    assert_match "realesrgan-x4plus", shell_output("#{bin}/superscale --list-models")
  end
end
