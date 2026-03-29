cask "superscale-gui" do
  version "1.0.1"
  sha256 "cb1a0cb430a5ea69d1e78bb3d20d8bc862f649ae5705d4bec31136d4ec0e0f1b"

  url "https://github.com/tigger04/superscale/releases/download/v1.0.1/Superscale.dmg"
  name "Superscale"
  desc "AI image upscaling for Apple Silicon"
  homepage "https://github.com/tigger04/superscale"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "Superscale.app"

  postflight do
    # Install shared models if not already present (e.g. from CLI install)
    models_dir = Pathname("#{Dir.home}/Library/Application Support/superscale/models")
    models_dir.mkpath unless models_dir.exist?

    # Models are downloaded separately via the CLI or brew install superscale
    # If neither is installed, inform the user
    unless models_dir.children.any? { |c| c.extname == ".mlpackage" }
      ohai "Models not found. Install them with:"
      ohai "  brew install tigger04/tap/superscale"
      ohai "Or download manually — see https://github.com/tigger04/superscale#readme"
    end
  end

  zap trash: [
    "~/Library/Application Support/superscale",
    "~/Library/Caches/superscale",
  ]

  caveats <<~EOS
    Superscale GUI shares models with the CLI tool.
    If you also have the CLI installed (brew install superscale),
    both use the same model files — no duplication.

    If the CLI is not installed, models will be downloaded on first use.
  EOS
end
