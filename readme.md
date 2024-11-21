```markdown
# Dotfiles Configuration for macOS

This repository contains my personal configurations for various tools and applications, stored in the `~/.config` directory. It is designed to streamline the setup process for future macOS installations.

---

## 🔧 Tools and Configurations Included
The repository is structured as follows:

```plaintext
├── bat
├── borders
├── bpytop
├── coc
├── git
├── herd-lite
├── iterm2
├── kitty
├── lsd
├── neofetch
├── nvim
├── sketchybar
├── skhd
├── yabai
├── yazi
└── zsh
```

---

## 🚀 Setup Instructions

### 1. Clone the Repository
To get started, clone this repository into your home directory:

```bash
git clone <your-repo-url> ~/.config
```

Replace `<your-repo-url>` with the actual URL of your repository.

---

### 2. Set Up the Configuration
Run the following command to ensure all configurations are properly applied and permissions are set:

```bash
rsync -a ~/.config/ ~/Library/Application\ Support/ && chmod -R 755 ~/.config
```

This command will:
- Synchronize your `.config` folder to `~/Library/Application Support` for apps like iTerm2.
- Ensure appropriate read, write, and execute permissions.

---

### 3. Optional: Zsh Configuration
If you're using Zsh and want to source your custom configurations, ensure your `~/.zshenv` file includes the following:

```bash
export ZDOTDIR=$HOME/.config/zsh
```

This will make Zsh load configurations from `~/.config/zsh`.

---

## 🛠 Customization
Feel free to modify any configuration files in the repository to suit your needs. Below are some key files you might want to customize:

- **`zsh/aliases.zsh`**: Your shell aliases.
- **`nvim/init.vim`**: Neovim settings and plugins.
- **`sketchybar/init.lua`**: SketchyBar UI and behavior.
- **`yabai/yabairc`**: Window manager rules.
- **`kitty/config`**: Terminal emulator settings.

---

## 📄 Notes
- For SketchyBar and Yabai, ensure their respective services are running:

```bash
brew services start sketchybar
brew services start yabai
```

- Update submodules if required (for plugins or themes):

```bash
git submodule update --init --recursive
```

- Refer to individual tool documentation for more advanced configuration options.

---

## 💡 Future Installations
After cloning this repository, the setup process is automated to ensure a smooth and consistent environment across devices.

Aquí tienes nuevamente la sección **Future Installations**, completa y corregida:

```markdown
## 💡 Future Installations
After cloning this repository, the setup process is streamlined to ensure a smooth and consistent environment across devices. Here are the steps to follow:

1. **Clone the Repository**
   Run the following command to download the repository to your `.config` directory:
   ```bash
   git clone <your-repo-url> ~/.config
   ```

2. **Apply Configurations**
   Use `rsync` to ensure all configurations are copied to their expected locations and permissions are set correctly:
   ```bash
   rsync -a ~/.config/ ~/Library/Application\ Support/ && chmod -R 755 ~/.config
   ```

3. **Start Necessary Services**
   Some tools require background services to run (e.g., SketchyBar, Yabai). Start them using:
   ```bash
   brew services start sketchybar
   brew services start yabai
   ```

4. **Verify Dependencies**
   Ensure all required tools are installed (e.g., Neovim, Zsh, SketchyBar, Yabai). You can use Homebrew to install missing dependencies:
   ```bash
   brew install <package-name>
   ```

5. **Update Submodules**
   If your repository includes submodules for plugins or themes, initialize and update them:
   ```bash
   git submodule update --init --recursive
   ```

6. **Set Zsh Configurations**
   Update the `~/.zshenv` file to source Zsh configurations from `.config/zsh`:
   ```bash
   export ZDOTDIR=$HOME/.config/zsh
   ```

After completing these steps, your macOS environment will be fully configured with all your personalized settings. 🎉
```